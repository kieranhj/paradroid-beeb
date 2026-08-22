#!/usr/bin/env python3
"""
palette_lab.py - the deck palette workbench for Layer 14.

Renders all 16 decks twice: once in the C64's own colours, once as the BBC
MODE 1 port draws them, and writes a single self-contained HTML page where
the BBC side is editable and the result can be saved back for the build.

    python tools/palette_lab.py           # writes tools/output/palette_lab.html
    python tools/palette_lab.py --open    # ... and opens it in the browser

WHY IT WORKS THE WAY IT DOES

Both renders come from ONE bitmap per deck: the C64 colour index (0-15) of
every pixel, exactly as the VIC would put it on screen - hires and multicolour
cells mixed, chosen per cell by bit 3 of the colour RAM nibble.

    C64 view:  index -> C64_RGB[index]
    BBC view:  index -> colourMap[index] -> physical[logical] -> BBC_RGB[]

which is precisely the port's own chain (colourMap and deckPalette in
src/data/colours.asm, applied by BuildCharset and SetPalette). So the BBC pane
is not an approximation of the port - it is the same lookup, and recolouring
is a 16-entry table swap, which is why editing is instant in the browser.

THE TWO THINGS THAT ARE EDITABLE, and they are different decisions:

  1. physical[]   logical 0-3 -> BBC physical colour 0-7.  This is
                  .deckPalette, 4 bytes a deck, and it is the palette in the
                  ordinary sense: it recolours without changing what merged
                  with what.
  2. colourMap[]  each C64 colour -> one of the four logical slots.  This is
                  the MERGE, and it is where detail is lost when a deck wants
                  more than four colours - two C64 colours landing on the same
                  logical become the same pixel and no palette can separate
                  them again.

Save writes tools/deck_palettes.json, which tools/export_bbc.py reads as an
override when it regenerates src/data/colours.asm. Delete the file to go back
to the automatic assignment.
"""

import argparse
import base64
import io
import json
import sys
import webbrowser
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit('ERROR: Pillow required. pip install Pillow')

sys.path.insert(0, str(Path(__file__).parent))
from rip_levels import parse_listing, decode_deck_rle          # noqa: E402
from export_droids import (build_rotor, build_digits,               # noqa: E402
                           droid_number, FRAMES)
from export_bbc import (C64_RGB, BBC_RGB,                          # noqa: E402
                        CHARSET_ADDR, TILEDEF_ADDR,
                        deck_colours, deck_background, build_logical_map,
                        build_colour_map, assign_palette)

PROJECT = Path(__file__).resolve().parent.parent
LST_FILE = PROJECT / 'paradroid_ce.lst'
OUT_DIR = PROJECT / 'tools' / 'output'
OUT_FILE = OUT_DIR / 'palette_lab.html'
OVERRIDE = PROJECT / 'tools' / 'deck_palettes.json'

MAP_COLS, MAP_ROWS = 64, 16
TILE_PX = 32                    # a tile is 4x4 characters of 8x8 pixels

# The play area, so the page can show what actually fits on screen at once.
VIEW_W, VIEW_H = 320, 120

C64_NAMES = ['black', 'white', 'red', 'cyan', 'purple', 'green', 'blue',
             'yellow', 'orange', 'brown', 'lt red', 'dk grey', 'grey',
             'lt green', 'lt blue', 'lt grey']
BBC_NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan',
             'white']

# The four slots carry fixed roles now - see export_bbc.build_logical_map.
ROLE_NAMES = ['background', 'darker', 'lighter', 'white / sprites']
# Only logical 3 has a physical colour the scheme depends on: the sprites are
# drawn in it and it has to read as white. 1 and 2 are the deck's own two
# foregrounds, darker then lighter - free choices, judge them by eye.
ROLE_WANTS = [None, None, None, 7]


def render_deck(mem, deck):
    """One deck as C64 colour indices, cropped to the tiles it actually uses.

    Returns (width, height, tile_x0, tile_y0, bytes) - one byte per pixel,
    the C64 colour 0-15 the VIC would display there.
    """
    _scheme, _rec, cell_colour = deck_colours(mem, deck)
    D021 = deck_background(mem, deck)      # per deck: slot 0 of its record

    tiles = decode_deck_rle(mem, deck)[:MAP_COLS * MAP_ROWS]
    tiles += [0] * (MAP_COLS * MAP_ROWS - len(tiles))

    used = [i for i, t in enumerate(tiles) if t]
    if not used:                                    # nothing to show
        return 0, 0, 0, 0, b''
    x0 = min(i % MAP_COLS for i in used)
    x1 = max(i % MAP_COLS for i in used)
    y0 = min(i // MAP_COLS for i in used)
    y1 = max(i // MAP_COLS for i in used)

    w = (x1 - x0 + 1) * TILE_PX
    h = (y1 - y0 + 1) * TILE_PX
    buf = bytearray([D021]) * (w * h)

    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            tile = tiles[ty * MAP_COLS + tx]
            for cy in range(4):
                for cx in range(4):
                    code = mem[TILEDEF_ADDR + tile * 16 + cy * 4 + cx]
                    colour = cell_colour(code)
                    base = CHARSET_ADDR + code * 8
                    px0 = (tx - x0) * TILE_PX + cx * 8
                    py0 = (ty - y0) * TILE_PX + cy * 8
                    # EVERY CELL IS HIRES: eight 1-bit pixels, the cell's
                    # full colour nibble against the deck background. Bit 3
                    # is part of the colour and not a mode flag - see
                    # export_bbc.py's header and ref/c64_deck5.png.
                    for row in range(8):
                        b = mem[base + row]
                        off = (py0 + row) * w + px0
                        for p in range(8):
                            buf[off + p] = colour if (b >> (7 - p)) & 1                                 else D021
    return w, h, x0, y0, bytes(buf)


SPR_W, SPR_H = 24, 21


def build_player_sprite(mem):
    """The player's droid, all 8 rotor phases, as rows of 24 booleans.

    Composed the way export_droids' row_index does it, because the picture is
    not stored anywhere as a picture: rows 0-4 are the rotor's top, 6-13 the
    droid's number, 15-17 the top rows again in REVERSE order, and 18-19 the
    two end rows taken from the OTHER entry of the two-entry tables - which is
    what makes the two ends of the rotor alternate as it spins.

    The player is type 0, and droid_number confirms it: 001, the influence
    device. Rows 5, 14 and 20 are blank.
    """
    frames, bottoms = build_rotor(mem)
    digits, _ = build_digits(mem, 0)

    phases = []
    for phase in range(FRAMES):
        rows = []
        for r in range(SPR_H):
            if r < 5:
                b = frames[phase][r]
            elif r in (5, 14, 20):
                b = [0, 0, 0]
            elif r < 14:
                b = digits[r - 6]
            elif r < 18:
                b = frames[phase][19 - r]
            elif r == 18:
                b = [0, bottoms[phase][1], 0]
            else:
                b = [0, bottoms[phase][0], 0]
            rows.append(''.join('1' if (byte >> (7 - i)) & 1 else '0'
                                for byte in b for i in range(8)))
        phases.append(rows)
    return phases


def png_b64(w, h, buf):
    """The index bitmap as an indexed PNG, painted in the C64's palette."""
    im = Image.frombytes('P', (w, h), buf)
    flat = []
    for rgb in C64_RGB:
        flat.extend(rgb)
    im.putpalette(flat)
    out = io.BytesIO()
    im.save(out, 'PNG', optimize=True)
    return base64.b64encode(out.getvalue()).decode('ascii')


def load_override():
    if not OVERRIDE.exists():
        return {}
    try:
        return json.loads(OVERRIDE.read_text()).get('decks', {})
    except (ValueError, OSError) as e:
        print('  WARNING: ignoring %s (%s)' % (OVERRIDE.name, e))
        return {}


def collect(mem):
    override = load_override()
    if override:
        print('  reading saved palettes from %s' % OVERRIDE.name)

    decks = []
    for d in range(16):
        scheme, rec, cell_colour = deck_colours(mem, d)
        bg = deck_background(mem, d)
        logical, _freq = build_logical_map(mem, cell_colour, bg)

        auto_map = build_colour_map(logical)
        auto_phys = assign_palette(logical)

        w, h, tx0, ty0, buf = render_deck(mem, d)
        counts = [0] * 16
        for b in buf:
            counts[b] += 1

        saved = override.get(str(d), {})
        decks.append({
            'deck': d,
            'scheme': scheme,
            'slots': rec,
            'w': w, 'h': h, 'tileX': tx0, 'tileY': ty0,
            'png': png_b64(w, h, buf),
            'logical': logical,
            'counts': counts,
            'autoMap': auto_map,
            'autoPhys': auto_phys,
            'colourMap': list(saved.get('colourMap', auto_map)),
            'physical': list(saved.get('physical', auto_phys)),
        })
        print('  deck %2d  scheme %d  bg %-9s %4dx%-4d  logical %s'
              % (d, scheme, C64_NAMES[bg], w, h,
                 ' '.join('%d=%s' % (i, C64_NAMES[c])
                          for i, c in enumerate(logical))))
    return decks


# --------------------------------------------------------------------------
# The page. Everything below is emitted verbatim except __DATA__.
# --------------------------------------------------------------------------

PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Paradroid deck palettes</title>
<style>
  :root {
    --bg: #14161a; --panel: #1c2027; --edge: #2c323c;
    --ink: #d8dee9; --dim: #8b95a5; --hot: #ffb454;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--ink);
    font: 13px/1.5 ui-sans-serif, system-ui, "Segoe UI", sans-serif;
  }
  h1 { font-size: 15px; margin: 0; font-weight: 600; letter-spacing: .02em; }
  h2 { font-size: 12px; margin: 0 0 8px; color: var(--dim);
       text-transform: uppercase; letter-spacing: .08em; font-weight: 600; }
  header {
    display: flex; align-items: center; gap: 16px; flex-wrap: wrap;
    padding: 10px 16px; background: var(--panel);
    border-bottom: 1px solid var(--edge); position: sticky; top: 0; z-index: 10;
  }
  .tabs { display: flex; gap: 3px; flex-wrap: wrap; }
  .tabs button {
    width: 30px; height: 26px; padding: 0; font: inherit; font-size: 12px;
    background: #232833; color: var(--dim);
    border: 1px solid var(--edge); border-radius: 4px; cursor: pointer;
  }
  .tabs button:hover { color: var(--ink); }
  .tabs button.on { background: var(--hot); color: #14161a; font-weight: 700;
                    border-color: var(--hot); }
  .tabs button.edited::after {
    content: ''; display: block; width: 4px; height: 4px; border-radius: 50%;
    background: var(--hot); margin: -5px auto 0;
  }
  .tabs button.on.edited::after { background: #14161a; }
  label { color: var(--dim); margin-right: 4px; }
  select, .btn {
    font: inherit; background: #232833; color: var(--ink);
    border: 1px solid var(--edge); border-radius: 4px; padding: 4px 8px;
    cursor: pointer;
  }
  .btn:hover { border-color: var(--hot); color: var(--hot); }
  main { display: flex; align-items: flex-start; gap: 0; }
  #views { flex: 1; min-width: 0; padding: 14px 16px 28px; }
  aside {
    width: 330px; flex: none; padding: 14px 16px 28px;
    border-left: 1px solid var(--edge); background: var(--panel);
    min-height: calc(100vh - 47px);
  }
  .pane { margin-bottom: 14px; }
  .pane .cap {
    display: flex; justify-content: space-between; align-items: baseline;
    color: var(--dim); font-size: 11px; text-transform: uppercase;
    letter-spacing: .08em; margin-bottom: 4px;
  }
  .scroller { overflow: auto; background: #0c0e11; border: 1px solid var(--edge);
              border-radius: 4px; }
  .scroller canvas { display: block; image-rendering: pixelated; }
  main.sbs #views { display: flex; gap: 14px; }
  main.sbs .pane { flex: 1; min-width: 0; }
  .swatch { width: 15px; height: 15px; border-radius: 3px; flex: none;
            border: 1px solid #0006; display: inline-block; vertical-align: -3px; }
  .lrow { display: flex; align-items: center; gap: 8px; margin-bottom: 7px; }
  .lrow .lname { width: 112px; font-size: 12px; line-height: 1.35; }
  .lrow .lname b { color: var(--hot); }
  .picker { display: flex; gap: 3px; }
  .picker button {
    width: 21px; height: 21px; padding: 0; border-radius: 3px; cursor: pointer;
    border: 2px solid transparent; outline: 1px solid #0008;
  }
  .picker button.on { border-color: var(--ink); }
  .merge { max-height: 208px; overflow: auto; margin: 0 -4px; padding: 0 4px; }
  .mrow { display: flex; align-items: center; gap: 7px; margin-bottom: 4px;
          font-size: 12px; }
  .mrow .mname { width: 66px; color: var(--dim); }
  .mrow .mpct { width: 42px; text-align: right; color: var(--dim);
                font-variant-numeric: tabular-nums; font-size: 11px; }
  .seg { display: flex; gap: 2px; }
  .seg button {
    width: 22px; height: 20px; padding: 0; font: inherit; font-size: 11px;
    background: #232833; color: var(--dim); border: 1px solid var(--edge);
    border-radius: 3px; cursor: pointer;
  }
  .seg button.on { background: var(--ink); color: #14161a; font-weight: 700; }
  .warn { color: #ff8f6b; font-size: 12px; margin: 8px 0 0; }
  .ovrow { display: flex; align-items: center; gap: 5px; margin-bottom: 3px;
           cursor: pointer; padding: 1px 3px; border-radius: 3px; }
  .ovrow:hover { background: #232833; }
  .ovrow.on { background: #2c323c; }
  .ovrow .ovn { width: 20px; font-size: 11px; color: var(--dim);
                text-align: right; font-variant-numeric: tabular-nums; }
  .ovrow .sw { width: 26px; height: 13px; border-radius: 2px;
               outline: 1px solid #0008; }
  .ovrow .ovsch { font-size: 10px; color: var(--dim); margin-left: 2px; }
  .ovrow .ovbad { color: #ff8f6b; font-size: 11px; margin-left: 2px; }
  .note { color: var(--dim); font-size: 11px; margin: 6px 0 0; }
  .acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 4px; }
  hr { border: 0; border-top: 1px solid var(--edge); margin: 16px 0; }
  #windows { display: flex; gap: 12px; flex-wrap: wrap; }
  #windows figure { margin: 0; }
  #windows figcaption { color: var(--dim); font-size: 11px; margin-bottom: 3px;
                        text-transform: uppercase; letter-spacing: .08em; }
  #windows canvas {
    image-rendering: pixelated; border: 1px solid var(--edge); border-radius: 3px;
    background: #0c0e11; width: 640px; height: 240px;
  }
  #windows select, #windows label { vertical-align: middle; }
  code { background: #0c0e11; padding: 1px 5px; border-radius: 3px;
         color: var(--hot); font-size: 11px; }
</style>
</head>
<body>

<header>
  <h1>Paradroid deck palettes</h1>
  <div class="tabs" id="tabs"></div>
  <span style="flex:1"></span>
  <label for="dither">dither</label>
  <select id="dither">
    <option value="off" selected>off &mdash; solid, as built</option>
    <option value="check">2&times;2 checker</option>
    <option value="vert">vertical stripes</option>
    <option value="horiz">horizontal stripes</option>
  </select>
  <select id="shade" title="which logical the half-pixels take">
    <option value="1" selected>shade = logical 1</option>
    <option value="2">shade = logical 2</option>
  </select>
  <label for="zoom">zoom</label>
  <select id="zoom">
    <option value="fit">fit</option>
    <option value="1" selected>1&times;</option>
    <option value="2">2&times;</option>
    <option value="3">3&times;</option>
  </select>
  <label for="layout">layout</label>
  <select id="layout">
    <option value="stack" selected>stacked</option>
    <option value="sbs">side by side</option>
  </select>
</header>

<main id="main">
  <div id="views">
    <div class="pane">
      <div class="cap"><span>C64 &mdash; as the VIC displays it</span>
        <span id="c64info"></span></div>
      <div class="scroller" id="scr64"><canvas id="cv64"></canvas></div>
    </div>
    <div class="pane">
      <div class="cap"><span>BBC MODE 1 &mdash; this palette</span>
        <span id="bbcinfo"></span></div>
      <div class="scroller" id="scrbb"><canvas id="cvbb"></canvas></div>
    </div>
    <h2 style="margin-top:18px">What fits on screen (320 &times; 120)
      <label style="text-transform:none;letter-spacing:0;font-weight:400;margin-left:10px">
        <input type="checkbox" id="sprOn" checked> droid</label>
      <select id="sprCol" style="text-transform:none;letter-spacing:0">
        <option value="3">white &mdash; logical 3, as drawn</option>
        <option value="1">black &mdash; logical 1, AND &amp;0F</option>
        <option value="2">highlight &mdash; logical 2, AND &amp;F0</option>
      </select>
    </h2>
    <div id="windows">
      <figure><figcaption>C64</figcaption><canvas id="w64" width="320" height="120"></canvas></figure>
      <figure><figcaption>BBC</figcaption><canvas id="wbb" width="320" height="120"></canvas></figure>
    </div>
    <p class="note" id="hint">Move the pointer over a deck above to aim this
      window; the droid follows it. Shown at 2&times;.</p>
    <p class="note"><b>dither</b> halves the intensity of logical 0 by giving
      every other pixel the shade logical instead. It is worth what logical 1
      is on this deck: black on thirteen of the sixteen, so the floor reads at
      half strength &mdash; but decks 0, 5 and 9 already have a BLACK logical 0
      and a coloured logical 1, so the dither there paints colour ONTO black
      and gets louder, not quieter. Those three want leaving alone, or
      re-picking.</p>
    <p class="note">What the BUILD does is the <b>2&times;2 checker</b> with
      <b>shade = logical 1</b>, and only on a deck whose logical 1 is physical
      black &mdash; <code>DitherChar</code> in <code>src/level.asm</code>, see
      <code>docs/layer-14-visual.md</code> DECISION 1. The other patterns and
      shade 2 are here to compare against, not to select: nothing carries them
      into the build.</p>
    <p class="note">The C64 draws every droid, the player included, in BLACK
      &mdash; <code>SpriteColor</code> takes <code>$F0</code> at
      <code>$1906</code> &mdash; so the C64 pane shows it black whatever the
      port is doing. Ours is logical 3, and logical 1 is one
      <code>AND &amp;0F</code> away.</p>
  </div>

  <aside>
    <h2>All sixteen decks</h2>
    <div id="overview"></div>
    <p class="note">Every deck's four physical colours in slot order. Click to
      jump; <b>!</b> marks one that breaks the scheme. Watch for neighbouring
      decks landing on the same combination.</p>

    <hr>
    <h2>Palette &mdash; logical to physical</h2>
    <div id="palette"></div>
    <p class="warn" id="dupwarn" hidden></p>
    <p class="note">Emitted as <code>.deckPalette</code>, 4 bytes a deck.
      Logical 0 is the background the whole deck sits on.</p>

    <hr>
    <h2>Merge &mdash; C64 colour to logical</h2>
    <div class="merge" id="merge"></div>
    <p class="warn" id="bgwarn" hidden></p>
    <p class="note">Emitted as <code>.colourMap</code>. Two C64 colours on the
      same logical slot become the same pixel &mdash; no palette can separate
      them again. Percentages are of this deck's pixels.</p>

    <hr>
    <h2>Save</h2>
    <div class="acts">
      <button class="btn" id="dl">Download deck_palettes.json</button>
      <button class="btn" id="cpasm">Copy .deckPalette</button>
      <button class="btn" id="rst">Reset deck</button>
      <button class="btn" id="rstall">Reset all</button>
    </div>
    <p class="note" id="saved"></p>
    <p class="note">Put the JSON in <code>tools/</code>, run
      <code>python tools/export_bbc.py</code>, then build. Edits are kept in
      this browser until you reset.</p>
  </aside>
</main>

<script>
const DATA = __DATA__;
const DECKS = DATA.decks, C64 = DATA.c64rgb, BBC = DATA.bbcrgb;
const C64N = DATA.c64names, BBCN = DATA.bbcnames;
const ROLES = DATA.roles, WANTS = DATA.wants;
const KEY = 'paradroid.palettes.v1';

let cur = 0, zoom = 1, imgs = [], idx = [];

/* ---- state, kept in localStorage so a reload does not lose an afternoon -- */
let edits = {};
try { edits = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { edits = {}; }

function deck(d) { return DECKS[d]; }
function phys(d) { return (edits[d] && edits[d].physical) || deck(d).physical; }
function cmap(d) { return (edits[d] && edits[d].colourMap) || deck(d).colourMap; }
function edited(d) {
  const e = edits[d]; if (!e) return false;
  const k = deck(d);
  return String(e.physical || k.physical) !== String(k.autoPhys) ||
         String(e.colourMap || k.colourMap) !== String(k.autoMap);
}
function setEdit(d, key, val) {
  edits[d] = Object.assign({ physical: phys(d).slice(), colourMap: cmap(d).slice() },
                           edits[d] || {});
  edits[d][key] = val;
  localStorage.setItem(KEY, JSON.stringify(edits));
}

/* ---- pixels ------------------------------------------------------------ */
/* One index bitmap per deck feeds both views; a view is a 16-entry lookup.  */
function lut(rgbList) {
  const t = new Uint32Array(16);
  for (let c = 0; c < 16; c++) {
    const [r, g, b] = rgbList[c];
    t[c] = (255 << 24) | (b << 16) | (g << 8) | r;   /* little-endian RGBA */
  }
  return t;
}
const LUT64 = lut(C64);

function bbcLut(d) {
  const p = phys(d), m = cmap(d), out = [];
  for (let c = 0; c < 16; c++) out.push(BBC[p[m[c]]]);
  return lut(out);
}

/* ---- the dither ---------------------------------------------------------
   Layer 14's experiment: the BBC palette is fully saturated, so a floor of
   solid red or cyan is far harsher than the C64's. Half its pixels take
   ANOTHER logical instead - logical 1, which is physical BLACK on thirteen
   of the sixteen decks - and the floor reads at half intensity.

   Applied to logical 0 wherever it lands: the floor itself AND any cell
   whose ink merged onto logical 0, which is what keeps such a cell
   invisible against the floor exactly as it is now.

   On the port this is baked into the charset at deck load, not drawn per
   frame, so the phase is fixed to the character grid. The crop here starts
   on a tile boundary, so (x+y)&1 is that grid up to a whole-pattern flip. */
let dither = 'off', shadeLog = 1;

function keepsColour(x, y) {
  if (dither === 'check') return ((x + y) & 1) === 0;
  if (dither === 'vert')  return (x & 1) === 0;
  if (dither === 'horiz') return (y & 1) === 0;
  return true;
}

/* The same 16-entry lookup, but with every C64 colour that merged onto
   logical 0 painted in the shade logical instead. */
function shadeLut(d) {
  const p = phys(d), m = cmap(d), out = [];
  for (let c = 0; c < 16; c++)
    out.push(BBC[p[m[c] === 0 ? shadeLog : m[c]]]);
  return lut(out);
}

function paint(canvas, d, table, alt) {
  const k = deck(d);
  canvas.width = k.w; canvas.height = k.h;
  const ctx = canvas.getContext('2d');
  const img = ctx.createImageData(k.w, k.h);
  const out = new Uint32Array(img.data.buffer), src = idx[d];
  if (!alt || dither === 'off') {
    for (let i = 0; i < src.length; i++) out[i] = table[src[i]];
  } else {
    for (let y = 0, i = 0; y < k.h; y++)
      for (let x = 0; x < k.w; x++, i++)
        out[i] = keepsColour(x, y) ? table[src[i]] : alt[src[i]];
  }
  ctx.putImageData(img, 0, 0);
}

/* Decode the PNG once into C64 indices. The PNG is painted in the C64
   palette, so the reverse lookup is exact - the 16 colours are distinct. */
function decodeIndices(d, img) {
  const k = deck(d);
  const c = document.createElement('canvas');
  c.width = k.w; c.height = k.h;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);
  const px = new Uint32Array(ctx.getImageData(0, 0, k.w, k.h).data.buffer);
  const back = new Map();
  for (let i = 0; i < 16; i++) back.set(LUT64[i] >>> 0, i);
  const out = new Uint8Array(px.length);
  let lost = 0;
  for (let i = 0; i < px.length; i++) {
    /* >>> 0: a bitwise OR yields a SIGNED int32, and the map is keyed on the
       unsigned values a Uint32Array reads back. Without it every lookup misses
       and the deck renders solid black. */
    const v = back.get((px[i] | 0xff000000) >>> 0);
    if (v === undefined) { lost++; out[i] = 0; } else { out[i] = v; }
  }
  if (lost) console.warn('deck ' + d + ': ' + lost + ' pixels off the C64 palette');
  idx[d] = out;
}

/* ---- drawing ----------------------------------------------------------- */
const cv64 = document.getElementById('cv64'), cvbb = document.getElementById('cvbb');
const w64 = document.getElementById('w64'), wbb = document.getElementById('wbb');

function applyZoom() {
  const k = deck(cur);
  let z = zoom;
  if (zoom === 'fit') {
    const avail = document.getElementById('scr64').clientWidth - 2;
    z = Math.min(1, avail / k.w);
  }
  for (const c of [cv64, cvbb]) {
    c.style.width = (k.w * z) + 'px';
    c.style.height = (k.h * z) + 'px';
  }
}

function redrawBBC() {
  paint(cvbb, cur, bbcLut(cur), shadeLut(cur));
  drawWindows(lastWin.x, lastWin.y);
}

function show(d) {
  cur = d;
  const k = deck(d);
  paint(cv64, d, LUT64);
  paint(cvbb, d, bbcLut(d), shadeLut(d));
  applyZoom();
  document.getElementById('c64info').textContent =
    'deck ' + d + ' · scheme ' + k.scheme + ' · ' + k.w + '×' + k.h + ' px';
  document.getElementById('bbcinfo').textContent =
    'physical ' + phys(d).join(' ');
  buildTabs(); buildOverview(); buildPalette(); buildMerge();
  drawWindows(lastWin.x, lastWin.y);
}

/* ---- the 320x120 window, which is what the player actually sees --------- */
let lastWin = { x: 0, y: 0 };
const SPR = DATA.sprite;
let sprOn = true, sprLogical = 3, sprPhase = 0;

/* The droid over the window, at the pointer. Both panes draw the same
   pixels; only the colour differs - the C64's is black by SpriteColor, ours
   is whichever logical slot is selected, which is the decision being made. */
function drawDroid(ctx, px, py, css) {
  if (!sprOn) return;
  const rows = SPR.phases[sprPhase & 7];
  ctx.fillStyle = css;
  for (let y = 0; y < SPR.h; y++) {
    const row = rows[y];
    for (let x = 0; x < SPR.w; x++)
      if (row[x] === '1') ctx.fillRect(px + x, py + y, 1, 1);
  }
}
function drawWindows(x, y) {
  const k = deck(cur);
  x = Math.max(0, Math.min(k.w - 1, x | 0));
  y = Math.max(0, Math.min(k.h - 1, y | 0));
  lastWin = { x, y };
  const sx = Math.max(0, Math.min(Math.max(0, k.w - 320), x - 160));
  const sy = Math.max(0, Math.min(Math.max(0, k.h - 120), y - 60));
  for (const [dst, src] of [[w64, cv64], [wbb, cvbb]]) {
    const c = dst.getContext('2d');
    c.imageSmoothingEnabled = false;
    c.fillStyle = '#000'; c.fillRect(0, 0, 320, 120);
    c.drawImage(src, sx, sy, Math.min(320, k.w), Math.min(120, k.h),
                0, 0, Math.min(320, k.w), Math.min(120, k.h));
    drawDroid(c, x - sx - (SPR.w >> 1), y - sy - (SPR.h >> 1),
              dst === w64 ? rgbcss(C64[0])            /* the C64's black */
                          : rgbcss(BBC[phys(cur)[sprLogical]]));
  }
}
for (const c of [cv64, cvbb]) {
  c.addEventListener('mousemove', ev => {
    const r = c.getBoundingClientRect(), k = deck(cur);
    drawWindows((ev.clientX - r.left) / r.width * k.w,
                (ev.clientY - r.top) / r.height * k.h);
    document.getElementById('hint').textContent =
      'window at ' + lastWin.x + ', ' + lastWin.y;
  });
}

/* ---- controls ---------------------------------------------------------- */
function rgbcss(t) { return 'rgb(' + t[0] + ',' + t[1] + ',' + t[2] + ')'; }

function buildTabs() {
  const el = document.getElementById('tabs');
  el.innerHTML = '';
  DECKS.forEach((k, d) => {
    const b = document.createElement('button');
    b.textContent = d;
    b.className = (d === cur ? 'on ' : '') + (edited(d) ? 'edited' : '');
    b.title = 'deck ' + d + ' - colour scheme ' + k.scheme;
    b.onclick = () => show(d);
    el.appendChild(b);
  });
}

function buildPalette() {
  const el = document.getElementById('palette'), k = deck(cur), p = phys(cur);
  el.innerHTML = '';
  for (let l = 0; l < 4; l++) {
    const row = document.createElement('div');
    row.className = 'lrow';
    const src = k.logical[l];
    row.innerHTML = '<span class="lname"><b>' + l + '</b> ' + ROLES[l] +
      '<br><span class="swatch" style="background:' + rgbcss(C64[src]) +
      '"></span> <span style="color:var(--dim)">' + C64N[src] + '</span></span>';
    const pick = document.createElement('div');
    pick.className = 'picker';
    for (let ph = 0; ph < 8; ph++) {
      const b = document.createElement('button');
      b.style.background = rgbcss(BBC[ph]);
      b.className = (p[l] === ph ? 'on' : '');
      b.title = ph + ' ' + BBCN[ph];
      b.onclick = () => {
        const np = phys(cur).slice(); np[l] = ph;
        setEdit(cur, 'physical', np);
        buildPalette(); buildTabs(); buildOverview(); redrawBBC();
        document.getElementById('bbcinfo').textContent = 'physical ' + np.join(' ');
      };
      pick.appendChild(b);
    }
    row.appendChild(pick);
    el.appendChild(row);
  }
  const msgs = [];
  if (new Set(p).size !== 4)
    msgs.push('Two logical colours share a physical one: detail drawn in the ' +
              'second is invisible, and verify_bbc.py asserts all four are ' +
              'distinct.');
  WANTS.forEach((want, l) => {
    if (want !== null && p[l] !== want)
      msgs.push('Logical ' + l + ' is ' + BBCN[p[l]] + ', not ' + BBCN[want] +
                '. The droids are drawn in logical 3, so it has to read as ' +
                'white on every deck.');
  });
  const w = document.getElementById('dupwarn');
  w.hidden = !msgs.length;
  w.innerHTML = msgs.join('<br><br>');
}

function buildOverview() {
  const el = document.getElementById('overview');
  el.innerHTML = '';
  DECKS.forEach((k, d) => {
    const p = phys(d);
    const row = document.createElement('div');
    row.className = 'ovrow' + (d === cur ? ' on' : '');
    row.onclick = () => show(d);
    let html = '<span class="ovn">' + d + '</span>';
    p.forEach(v => { html += '<span class="sw" style="background:' +
      rgbcss(BBC[v]) + '"></span>'; });
    html += '<span class="ovsch">s' + k.scheme + '</span>';
    const bad = WANTS.some((want, l) => want !== null && p[l] !== want) ||
                new Set(p).size !== 4;
    if (bad) html += '<span class="ovbad">!</span>';
    row.innerHTML = html;
    row.title = 'deck ' + d + ': ' + p.map((v, l) => l + '=' + BBCN[v]).join(', ');
    el.appendChild(row);
  });
}

function buildMerge() {
  const el = document.getElementById('merge'), k = deck(cur), m = cmap(cur);
  /* The background HAS to stay on logical 0: it is %00, so BuildLUTs gets a
     background pixel for free and DitherCharset finds one by asking which
     pixels are zero. export_bbc.py refuses to write colours.asm otherwise,
     so say it here rather than at build time. */
  const bgw = document.getElementById('bgwarn');
  bgw.hidden = m[k.logical[0]] === 0;
  bgw.textContent = 'The background (' + C64N[k.logical[0]] + ') is on logical '
    + m[k.logical[0]] + ', not 0. export_bbc.py will refuse this deck.';
  const total = k.counts.reduce((a, b) => a + b, 0) || 1;
  el.innerHTML = '';
  k.counts.forEach((n, c) => {
    if (!n) return;                       /* only colours this deck uses */
    const row = document.createElement('div');
    row.className = 'mrow';
    row.innerHTML = '<span class="swatch" style="background:' + rgbcss(C64[c]) +
      '"></span><span class="mname">' + C64N[c] + '</span>' +
      '<span class="mpct">' + (n * 100 / total).toFixed(1) + '%</span>';
    const seg = document.createElement('div');
    seg.className = 'seg';
    for (let l = 0; l < 4; l++) {
      const b = document.createElement('button');
      b.textContent = l;
      b.className = (m[c] === l ? 'on' : '');
      b.style.color = m[c] === l ? '#14161a' : rgbcss(BBC[phys(cur)[l]]);
      b.title = 'logical ' + l + ' (' + BBCN[phys(cur)[l]] + ')';
      b.onclick = () => {
        const nm = cmap(cur).slice(); nm[c] = l;
        setEdit(cur, 'colourMap', nm);
        buildMerge(); buildTabs(); buildOverview(); redrawBBC();
      };
      seg.appendChild(b);
    }
    row.appendChild(seg);
    el.appendChild(row);
  });
}

/* ---- save -------------------------------------------------------------- */
function payload() {
  const decks = {};
  DECKS.forEach((k, d) => {
    decks[d] = { physical: phys(d), colourMap: cmap(d) };
  });
  return {
    _comment: 'Written by tools/palette_lab.py. Read by tools/export_bbc.py ' +
              'when it regenerates src/data/colours.asm. physical = logical ' +
              '0-3 to BBC physical 0-7 (.deckPalette); colourMap = C64 colour ' +
              '0-15 to logical 0-3 (.colourMap). Delete this file to go back ' +
              'to the automatic assignment.',
    decks: decks
  };
}

document.getElementById('dl').onclick = () => {
  const blob = new Blob([JSON.stringify(payload(), null, 2)],
                        { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'deck_palettes.json';
  a.click();
  URL.revokeObjectURL(a.href);
  document.getElementById('saved').textContent =
    'Saved. Move it to tools/deck_palettes.json and re-run export_bbc.py.';
};

document.getElementById('cpasm').onclick = () => {
  const rows = [];
  for (let d = 0; d < 16; d += 4) {
    const line = [];
    for (let i = 0; i < 4; i++)
      phys(d + i).forEach(v => line.push('&0' + v));
    rows.push('  EQUB ' + line.join(','));
  }
  const text = '.deckPalette\n' + rows.join('\n') + '\n';
  navigator.clipboard.writeText(text).then(
    () => document.getElementById('saved').textContent = '.deckPalette copied.',
    () => document.getElementById('saved').textContent = text);
};

document.getElementById('rst').onclick = () => {
  delete edits[cur];
  localStorage.setItem(KEY, JSON.stringify(edits));
  show(cur);
};
document.getElementById('rstall').onclick = () => {
  if (!confirm('Discard every edit and go back to the values in the build?')) return;
  edits = {};
  localStorage.setItem(KEY, JSON.stringify(edits));
  show(cur);
};

document.getElementById('sprOn').onchange = e => {
  sprOn = e.target.checked; drawWindows(lastWin.x, lastWin.y);
};
document.getElementById('sprCol').onchange = e => {
  sprLogical = +e.target.value; drawWindows(lastWin.x, lastWin.y);
};
/* the rotor spins in the game, so it spins here - a still rotor hides how
   much of the droid is actually its thin blades */
setInterval(() => { if (sprOn) { sprPhase++; drawWindows(lastWin.x, lastWin.y); } }, 120);

document.getElementById('dither').onchange = e => {
  dither = e.target.value; redrawBBC();
};
document.getElementById('shade').onchange = e => {
  shadeLog = +e.target.value; redrawBBC();
};

document.getElementById('zoom').onchange = e => {
  zoom = e.target.value === 'fit' ? 'fit' : +e.target.value;
  applyZoom();
};
document.getElementById('layout').onchange = e => {
  document.getElementById('main').className = e.target.value === 'sbs' ? 'sbs' : '';
  applyZoom();
};
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowLeft' && cur > 0) show(cur - 1);
  if (e.key === 'ArrowRight' && cur < 15) show(cur + 1);
});
window.addEventListener('resize', applyZoom);

/* Keep the two scrollers in step so the same part of the deck is compared. */
const s64 = document.getElementById('scr64'), sbb = document.getElementById('scrbb');
let syncing = false;
for (const [a, b] of [[s64, sbb], [sbb, s64]]) {
  a.addEventListener('scroll', () => {
    if (syncing) return;
    syncing = true;
    b.scrollLeft = a.scrollLeft; b.scrollTop = a.scrollTop;
    syncing = false;
  });
}

/* ---- go ---------------------------------------------------------------- */
let pending = DECKS.length;
DECKS.forEach((k, d) => {
  const img = new Image();
  img.onload = () => {
    decodeIndices(d, img);
    if (--pending === 0) show(0);
  };
  img.src = 'data:image/png;base64,' + k.png;
  imgs[d] = img;
});
</script>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[1])
    ap.add_argument('--open', action='store_true',
                    help='open the page in the default browser when written')
    args = ap.parse_args()

    if not LST_FILE.exists():
        sys.exit('ERROR: %s not found (supply it locally, see CLAUDE.md)'
                 % LST_FILE)

    print('Reading %s' % LST_FILE.name)
    mem, _ = parse_listing(LST_FILE)

    decks = collect(mem)
    sprite = build_player_sprite(mem)
    print('  player   %s, %d phases, %d x %d'
          % (droid_number(mem, 0), FRAMES, SPR_W, SPR_H))

    data = {
        'decks': decks,
        'c64rgb': [list(c) for c in C64_RGB],
        'bbcrgb': [list(c) for c in BBC_RGB],
        'c64names': C64_NAMES,
        'bbcnames': BBC_NAMES,
        'roles': ROLE_NAMES,
        'wants': ROLE_WANTS,
        'sprite': {'w': SPR_W, 'h': SPR_H, 'phases': sprite},
        'view': [VIEW_W, VIEW_H],
    }
    html = PAGE.replace('__DATA__', json.dumps(data, separators=(',', ':')))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(html, encoding='utf-8')
    print('\nWrote %s  (%.0f KB)' % (OUT_FILE, OUT_FILE.stat().st_size / 1024))
    print('Open it in a browser; Save writes tools/deck_palettes.json, which')
    print('export_bbc.py picks up on its next run.')

    if args.open:
        webbrowser.open(OUT_FILE.as_uri())


if __name__ == '__main__':
    main()
