#!/usr/bin/env python3
"""
zx0.py - a Python port of Einar Saukas' ZX0 compressor (v2 format),
plus a decompressor for round-trip verification.

Ported line-for-line from the reference C (optimize.c + compress.c,
(c) 2021 Einar Saukas, BSD-3 licence, https://github.com/einar-saukas/ZX0)
in its DEFAULT mode: forwards, inverted new-offset-MSB gamma (that is,
`zx0` with no flags). The 6502 depacker in src/zx0depack.asm decodes
exactly this format; change one and you must change the other.

Used by export_bbc.py to compress the sixteen deck maps into bank 4.
"""

INITIAL_OFFSET = 1
MAX_OFFSET_ZX0 = 32640


class Block:
    __slots__ = ('chain', 'bits', 'index', 'offset')

    def __init__(self, bits, index, offset, chain):
        self.bits = bits
        self.index = index
        self.offset = offset
        self.chain = chain


def elias_gamma_bits(value):
    bits = 1
    while value > 1:
        value >>= 1
        bits += 2
    return bits


def offset_ceiling(index, offset_limit):
    return offset_limit if index > offset_limit else (
        INITIAL_OFFSET if index < INITIAL_OFFSET else index)


def optimize(input_data, skip=0, offset_limit=MAX_OFFSET_ZX0):
    input_size = len(input_data)
    max_offset = offset_ceiling(input_size - 1, offset_limit)

    last_literal = [None] * (max_offset + 1)
    last_match = [None] * (max_offset + 1)
    optimal = [None] * input_size
    match_length = [0] * (max_offset + 1)
    best_length = [0] * input_size
    if input_size > 2:
        best_length[2] = 2

    last_match[INITIAL_OFFSET] = Block(-1, skip - 1, INITIAL_OFFSET, None)

    for index in range(skip, input_size):
        best_length_size = 2
        max_offset = offset_ceiling(index, offset_limit)
        for offset in range(1, max_offset + 1):
            if index != skip and index >= offset and \
                    input_data[index] == input_data[index - offset]:
                ll = last_literal[offset]
                if ll is not None:
                    length = index - ll.index
                    bits = ll.bits + 1 + elias_gamma_bits(length)
                    last_match[offset] = Block(bits, index, offset, ll)
                    if optimal[index] is None or optimal[index].bits > bits:
                        optimal[index] = last_match[offset]
                match_length[offset] += 1
                if match_length[offset] > 1:
                    if best_length_size < match_length[offset]:
                        bits = optimal[index - best_length[best_length_size]].bits + \
                            elias_gamma_bits(best_length[best_length_size] - 1)
                        while True:
                            best_length_size += 1
                            bits2 = optimal[index - best_length_size].bits + \
                                elias_gamma_bits(best_length_size - 1)
                            if bits2 <= bits:
                                best_length[best_length_size] = best_length_size
                                bits = bits2
                            else:
                                best_length[best_length_size] = \
                                    best_length[best_length_size - 1]
                            if best_length_size >= match_length[offset]:
                                break
                    length = best_length[match_length[offset]]
                    bits = optimal[index - length].bits + 8 + \
                        elias_gamma_bits((offset - 1) // 128 + 1) + \
                        elias_gamma_bits(length - 1)
                    lm = last_match[offset]
                    if lm is None or lm.index != index or lm.bits > bits:
                        last_match[offset] = Block(bits, index, offset,
                                                   optimal[index - length])
                        if optimal[index] is None or optimal[index].bits > bits:
                            optimal[index] = last_match[offset]
            else:
                match_length[offset] = 0
                lm = last_match[offset]
                if lm is not None:
                    length = index - lm.index
                    bits = lm.bits + 1 + elias_gamma_bits(length) + length * 8
                    last_literal[offset] = Block(bits, index, 0, lm)
                    if optimal[index] is None or optimal[index].bits > bits:
                        optimal[index] = last_literal[offset]

    return optimal[input_size - 1]


class _Writer:
    def __init__(self):
        self.out = bytearray()
        self.bit_mask = 0
        self.bit_index = 0
        self.backtrack = True

    def write_byte(self, value):
        self.out.append(value & 0xFF)

    def write_bit(self, value):
        if self.backtrack:
            if value:
                self.out[-1] |= 1
            self.backtrack = False
        else:
            if not self.bit_mask:
                self.bit_mask = 128
                self.bit_index = len(self.out)
                self.write_byte(0)
            if value:
                self.out[self.bit_index] |= self.bit_mask
            self.bit_mask >>= 1

    def write_gamma(self, value, invert):
        i = 2
        while i <= value:
            i <<= 1
        i >>= 2
        while i > 0:
            self.write_bit(0)                       # forwards: continuation 0
            bit = 1 if (value & i) else 0
            self.write_bit(bit ^ 1 if invert else bit)
            i >>= 1
        self.write_bit(1)                           # forwards: terminator 1


def compress(input_data, skip=0, offset_limit=MAX_OFFSET_ZX0):
    """The default zx0 v2 stream for input_data (forwards, inverted MSB)."""
    optimal = optimize(input_data, skip, offset_limit)

    # un-reverse the chain
    prev = None
    while optimal is not None:
        nxt = optimal.chain
        optimal.chain = prev
        prev = optimal
        optimal = nxt

    w = _Writer()
    w.backtrack = True
    last_offset = INITIAL_OFFSET
    input_index = skip

    node = prev.chain
    prev_node = prev
    while node is not None:
        length = node.index - prev_node.index
        if node.offset == 0:
            w.write_bit(0)
            w.write_gamma(length, False)
            for _ in range(length):
                w.write_byte(input_data[input_index])
                input_index += 1
        elif node.offset == last_offset:
            w.write_bit(0)
            w.write_gamma(length, False)
            input_index += length
        else:
            w.write_bit(1)
            w.write_gamma((node.offset - 1) // 128 + 1, True)
            w.write_byte((127 - (node.offset - 1) % 128) << 1)
            w.backtrack = True
            w.write_gamma(length - 1, False)
            input_index += length
            last_offset = node.offset
        prev_node = node
        node = node.chain

    w.write_bit(1)
    w.write_gamma(256, True)
    return bytes(w.out)


def decompress(z):
    """Round-trip verifier for the default v2 stream."""
    out = bytearray()
    pos = 0
    bit_mask = 0
    bit_byte = 0
    backtrack = [None]     # holds the offset-LSB byte whose bit 0 is the
                           # next control bit, mirroring the compressor

    def bit():
        nonlocal bit_mask, bit_byte, pos
        if backtrack[0] is not None:
            b = backtrack[0] & 1
            backtrack[0] = None
            return b
        if not bit_mask:
            bit_byte = z[pos]
            pos += 1
            bit_mask = 128
        b = 1 if (bit_byte & bit_mask) else 0
        bit_mask >>= 1
        return b

    def gamma(invert):
        v = 1
        while not bit():
            d = bit()
            if invert:
                d ^= 1
            v = (v << 1) | d
        return v

    last_offset = INITIAL_OFFSET
    state = 'literals'
    while True:
        if state == 'literals':
            length = gamma(False)
            out.extend(z[pos:pos + length])
            pos += length
            state = 'new' if bit() else 'copy'
        elif state == 'copy':
            length = gamma(False)
            for _ in range(length):
                out.append(out[-last_offset])
            state = 'new' if bit() else 'literals'
        else:                                       # new offset
            msb = gamma(True)
            if msb == 256:
                return bytes(out)
            lsb = z[pos]
            pos += 1
            last_offset = (msb - 1) * 128 + (127 - (lsb >> 1)) + 1
            backtrack[0] = lsb                      # gamma starts in its bit 0
            length = gamma(False) + 1
            for _ in range(length):
                out.append(out[-last_offset])
            state = 'new' if bit() else 'literals'


if __name__ == '__main__':
    import sys
    data = open(sys.argv[1], 'rb').read()
    z = compress(data)
    print('%d -> %d' % (len(data), len(z)))
    assert decompress(z) == data, 'round-trip FAILED'
    print('round-trip ok')
    if len(sys.argv) > 2:
        open(sys.argv[2], 'wb').write(z)
