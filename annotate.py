#!/usr/bin/env python3
"""
annotate.py  —  Generate a Level7/bbcelite-style annotated assembly listing
                from the Paradroid CE IDA disassembly (paradroid_ce.lst).

Outputs paradroid_ce_annotated.asm with:
  • Structured header blocks for every subroutine and named variable
  • Inline [C64: …] annotations for every hardware register access
  • Section banners at major address boundaries
  • C64 hardware constant definitions at the top
"""

import re
import sys
from datetime import date

# ---------------------------------------------------------------------------
# File paths
# ---------------------------------------------------------------------------
INPUT_FILE  = r'C:\Users\khcon\OneDrive\Projects\Paradroid\paradroid_ce.lst'
OUTPUT_FILE = r'C:\Users\khcon\OneDrive\Projects\Paradroid\paradroid_ce_annotated.asm'

# ---------------------------------------------------------------------------
# Known function database  (addr -> detail dict)
# ---------------------------------------------------------------------------
KNOWN_FUNCTIONS = {
    0x0500: dict(
        category='Sound',
        summary='SID music and sound effects driver',
        detail=(
            'Called from Irq_118 at 50 Hz. Drives up to 3 SID voices\n'
            '; using zero-page channel state ($80-$CF). Handles note\n'
            '; triggers, frequency slides, vibrato, and\n'
            '; attack/decay/sustain envelope.'
        ),
    ),
    0x091A: dict(
        category='Input',
        summary='Read joystick direction from CIA1 port B ($DC01)',
        detail=(
            'Pulses CIA1 port A ($DC00) with $FF to select joystick\n'
            '; port 2, then reads port B ($DC01) bits 0-3 for\n'
            '; direction and bit 4 for the fire button.\n'
            '; Writes joyXDir, joyYDir, joyFire in zero page.'
        ),
    ),
    0x0966: dict(
        category='Sprite management',
        summary='Read VIC-II sprite registers into zero page scratch variables',
        detail=(
            'Reads hardware sprite registers for sprite N (SpriteNum\n'
            '; at $04) from the VIC-II chip ($D000-$D01F) into zero\n'
            '; page scratch variables $05-$0E.\n'
            ';\n'
            '; C64 hardware: VIC-II sprite X ($D000+N*2), Y ($D001+N*2),\n'
            '; enable ($D015), colour ($D027+N), multicolour ($D01C),\n'
            '; expand ($D01D/$D017), priority ($D01B).'
        ),
    ),
    0x09B7: dict(
        category='Sprite management',
        summary='Write zero page sprite variables back to VIC-II registers',
        detail=(
            'Inverse of RdSpriteState. Writes ZP scratch variables\n'
            '; for sprite N back to VIC-II hardware registers.\n'
            '; Uses bit-mask table at bits: ($095E) to set/clear\n'
            '; individual bits in shared VIC-II control bytes.'
        ),
    ),
    0x0A52: dict(
        category='Screen',
        summary='Fill Color RAM ($D800-$DBFF) with a constant colour byte',
        detail=(
            'Uses a 16-bit destination pointer (ZP $1C-$1D) to write\n'
            '; 1000 bytes to Color RAM at $D800. Called during screen\n'
            '; mode initialisation.'
        ),
    ),
    0x0A7D: dict(
        category='Score',
        summary='BCD score arithmetic and render digits to screen RAM',
        detail=(
            'Performs BCD addition using SED/CLD on the packed-BCD\n'
            '; score variable, then writes the resulting decimal\n'
            '; digits to screen RAM.'
        ),
    ),
    0x0B6E: dict(
        category='System',
        summary='Control tape motor via 6510 processor port ($01)',
        detail=(
            'Sets or clears the cassette motor control bit in the\n'
            '; 6510 on-chip I/O port at $01. Used to start/stop\n'
            '; tape loading.'
        ),
    ),
    0x1242: dict(
        category='Initialisation',
        summary='Initialise VIC-II, CIA, and SID for game start',
        detail=(
            'Sets up all C64 hardware for gameplay: VIC-II display\n'
            '; mode, sprite registers, SID volume, CIA interrupt\n'
            '; vectors. Also clears game state variables.'
        ),
    ),
    0x13DA: dict(
        category='Main loop',
        summary='Main game loop — wait for IRQ frame sync then dispatch',
        detail=(
            'Spins waiting for the raster IRQ frame-sync flag set\n'
            '; by Irq_254, then calls RunGame once per 50 Hz frame.\n'
            '; Also contains the per-frame sprite update loop.'
        ),
    ),
    0x1545: dict(
        category='Main loop',
        summary='Per-frame game dispatch — droids, collisions, display',
        detail=(
            'Called once per frame from GameLoop. Dispatches droid\n'
            '; AI (RunDroids), collision detection (DoCollision),\n'
            '; and screen update (DrawScreen).'
        ),
    ),
    0x1700: dict(
        category='Droid AI',
        summary='Iterate all active droids and call their mode handler',
        detail=(
            'Loops through the droid table and calls the mode-dispatch\n'
            '; jump table (DroidModeJump) for each active droid\n'
            '; (modes 0-7).'
        ),
    ),
    0x18CA: dict(
        category='Droid AI',
        summary='Droid mode 0 — pathfinding, shooting, and chasing player',
        detail=(
            'The main enemy droid behaviour handler. Reads sprite\n'
            '; state via RdSpriteState, chooses movement direction\n'
            '; via pathfinding tables, fires at the player, and\n'
            '; writes back via WrSpriteState.'
        ),
    ),
    0x1BC1: dict(
        category='Droid AI',
        summary='Bullet movement and wall collision',
        detail=(
            'Moves a bullet sprite by its velocity vector each frame.\n'
            '; If the bullet hits a wall tile it is destroyed.'
        ),
    ),
    0x1BF6: dict(
        category='Collision',
        summary='Friendly fire — droid bullet hits another droid',
        detail=(
            'Checks whether a bullet sprite has hit a non-player\n'
            '; droid and triggers KillDroid if so.'
        ),
    ),
    0x1C0F: dict(
        category='Collision',
        summary='Player fire hits enemy droid',
        detail=(
            'Checks whether a player bullet has hit an enemy droid\n'
            '; and applies damage / triggers explosion.'
        ),
    ),
    0x1C39: dict(
        category='Droid AI',
        summary='Stun a droid for 16 frames',
        detail='Sets the droid stun counter to 16, preventing movement.',
    ),
    0x1C41: dict(
        category='Droid AI',
        summary='Kill a droid — trigger explosion animation, update score',
        detail=(
            'Transitions the droid to explosion mode (dMd2_explosion)\n'
            '; and awards score points via DoScore.'
        ),
    ),
    0x1CF4: dict(
        category='Droid AI',
        summary='Explosion animation state machine',
        detail=(
            'Animates the 8-frame explosion sprite sequence then\n'
            '; frees the sprite slot.'
        ),
    ),
    0x2A6D: dict(
        category='Doors',
        summary='Open a door — edit screen RAM tiles at door position',
        detail=(
            'Replaces closed-door tiles in screen RAM with open-door\n'
            '; tiles at the computed screen position.'
        ),
    ),
    0x2B08: dict(
        category='Doors',
        summary='Close all doors — restore screen RAM tiles',
        detail=(
            'Restores closed-door tiles for all doors on the current\n'
            '; deck.'
        ),
    ),
    0x3590: dict(
        category='Level',
        summary='RLE-decode level data to screen RAM',
        detail=(
            'Decodes the run-length-encoded level map into the C64\n'
            '; screen RAM at $0400. Called when entering a new deck.'
        ),
    ),
    0x3629: dict(
        category='Title screen',
        summary='Set up VIC-II sprites for the title screen',
        detail=(
            'Initialises sprite positions, images, and colours for\n'
            '; the attract-mode title display.'
        ),
    ),
    0x39F8: dict(
        category='Screen',
        summary='Viewport render and fine horizontal scroll update',
        detail=(
            'Updates the screen viewport position and writes the\n'
            '; fine horizontal scroll value to VIC-II $D016 for\n'
            '; smooth scrolling.'
        ),
    ),
    0x3BE8: dict(
        category='UI',
        summary='Suspend game on fire/run key — pause screen',
        detail=(
            'Waits for the player to press fire or the RUN/STOP key\n'
            '; then resumes. Shows a pause indicator on screen.'
        ),
    ),
    0x3C14: dict(
        category='Text',
        summary='Decompress packed text string',
        detail=(
            'Unpacks 5-bit compressed text tokens into character\n'
            '; codes for on-screen display.'
        ),
    ),
    0x6EC0: dict(
        category='Interrupt',
        summary='Raster IRQ at line 254 — frame start, set sync flag',
        detail=(
            'First raster IRQ of each frame. Acknowledges the VIC-II\n'
            '; interrupt ($D019), sets the next raster trigger\n'
            '; ($D012 = 91), and sets the frame-sync flag read by\n'
            '; GameLoop.'
        ),
    ),
    0x6F04: dict(
        category='Interrupt',
        summary='Raster IRQ at line 91 — write horizontal scroll register',
        detail=(
            'Second raster IRQ. Writes the horizontal fine-scroll\n'
            '; value to VIC-II $D016 to achieve mid-frame smooth\n'
            '; scrolling.'
        ),
    ),
    0x6F4C: dict(
        category='Interrupt',
        summary='Raster IRQ at line 118 — call Sound driver at 50 Hz',
        detail=(
            'Third raster IRQ. JSR to Sound to drive SID music and\n'
            '; sound effects at the 50 Hz frame rate.'
        ),
    ),
    0x6FC0: dict(
        category='Interrupt',
        summary='Raster IRQ at line 246 — read sprite-sprite collision',
        detail=(
            'Fourth raster IRQ. Reads VIC-II sprite-sprite collision\n'
            '; register $D01E (reading clears it) and stores the\n'
            '; result for collision processing.'
        ),
    ),
    0x6FE9: dict(
        category='Interrupt',
        summary='NMI handler — RTI stub (disables RESTORE key crash)',
        detail=(
            'Non-maskable interrupt handler. Executes RTI immediately\n'
            '; to dismiss the interrupt. Prevents NMI from crashing\n'
            '; the game when the RESTORE key is pressed.'
        ),
    ),
    0xE0D3: dict(
        category='Transfer minigame',
        summary='Circuit puzzle — select side for droid transfer minigame',
        detail=(
            'Handles player input and display logic for the droid\n'
            '; transfer minigame circuit-side selection screen.'
        ),
    ),
}

# ---------------------------------------------------------------------------
# C64 hardware register descriptions
# ---------------------------------------------------------------------------
HW_REGS = {
    0xD000: 'VIC-II sprite 0 X position',
    0xD001: 'VIC-II sprite 0 Y position',
    0xD002: 'VIC-II sprite 1 X position',
    0xD003: 'VIC-II sprite 1 Y position',
    0xD004: 'VIC-II sprite 2 X position',
    0xD005: 'VIC-II sprite 2 Y position',
    0xD006: 'VIC-II sprite 3 X position',
    0xD007: 'VIC-II sprite 3 Y position',
    0xD008: 'VIC-II sprite 4 X position',
    0xD009: 'VIC-II sprite 4 Y position',
    0xD00A: 'VIC-II sprite 5 X position',
    0xD00B: 'VIC-II sprite 5 Y position',
    0xD00C: 'VIC-II sprite 6 X position',
    0xD00D: 'VIC-II sprite 6 Y position',
    0xD00E: 'VIC-II sprite 7 X position',
    0xD00F: 'VIC-II sprite 7 Y position',
    0xD010: 'VIC-II sprite X MSB (bit 8 of X)',
    0xD011: 'VIC-II ctrl1: vscroll/screen-on/blank',
    0xD012: 'VIC-II raster line trigger',
    0xD013: 'VIC-II light pen X',
    0xD014: 'VIC-II light pen Y',
    0xD015: 'VIC-II sprite enable',
    0xD016: 'VIC-II ctrl2: hscroll/multicolour',
    0xD017: 'VIC-II sprite Y expand',
    0xD018: 'VIC-II memory pointers (char/screen bank)',
    0xD019: 'VIC-II IRQ status/acknowledge',
    0xD01A: 'VIC-II IRQ enable mask',
    0xD01B: 'VIC-II sprite-background priority',
    0xD01C: 'VIC-II sprite multicolour enable',
    0xD01D: 'VIC-II sprite X expand',
    0xD01E: 'VIC-II sprite-sprite collision [read clears]',
    0xD01F: 'VIC-II sprite-background collision [read clears]',
    0xD020: 'VIC-II border colour',
    0xD021: 'VIC-II background colour 0',
    0xD022: 'VIC-II background colour 1',
    0xD023: 'VIC-II background colour 2',
    0xD024: 'VIC-II background colour 3',
    0xD025: 'VIC-II sprite multicolour 0',
    0xD026: 'VIC-II sprite multicolour 1',
    0xD027: 'VIC-II sprite 0 colour',
    0xD028: 'VIC-II sprite 1 colour',
    0xD029: 'VIC-II sprite 2 colour',
    0xD02A: 'VIC-II sprite 3 colour',
    0xD02B: 'VIC-II sprite 4 colour',
    0xD02C: 'VIC-II sprite 5 colour',
    0xD02D: 'VIC-II sprite 6 colour',
    0xD02E: 'VIC-II sprite 7 colour',
    0xD400: 'SID voice 1 frequency lo',
    0xD401: 'SID voice 1 frequency hi',
    0xD402: 'SID voice 1 pulse width lo',
    0xD403: 'SID voice 1 pulse width hi',
    0xD404: 'SID voice 1 control register',
    0xD405: 'SID voice 1 attack/decay',
    0xD406: 'SID voice 1 sustain/release',
    0xD407: 'SID voice 2 frequency lo',
    0xD408: 'SID voice 2 frequency hi',
    0xD409: 'SID voice 2 pulse width lo',
    0xD40A: 'SID voice 2 pulse width hi',
    0xD40B: 'SID voice 2 control register',
    0xD40C: 'SID voice 2 attack/decay',
    0xD40D: 'SID voice 2 sustain/release',
    0xD40E: 'SID voice 3 frequency lo',
    0xD40F: 'SID voice 3 frequency hi',
    0xD410: 'SID voice 3 pulse width lo',
    0xD411: 'SID voice 3 pulse width hi',
    0xD412: 'SID voice 3 control register',
    0xD413: 'SID voice 3 attack/decay',
    0xD414: 'SID voice 3 sustain/release',
    0xD415: 'SID filter cutoff lo',
    0xD416: 'SID filter cutoff hi',
    0xD417: 'SID filter resonance/voice enable',
    0xD418: 'SID master volume / filter mode',
    0xDC00: 'CIA1 port A: keyboard column / joystick 1',
    0xDC01: 'CIA1 port B: keyboard row / joystick 2',
    0xDC02: 'CIA1 port A data direction',
    0xDC03: 'CIA1 port B data direction',
    0xDC04: 'CIA1 timer A lo',
    0xDC05: 'CIA1 timer A hi',
    0xDC06: 'CIA1 timer B lo',
    0xDC07: 'CIA1 timer B hi',
    0xDC0D: 'CIA1 interrupt control/status',
    0xDC0E: 'CIA1 control register A',
    0xDC0F: 'CIA1 control register B',
    0xDD00: 'CIA2 port A: VIC-II bank select / serial',
    0xDD01: 'CIA2 port B: user port',
    0xDD02: 'CIA2 port A data direction',
    0xDD0D: 'CIA2 interrupt control/status',
    0xDD0E: 'CIA2 control register A',
    0xDD0F: 'CIA2 control register B',
    0xFFFA: 'NMI vector lo',
    0xFFFB: 'NMI vector hi',
    0xFFFC: 'RESET vector lo',
    0xFFFD: 'RESET vector hi',
    0xFFFE: 'IRQ/BRK vector lo',
    0xFFFF: 'IRQ/BRK vector hi',
}


def hw_reg_desc(addr):
    """Return a hardware register description for a C64 I/O address, or None."""
    if addr in HW_REGS:
        return HW_REGS[addr]
    if 0xD800 <= addr <= 0xDBFF:
        return f'Color RAM +${addr - 0xD800:03X}'
    if 0xD000 <= addr <= 0xD02E:
        return f'VIC-II register +${addr - 0xD000:02X}'
    if 0xD400 <= addr <= 0xD41C:
        return f'SID register +${addr - 0xD400:02X}'
    if 0xDC00 <= addr <= 0xDCFF:
        return f'CIA1 register +${addr - 0xDC00:02X}'
    if 0xDD00 <= addr <= 0xDDFF:
        return f'CIA2 register +${addr - 0xDD00:02X}'
    return None


# ---------------------------------------------------------------------------
# Section banners
# ---------------------------------------------------------------------------
SECTIONS = [
    (0x0000, 'Zero Page Workspace',      'CPU zero page variables ($0000-$00FF)'),
    (0x0100, 'Stack / Page 1 Data',      'Stack page and auxiliary data ($0100-$01FF)'),
    (0x0200, 'Page 2 Variables',         'Additional RAM variables ($0200-$04FF)'),
    (0x0500, 'Sound Engine',             'SID music and sound effects driver ($0500+)'),
    (0x091A, 'I/O and Sprite Routines',  'CIA joystick reads, VIC-II sprite management'),
    (0x0A52, 'Display Utilities',        'Colour RAM fill, score display'),
    (0x0B6E, 'System Utilities',         'Tape motor, miscellaneous system routines'),
    (0x1000, 'Entry and Restart',        'Cold/warm start entry points ($1000+)'),
    (0x1242, 'Initialisation',           'Hardware setup for game start'),
    (0x13DA, 'Main Loop',                'GameLoop, RunGame per-frame dispatch'),
    (0x1700, 'Droid AI',                 'Droid movement, shooting, mode dispatch'),
    (0x2000, 'Game Logic',               'Collision, doors, scoring, lifts'),
    (0x3590, 'Level Build',              'RLE level decode, screen construction'),
    (0x39F8, 'Screen Rendering',         'Viewport render, scrolling, text'),
    (0x6B00, 'Data Tables',              'Level maps, sprite data, lookup tables'),
    (0x6EC0, 'IRQ Handlers',             '4-stage raster interrupt chain'),
    (0x7000, 'Level Data',               'Encoded level map data'),
    (0xE000, 'Transfer Minigame',        'Droid transfer circuit puzzle'),
    (0xFFFA, 'Interrupt Vectors',        'NMI/RESET/IRQ vectors ($FFFA-$FFFF)'),
]

# ---------------------------------------------------------------------------
# Hardware constants block
# ---------------------------------------------------------------------------
HW_CONSTANTS = """\
; VIC-II sprite position registers
VIC_SPR0_X    = $D000           ; Sprite 0 X position
VIC_SPR0_Y    = $D001           ; Sprite 0 Y position
VIC_SPR1_X    = $D002           ; Sprite 1 X position
VIC_SPR1_Y    = $D003           ; Sprite 1 Y position
VIC_SPR2_X    = $D004           ; Sprite 2 X position
VIC_SPR2_Y    = $D005           ; Sprite 2 Y position
VIC_SPR3_X    = $D006           ; Sprite 3 X position
VIC_SPR3_Y    = $D007           ; Sprite 3 Y position
VIC_SPR4_X    = $D008           ; Sprite 4 X position
VIC_SPR4_Y    = $D009           ; Sprite 4 Y position
VIC_SPR5_X    = $D00A           ; Sprite 5 X position
VIC_SPR5_Y    = $D00B           ; Sprite 5 Y position
VIC_SPR6_X    = $D00C           ; Sprite 6 X position
VIC_SPR6_Y    = $D00D           ; Sprite 6 Y position
VIC_SPR7_X    = $D00E           ; Sprite 7 X position
VIC_SPR7_Y    = $D00F           ; Sprite 7 Y position

; VIC-II control registers
VIC_SPR_XMSB  = $D010           ; Sprite X MSB (bit 8 of X for each sprite)
VIC_CTRL1     = $D011           ; Control 1: vscroll / screen-on / blank
VIC_RASTER    = $D012           ; Raster line trigger
VIC_SPR_ENA   = $D015           ; Sprite enable register
VIC_CTRL2     = $D016           ; Control 2: hscroll / multicolour mode
VIC_SPR_YEXP  = $D017           ; Sprite Y expand
VIC_MEMPTR    = $D018           ; Memory pointers (char/screen bank)
VIC_IRQ       = $D019           ; IRQ status / acknowledge
VIC_IRQ_ENA   = $D01A           ; IRQ enable mask
VIC_SPR_PRI   = $D01B           ; Sprite-background priority
VIC_SPR_MC    = $D01C           ; Sprite multicolour enable
VIC_SPR_XEXP  = $D01D           ; Sprite X expand
VIC_SPR_SS    = $D01E           ; Sprite-sprite collision [read clears]
VIC_SPR_SB    = $D01F           ; Sprite-background collision [read clears]
VIC_BORDER    = $D020           ; Border colour
VIC_BG0       = $D021           ; Background colour 0
VIC_SPR0_COL  = $D027           ; Sprite 0 colour
VIC_SPR1_COL  = $D028           ; Sprite 1 colour
VIC_SPR2_COL  = $D029           ; Sprite 2 colour
VIC_SPR3_COL  = $D02A           ; Sprite 3 colour
VIC_SPR4_COL  = $D02B           ; Sprite 4 colour
VIC_SPR5_COL  = $D02C           ; Sprite 5 colour
VIC_SPR6_COL  = $D02D           ; Sprite 6 colour
VIC_SPR7_COL  = $D02E           ; Sprite 7 colour

; SID registers
SID_V1_FREQ_LO = $D400          ; Voice 1 frequency lo
SID_V1_FREQ_HI = $D401          ; Voice 1 frequency hi
SID_V1_PW_LO   = $D402          ; Voice 1 pulse width lo
SID_V1_PW_HI   = $D403          ; Voice 1 pulse width hi
SID_V1_CTRL    = $D404          ; Voice 1 control register
SID_V1_AD      = $D405          ; Voice 1 attack/decay
SID_V1_SR      = $D406          ; Voice 1 sustain/release
SID_V2_FREQ_LO = $D407          ; Voice 2 frequency lo
SID_V2_FREQ_HI = $D408          ; Voice 2 frequency hi
SID_V2_PW_LO   = $D409          ; Voice 2 pulse width lo
SID_V2_PW_HI   = $D40A          ; Voice 2 pulse width hi
SID_V2_CTRL    = $D40B          ; Voice 2 control register
SID_V2_AD      = $D40C          ; Voice 2 attack/decay
SID_V2_SR      = $D40D          ; Voice 2 sustain/release
SID_V3_FREQ_LO = $D40E          ; Voice 3 frequency lo
SID_V3_FREQ_HI = $D40F          ; Voice 3 frequency hi
SID_V3_PW_LO   = $D410          ; Voice 3 pulse width lo
SID_V3_PW_HI   = $D411          ; Voice 3 pulse width hi
SID_V3_CTRL    = $D412          ; Voice 3 control register
SID_V3_AD      = $D413          ; Voice 3 attack/decay
SID_V3_SR      = $D414          ; Voice 3 sustain/release
SID_FILT_LO    = $D415          ; Filter cutoff lo
SID_FILT_HI    = $D416          ; Filter cutoff hi
SID_FILT_RES   = $D417          ; Filter resonance / voice enable
SID_VOL        = $D418          ; Master volume / filter mode

; CIA1 registers
CIA1_PA        = $DC00          ; Port A: keyboard column / joystick 1
CIA1_PB        = $DC01          ; Port B: keyboard row / joystick 2
CIA1_DDRA      = $DC02          ; Port A data direction register
CIA1_DDRB      = $DC03          ; Port B data direction register
CIA1_ICR       = $DC0D          ; Interrupt control / status
CIA1_CRA       = $DC0E          ; Control register A
CIA1_CRB       = $DC0F          ; Control register B

; CIA2 registers
CIA2_PA        = $DD00          ; Port A: VIC-II bank select / serial clock
CIA2_PB        = $DD01          ; Port B: user port
CIA2_DDRA      = $DD02          ; Port A data direction register
CIA2_ICR       = $DD0D          ; Interrupt control / status

; Color RAM and interrupt vectors
COLOR_RAM      = $D800          ; Color RAM base address ($D800-$DBFF)
VEC_NMI        = $FFFA          ; NMI vector (lo/hi)
VEC_RESET      = $FFFC          ; RESET vector (lo/hi)
VEC_IRQ        = $FFFE          ; IRQ/BRK vector (lo/hi)
"""

# ---------------------------------------------------------------------------
# Regex constants
# ---------------------------------------------------------------------------
LINE_PREFIX_RE = re.compile(r'^\s+\d+\u2192')   # matches '   123→'
ADDR_RE        = re.compile(r'^([0-9A-Fa-f]{4})')
# A tab-field that is purely hex bytes / ?? / + continuation markers
HEX_FIELD_RE   = re.compile(
    r'^[0-9A-Fa-f]{2}(?:\s+[0-9A-Fa-f]{2})*\+?$'
    r'|^\?\?(?:\s+\?\?)*\+?$'
    r'|^\?\?$'
    r'|^\+$'
)
DATA_DIRECTIVE_RE = re.compile(r'\.(BYTE|WORD)\b', re.IGNORECASE)
XREF_RE        = re.compile(r'\w+(?:\+[0-9A-Fa-f]+)?\s*[\u2191\u2193]\w')  # ↑/↓
CALLER_RE      = re.compile(r'(\w+)(?:\+[0-9A-Fa-f]+)?\s*[\u2191\u2193]p')
OPCODE_RE      = re.compile(
    r'\b(LDA|LDX|LDY|STA|STX|STY|TAX|TAY|TXA|TYA|TSX|TXS'
    r'|PHA|PLA|PHP|PLP|ADC|SBC|AND|ORA|EOR|CMP|CPX|CPY'
    r'|INC|DEC|INX|DEX|INY|DEY|ASL|LSR|ROL|ROR|BIT'
    r'|JMP|JSR|RTS|RTI|BEQ|BNE|BCC|BCS|BPL|BMI|BVC|BVS'
    r'|NOP|SEC|CLC|SEI|CLI|SED|CLD|CLV)\b',
    re.IGNORECASE,
)
HW_ADDR_RE     = re.compile(r'\$([CD][0-9A-Fa-f]{3})\b', re.IGNORECASE)
HW_LABEL_RE    = re.compile(r'\b(?:unk_0_|byte_0_)([CD][0-9A-Fa-f]{3})\b', re.IGNORECASE)

SEP  = '; ' + '*' * 78
SEPC = '; ' + '-' * 78


# ---------------------------------------------------------------------------
# Low-level line parsing
# ---------------------------------------------------------------------------

def strip_prefix(raw):
    """Remove the IDA line-number prefix '   123→' from a raw line."""
    m = LINE_PREFIX_RE.match(raw)
    return raw[m.end():].rstrip('\r\n') if m else raw.rstrip('\r\n')


def parse_line(raw):
    """
    Returns (addr_int, rest_str) where rest_str is everything after the
    4-character hex address (may be empty).
    Returns (None, stripped_line) if the line has no address.
    """
    line = strip_prefix(raw)
    if not line.strip():
        return None, ''
    m = ADDR_RE.match(line)
    if not m:
        return None, line
    return int(m.group(1), 16), line[4:]


def get_content(rest):
    """
    Given rest = everything after the 4-char address, skip hex-byte fields
    and return the first tab-field that looks like real assembly content.
    """
    parts = rest.split('\t')
    for idx, part in enumerate(parts):
        stripped = part.strip()
        if not stripped:
            continue
        if HEX_FIELD_RE.match(stripped):
            continue
        # A .BYTE/.WORD OPERAND LIST IS LAID OUT IN TAB-SEPARATED COLUMN
        # GROUPS, and returning only the first one silently truncates the
        # block - and misaligns whatever survives, so the bytes that are
        # left sit at the WRONG OFFSETS.  BUGS.md #19: CharColor ($0800)
        # came back as 76 bytes of 256 this way, and 43% of the raw
        # listing's data went missing.  tools/verify_annotation.py checks.
        if DATA_DIRECTIVE_RE.search(stripped):
            tail = []
            for extra in parts[idx + 1:]:
                e = extra.strip()
                if not e:
                    continue
                if e.startswith(';'):
                    break               # a trailing xref, not more data
                tail.append(e)
            if tail:
                return stripped + ' ' + ' '.join(tail)
        return stripped
    return ''


def classify(rest):
    """
    Classify the line given rest = everything after the 4-char address.
    Returns one of:
        'banner'     — IDA 'S U B R O U T I N E' separator
        'end_func'   — IDA 'End of function' footer
        'func_label' — named subroutine/data label (no .BYTE/.WORD directive)
        'var'        — variable label with .BYTE/.WORD directive
        'local_label'— _N: style local label
        'code'       — 6502 instruction
        'data'       — .BYTE/.WORD without a leading label
        'xref'       — pure comment / xref line (starts with ;)
        'blank'      — empty
    """
    full = rest.strip()
    if not full:
        return 'blank'

    # IDA structural banners (use full line to catch tab-separated S U B R)
    if re.search(r'S\s+U\s+B\s+R\s+O\s+U\s+T\s+I\s+N\s+E', full):
        return 'banner'
    if re.search(r'End\s+of\s+function', full):
        return 'end_func'

    content = get_content(rest)
    if not content:
        return 'blank'

    if content.startswith(';'):
        return 'xref'

    # Local label _N: or IDA-generated loc_XXXX:
    if re.match(r'^_\w+:', content):
        return 'local_label'
    if re.match(r'^loc_[0-9A-Fa-f_]+:', content):
        return 'local_label'

    # Named label
    if re.match(r'^\w+:', content):
        # Check for .BYTE/.WORD in content OR in the full rest (covers 'name:; 0 .BYTE' style)
        if re.search(r'\.(BYTE|WORD|RES)\b', content, re.IGNORECASE):
            return 'var'
        if re.search(r'\.(BYTE|WORD|RES)\b', rest, re.IGNORECASE):
            return 'var'
        # Catch IDA 'unk_0_X:; 0 .BYTE uninited & unexplored' pattern
        if re.search(r'0\s+\.BYTE\s+uninited', rest, re.IGNORECASE):
            return 'var'
        return 'func_label'

    if re.search(r'\.(BYTE|WORD|RES)\b', content, re.IGNORECASE):
        return 'data'

    if OPCODE_RE.search(content):
        return 'code'

    return 'xref'  # catch-all for stray comment lines


# ---------------------------------------------------------------------------
# Xref / comment utilities
# ---------------------------------------------------------------------------

def extract_xrefs(content):
    """Return list of xref strings found in a comment."""
    # Collect everything after each ';' that contains an arrow xref
    results = []
    for seg in content.split(';'):
        seg = seg.strip()
        if XREF_RE.search(seg):
            results.append(seg)
    return results


def strip_xrefs(content):
    """
    Remove trailing IDA cross-reference comments from a content string.
    Preserves genuine developer comments (those without ↑/↓ arrows).
    """
    result = content
    # Remove xref-style semicolon groups from the right
    while True:
        m = re.search(r'\s*;\s*\w+(?:\+[0-9A-Fa-f]+)?\s*[\u2191\u2193]\w.*$', result)
        if m:
            result = result[:m.start()].rstrip()
        else:
            break
    # Also strip IDA 'uninited' annotations
    result = re.sub(r'\s*;\s*\(uninited\).*$', '', result).rstrip()
    result = re.sub(r'\s*;\s*0\s*\.BYTE\s*uninited.*$', '', result).rstrip()
    return result


def hw_annotation(content):
    """
    Scan an instruction's content for C64 hardware addresses.
    Returns an annotation string like ' ; [C64: VIC-II sprite enable ($D015)]'
    or '' if nothing found.
    """
    descs = []
    seen  = set()

    # Explicit $DXXX / $CXXX addresses
    for m in HW_ADDR_RE.finditer(content):
        addr = int(m.group(1), 16)
        if addr not in seen:
            desc = hw_reg_desc(addr)
            if desc:
                descs.append(f'[C64: {desc} (${addr:04X})]')
                seen.add(addr)

    # Labels encoding hardware addresses: unk_0_D015, byte_0_DC01, etc.
    for m in HW_LABEL_RE.finditer(content):
        addr = int(m.group(1), 16)
        if addr not in seen:
            desc = hw_reg_desc(addr)
            if desc:
                descs.append(f'[C64: {desc} (${addr:04X})]')
                seen.add(addr)

    if descs:
        return ' ; ' + ' '.join(descs)
    return ''


# ---------------------------------------------------------------------------
# Header generators
# ---------------------------------------------------------------------------

def file_header():
    today = date.today().isoformat()
    return '\n'.join([
        SEP,
        ';',
        ';  Paradroid CE — Level7-Style Annotated Assembly Listing',
        ';  Generated from paradroid_ce.lst (IDA Pro disassembly)',
        f';  Date: {today}',
        ';',
        ';  Annotation style based on level7.org.uk (Exile disassembly) and',
        ';  bbcelite.com (Elite BBC Micro disassembly).',
        ';',
        ';  BBC Micro port notes:',
        ';    Sections marked [BBC HAL] require platform replacement:',
        ';      • VIC-II hardware sprites  → software sprites in MODE 4/5',
        ';      • SID 3-voice synthesis    → SN76489 via BBC sound system',
        ';      • 4-stage raster IRQ chain → single 50 Hz VSYNC interrupt',
        ';      • CIA joystick ($DC01)     → system VIA analogue port ($FE60)',
        ';      • Color RAM ($D800)        → no equivalent; BBC uses palette',
        ';      • $D018/$DD00 bank switch  → CRTC registers 12/13',
        ';',
        ';    Directly portable (no hardware dependency):',
        ';      • All AI, collision, scoring, doors, lifts',
        ';      • Map and level data tables',
        ';      • BCD score arithmetic (SED/CLD identical)',
        ';      • Direction tables and jump-table dispatch',
        ';',
        SEP,
    ])


def section_banner(title, desc):
    return '\n'.join([
        '',
        '; ' + '=' * 78,
        f'; SECTION: {title}',
        f'; {desc}',
        '; ' + '=' * 78,
        '',
    ])


def sub_header(name, addr, category, summary, detail, callers):
    lines = [SEP, ';',
             f';       Name: {name}',
             ';       Type: Subroutine',
             f';    Address: ${addr:04X}',
             f';   Category: {category}',
             f';    Summary: {summary}',
             ';']
    if detail:
        lines.append(SEPC)
        lines.append(';')
        for dl in detail.split('\n'):
            # Lines starting with ';' are already formatted
            if dl.startswith(';'):
                lines.append(dl)
            else:
                lines.append(f'; {dl}')
        lines.append(';')
    if callers:
        lines.append(f'; Called from: {", ".join(callers[:8])}')
        lines.append(';')
    lines.append(SEP)
    return '\n'.join(lines)


def var_header(name, addr, category, summary):
    return '\n'.join([
        SEP, ';',
        f';       Name: {name}',
        ';       Type: Variable',
        f';    Address: ${addr:04X}',
        f';   Category: {category}',
        f';    Summary: {summary}',
        ';',
        SEP,
    ])


# ---------------------------------------------------------------------------
# Pass 1: build symbol table
# ---------------------------------------------------------------------------

def pass1(lines):
    """
    Scan all lines and build:
      symbol_table : dict{ addr -> {name, type, xrefs:[str]} }
      func_callers : dict{ name -> [caller_name, ...] }
    """
    symbol_table = {}
    i = 0
    N = len(lines)

    while i < N:
        raw   = lines[i]
        addr, rest = parse_line(raw)
        i += 1

        if addr is None:
            continue

        cls = classify(rest)
        if cls not in ('func_label', 'var'):
            continue

        content = get_content(rest)
        m = re.match(r'^(\w+):', content)
        if not m:
            continue
        name = m.group(1)

        # Gather xrefs from this line's comment
        xrefs = extract_xrefs(content)

        # Peek ahead and absorb continuation xref lines at the same address
        while i < N:
            next_addr, next_rest = parse_line(lines[i])
            if next_addr != addr:
                break
            next_cls = classify(next_rest)
            if next_cls in ('xref', 'blank', 'banner', 'end_func'):
                xrefs.extend(extract_xrefs(get_content(next_rest)))
                i += 1
            else:
                break

        symbol_table[addr] = {'name': name, 'type': cls, 'xrefs': xrefs}

    # Build per-name caller list
    func_callers = {}
    for sym in symbol_table.values():
        callers = []
        for xref in sym['xrefs']:
            for cm in CALLER_RE.finditer(xref):
                c = cm.group(1)
                if c != sym['name'] and c not in callers:
                    callers.append(c)
        func_callers[sym['name']] = callers

    return symbol_table, func_callers


# ---------------------------------------------------------------------------
# Pass 2: emit annotated output
# ---------------------------------------------------------------------------

def pass2(lines, symbol_table, func_callers, outfile):
    out = []

    def emit(s=''):
        out.append(s)

    # Sort section boundaries for range checks
    sec_sorted = sorted(SECTIONS, key=lambda x: x[0])
    sections_emitted = set()
    prev_addr = -1

    # --- File header + hardware constants ---
    emit(file_header())
    emit('')
    emit(SEP)
    emit(';')
    emit(';  C64 Hardware Constants')
    emit(';  (Replace with BBC Micro equivalents in the HAL layer)')
    emit(';')
    emit(SEP)
    emit('')
    emit(HW_CONSTANTS.rstrip())
    emit('')

    # --- Main pass ---
    i = 0
    N = len(lines)

    while i < N:
        raw = lines[i]
        addr, rest = parse_line(raw)
        i += 1

        # Blank / un-addressable line
        if addr is None:
            emit()
            continue

        # Section banners
        for sa, stitle, sdesc in sec_sorted:
            if sa not in sections_emitted and prev_addr < sa <= addr:
                emit(section_banner(stitle, sdesc))
                sections_emitted.add(sa)

        cls = classify(rest)

        # --- Suppress IDA structural lines ---
        if cls in ('banner', 'end_func'):
            prev_addr = addr
            continue

        content = get_content(rest)

        # -------------------------------------------------------------------
        if cls == 'func_label':
            # Collect callers from symbol table
            sym  = symbol_table.get(addr, {})
            name = sym.get('name', f'sub_{addr:04X}')
            callers = func_callers.get(name, [])

            known    = KNOWN_FUNCTIONS.get(addr, {})
            category = known.get('category', 'TODO')
            summary  = known.get('summary', f'Subroutine at ${addr:04X}')
            detail   = known.get('detail', '')

            emit()
            emit(sub_header(name, addr, category, summary, detail, callers))
            emit()
            emit(f'{name}:')

            # Skip xref continuation lines
            while i < N:
                na, nr = parse_line(lines[i])
                if na != addr:
                    break
                nc = classify(nr)
                if nc in ('xref', 'blank', 'banner', 'end_func'):
                    i += 1
                else:
                    break

        # -------------------------------------------------------------------
        elif cls == 'var':
            sym  = symbol_table.get(addr, {})
            name = sym.get('name')
            if not name:
                m2 = re.match(r'^(\w+):', content)
                name = m2.group(1) if m2 else f'var_{addr:04X}'

            category = 'Zero page' if addr < 0x100 else 'Variables'

            # Try to derive a sensible summary
            is_auto_name = bool(re.match(r'^(unk_|byte_|word_|off_)', name))
            if is_auto_name and re.search(r'uninited|unexplored', rest, re.IGNORECASE):
                summary = f'Uninitialised byte at ${addr:04X}'
            else:
                clean = strip_xrefs(content)
                clean_no_label = re.sub(r'^\w+:\s*;?\s*', '', clean).strip()
                clean_no_label = re.sub(r'^;+\s*', '', clean_no_label).strip()
                clean_no_label = re.sub(r'^\.(BYTE|WORD)\s+\d+\s*$', '', clean_no_label).strip()
                if clean_no_label and clean_no_label not in (';', ''):
                    summary = clean_no_label[:72]
                else:
                    summary = f'Variable at ${addr:04X}'

            emit()
            emit(var_header(name, addr, category, summary))

            # Emit declaration
            decl = strip_xrefs(content)
            if addr < 0x100:
                # Zero page: emit as equate  Name = $XX
                emit(f'{name} = ${addr:02X}')
            else:
                emit(f'{addr:04X}  {decl}')

            # Skip continuation xrefs
            while i < N:
                na, nr = parse_line(lines[i])
                if na != addr:
                    break
                nc = classify(nr)
                if nc in ('xref', 'blank'):
                    i += 1
                else:
                    break

        # -------------------------------------------------------------------
        elif cls == 'local_label':
            m2 = re.match(r'^(_\w+):', content)
            label = m2.group(1) if m2 else content.split(';')[0].rstrip().rstrip(':')
            emit(f'            {label}:')

            # Skip xref continuations
            while i < N:
                na, nr = parse_line(lines[i])
                if na != addr:
                    break
                nc = classify(nr)
                if nc in ('xref', 'blank'):
                    i += 1
                else:
                    break

        # -------------------------------------------------------------------
        elif cls == 'code':
            instr = strip_xrefs(content)
            ann   = hw_annotation(instr)
            if ann:
                emit(f'{addr:04X}  {instr:<42}{ann}')
            else:
                emit(f'{addr:04X}  {instr}')

        # -------------------------------------------------------------------
        elif cls == 'data':
            decl = strip_xrefs(content)
            emit(f'{addr:04X}  {decl}')

        # -------------------------------------------------------------------
        elif cls == 'xref':
            # Standalone xref/comment: emit only if it's a genuine comment
            if not XREF_RE.search(content):
                # Not an xref — genuine comment, pass through
                emit(f'{addr:04X}  {content}')
            # Otherwise silently suppress

        # -------------------------------------------------------------------
        else:
            # blank or unknown
            emit()

        prev_addr = addr

    # Write
    with open(outfile, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
        f.write('\n')

    return len(out)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print(f'Reading {INPUT_FILE}...', flush=True)
    try:
        with open(INPUT_FILE, encoding='utf-8') as f:
            lines = f.readlines()
    except UnicodeDecodeError:
        with open(INPUT_FILE, encoding='latin-1') as f:
            lines = f.readlines()
    print(f'  {len(lines)} lines read.')

    print('Pass 1: building symbol table...')
    symbol_table, func_callers = pass1(lines)
    n_funcs = sum(1 for s in symbol_table.values() if s['type'] == 'func_label')
    n_vars  = sum(1 for s in symbol_table.values() if s['type'] == 'var')
    print(f'  {n_funcs} subroutines, {n_vars} variables found.')

    print('Pass 2: generating annotated output...')
    n_out = pass2(lines, symbol_table, func_callers, OUTPUT_FILE)
    print(f'  Written {n_out} lines to {OUTPUT_FILE}')
    print('Done.')


if __name__ == '__main__':
    main()
