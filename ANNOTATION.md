# Paradroid CE — Assembly Listing Annotation
## Analysis for BBC Micro Port

> Source: `paradroid_ce.lst` (18,339 lines, M6502 assembly)
> Purpose: Document all major functions and C64 hardware dependencies to guide a port to the BBC Micro.

---

## 1. MEMORY MAP OVERVIEW

| Region | Address Range | Purpose |
|--------|--------------|---------|
| Zero Page | $0000–$00FF | All game variables (sprites, state, AI, scroll) |
| Stack | $0100–$01FF | 6502 hardware stack |
| Game variables (upper ZP) | $0002–$00FF | Position, score, mode flags |
| Sound driver | $0500–$091A | SID music/sound engine |
| I/O routines | $091A–$0A52 | Joystick, sprite R/W |
| Score/display | $0A7D–$0B6D | Score handling |
| Tape control | $0B6E–... | Tape motor (loading only) |
| Game init | $1242–$13D9 | StartGame |
| Main game loop | $13DA–$1544 | GameLoop |
| Per-frame update | $1545–$16FF | RunGame |
| Droid AI driver | $1700–$18C9 | RunDroids |
| Droid AI behaviour | $18CA–... | dMd0_droid, dMd1_bullet, dMd2_explosion |
| Game logic | $2000–$3589 | Doors, collisions, weapons, lifts |
| Level builder | $3590–$39F7 | BuildLevel, BuildIntroSprites |
| Screen renderer | $39F8–... | DrawScreen, CalcSpeed |
| Data tables | $6B00–$6FFF | All lookup tables, text, colors |
| IRQ handlers | $6EC0–$6FE9 | Raster IRQ chain + NMI stub |
| Transfer minigame | $E0D3–... | SubGameSelectSide and wire logic |
| Screen RAM (primary) | $4000–$43E7 | 40×25 character display |
| Screen RAM (alt) | $4C00–$4FE7 | Double-buffer screen |
| Sprite pointers | $4BF8–$4BFF | 8 sprite image pointers (VIC-II) |
| Color RAM | $D800–$DBFF | Per-character color attributes |

---

## 2. ZERO PAGE LAYOUT ($00–$FF)

### Tape / System
| Address | Name | Description |
|---------|------|-------------|
| $0001 | `byte_0_1` | Tape motor control / CIA interface flag |

### Sprite Scratch Registers ($04–$0E)
These mirror VIC-II sprite registers during processing (read/written by `RdSpriteState`/`WrSpriteState`).

| Address | Name | Description |
|---------|------|-------------|
| $0004 | `SpriteNum` | Current sprite index (0–7) |
| $0005–$0006 | `SpriteX` | Sprite X position (16-bit, MSB used for $D010) |
| $0007 | `SpriteY` | Sprite Y position |
| $0008 | `SpriteEna` | Sprite enable flag |
| $0009 | `SpriteYExp` | Sprite Y-expansion flag |
| $000A | `SpritePri` | Sprite priority (foreground/background) |
| $000B | `SpriteMC` | Sprite multicolor mode flag |
| $000C | `SpriteXExp` | Sprite X-expansion flag |
| $000D | `SpriteColor` | Sprite color index |
| $000E | `SpriteImage` | Sprite pattern pointer (index into sprite bank) |

### Temporary Variables
| Address | Name | Description |
|---------|------|-------------|
| $000F | `tmp1` | General scratch (DoScore, NextLevel, GetNewDir) |

### Player/Game State
| Address | Name | Description |
|---------|------|-------------|
| $0021–$0024 | `Score` | 4-byte BCD score |
| $0033 | `deckNum` | Current deck/level (0–7) |
| $003A | `moveMode` | Movement mode flags (walk, climb, etc.) |
| $003C | `consoleState` | Console/UI state machine index |
| $0048 | `hScroll` | Horizontal fine scroll value (applied in IRQ) |
| $0049 | `vScroll` | Vertical fine scroll value |
| $004B | `irqToggle` | IRQ phase toggle flag |
| $004C–$004D | `plyMapPos` | Player map position (16-bit word) |
| $004E | `charUnder` | Tile/char code beneath player |
| $004F | `SprSprCollision` | Sprite-sprite collision result |
| $005A | `bgColor` | Current background color (written to $D021) |
| $005C–$005D | `droidInfoData` | Pointer to active droid's data structure |
| $0076–$0077 | `MapPos` | General map position pointer |

### IRQ/Display
| Address | Name | Description |
|---------|------|-------------|
| $002C | `Irq1bgColor` | Background color used by IRQ phase 1 |

---

## 3. SUBROUTINE REFERENCE

### Sound Engine
| Address | Name | Description |
|---------|------|-------------|
| $0500 | `Sound` | Main SID music/sound driver. Updates all 3 SID voices. Called from `Irq_118` every frame at 50 Hz. |

### I/O Layer
| Address | Name | Description |
|---------|------|-------------|
| $091A | `ReadJoystick` | Reads CIA1 $DC00/$DC01 for joystick 2. Returns direction bits in A. |
| $0966 | `RdSpriteState` | Reads VIC-II sprite registers ($D000–$D01F) for sprite `SpriteNum` into ZP scratch ($04–$0E). |
| $09B7 | `WrSpriteState` | Writes ZP scratch ($04–$0E) back to VIC-II sprite registers for sprite `SpriteNum`. |
| $0A52 | `FillCRAM` | Fills Color RAM ($D800–$DBFF) using color from `SpriteColor` ZP. |

### Scoring
| Address | Name | Description |
|---------|------|-------------|
| $0A7D | `DoScore` | BCD arithmetic on `Score` ($0021–$0024). Renders score to screen RAM. |

### System / Loading
| Address | Name | Description |
|---------|------|-------------|
| $0B6E | `TapeMotorControl` | Controls tape motor via CIA registers. Used for level loading only. |

### Game Initialization
| Address | Name | Description |
|---------|------|-------------|
| $1242 | `StartGame` | Full game init: clears state, sets up VIC-II, CIA, sprites, sound, loads deck 0. |

### Main Loop
| Address | Name | Description |
|---------|------|-------------|
| $13DA | `GameLoop` | Outer game loop. Waits for IRQ frame sync then calls `RunGame`. |
| $1545 | `RunGame` | Per-frame update: runs droids, player movement, bullets, rendering, score. |

### Droid AI
| Address | Name | Description |
|---------|------|-------------|
| $1700 | `RunDroids` | Iterates over all active droid sprites; dispatches via `DroidModeJump` table. |
| $18CA | `dMd0_droid` | Normal droid behaviour: pathfinding, shooting, chasing player. Uses `nearXoffset`/`nearYoffset` tables. |
| $1BC1 | `dMd1_bullet` | Bullet projectile: moves bullet, checks wall/sprite collision, animates. |
| $1CF4 | `dMd2_explosion` | Explosion effect: cycles animation frames, then frees sprite. |

### Collision Detection
| Address | Name | Description |
|---------|------|-------------|
| (various) | `DoCollision` | Sprite-sprite and sprite-environment collision. Indexes `CollisionType` matrix at $6D6D. |
| (various) | `DoCollision2` | Secondary collision pass (player–droid interactions). |
| (various) | `SpriteHitWall` | Tests if sprite position overlaps a wall tile. |
| (various) | `ExplodeSprite` | Converts a sprite to explosion mode. |
| (various) | `GetDroidBySprNum` | Looks up droid record by sprite number. |

### Player Actions
| Address | Name | Description |
|---------|------|-------------|
| (various) | `MovePlyFire` | Move player fire (bullet) sprite each frame. |
| (various) | `DoFire` | Spawn bullet sprite when player fires. Uses `BulletSprite_t` and `BulletDisplacement_t`. |
| (various) | `CalcSpeed` | Acceleration/deceleration using `PlayerSpeed_t` table. |
| (various) | `GetNewDir` | Map joystick input to movement direction (0–7). |

### Weapon: Disruptor
| Address | Name | Description |
|---------|------|-------------|
| (various) | `Disruptor` | Special weapon effect. Checks `DisruptorImmune` table; freezes or damages droids. |

### Doors & Lifts
| Address | Name | Description |
|---------|------|-------------|
| $2A6D | `OpenDoor` | Animate door opening: edits screen RAM tiles. |
| $2B08 | `CloseDoors` | Animate door closing: restores screen RAM tiles. |
| (various) | `DoLift` | Handle player entering a lift. |
| (various) | `ChangeDeck` | Transition to new deck: calls `BuildLevel`, resets sprites. |
| (various) | `FindLift` | Find nearest lift position to player. |

### Level / Screen Building
| Address | Name | Description |
|---------|------|-------------|
| $3590 | `BuildLevel` | Constructs a deck: fills screen RAM and Color RAM from level data; places lifts, doors, floor tiles. |
| $3629 | `BuildIntroSprites` | Sets up the 8 hardware sprites for the title/intro sequence. |
| $39F8 | `DrawScreen` | Renders game viewport to screen RAM from map data; manages horizontal/vertical fine scroll registers. |

### Console / UI
| Address | Name | Description |
|---------|------|-------------|
| (various) | `Console` | Dispatches to console sub-screens via `conJump_t`. |
| (various) | `con_DroidInfo` | Displays selected droid stats (5 pages via `dInfoPgJump_t`). |
| (various) | `con_DeckInfo` | Displays current deck information. |
| (various) | `con_ShipInfo` | Displays overall ship/game status. |
| (various) | `PrintDroidInfo` | Formats and writes droid statistics to screen RAM. |
| (various) | `ShowRobotType` | Prints droid type name from `UnitType_txt`. |
| (various) | `conWaitInput` | Waits for console key/joystick input. |
| (various) | `ShowTitle` | Displays the game title screen. |
| (various) | `UpdateTextScore` | Refreshes score text in the status bar. |

### Transfer Minigame
| Address | Name | Description |
|---------|------|-------------|
| $E0D3 | `SubGameSelectSide` | Top-level transfer/capture minigame controller. |
| (various) | `xfer_PutRandom` | Places a random pulser circuit piece. |
| (various) | `xfer_PutAutoPulser` | Places an auto-advancing pulser. |
| (various) | `xfer_PutTerminator` | Places a signal terminator. |
| (various) | `xfer_PutSwitcher` | Places a signal switch (path redirect). |
| (various) | `xfer_PutSplitter` | Places a signal splitter (one-to-two). |
| (various) | `xfer_PutJoiner` | Places a signal joiner (two-to-one). |
| (various) | `xferInitDroid` | Initialise transfer board for selected droid. |
| (various) | `FinishTransfer1` | Successful transfer: award 2000 points, update game state. |
| (various) | `FinishTransfer2` | Transfer complete cleanup. |
| (various) | `BlowInto001` | Transfer minigame: "blow into 001" animation/logic. |

### Droid Lifecycle
| Address | Name | Description |
|---------|------|-------------|
| (various) | `KillDroid` | Award score, trigger explosion, free droid slot. |
| (various) | `DoAlertAndAging` | Raise alert level, age droid (increase aggression over time). |
| (various) | `NextLevel` | Advance to next deck after clearing all droids. |

### Interrupt Handlers
| Address | Name | Description |
|---------|------|-------------|
| $6EC0 | `Irq_254` | Raster IRQ at line 254. Frame-start bookkeeping. Sets next IRQ at line 91. **C64-specific.** |
| $6F04 | `Irq_91` | Raster IRQ at line 91. Applies vertical scroll, switches character set for top area. |
| $6F1B | `_d016Mode` | Sub of Irq_91: writes hScroll to $D016. |
| $6F4C | `Irq_118` | Raster IRQ at line 118. Restores character set, loads sprite pointers, calls `Sound`. **Audio sync point.** |
| $6FC0 | `Irq_246` | Raster IRQ at line 246. Reads sprite-sprite collision ($D01E), stores to `SprSprCollision`. |
| $6FE9 | `NMI` | NMI handler — just RTI (NMI disabled/ignored). |

---

## 4. C64 HARDWARE REFERENCE

### VIC-II Video Chip ($D000–$D3FF)

#### Sprite Registers ($D000–$D017)
| Register | Name | Usage in Game |
|----------|------|---------------|
| $D000+n×2 | Sprite n X low | Read by `RdSpriteState`; written by `WrSpriteState` |
| $D001+n×2 | Sprite n Y | Read by `RdSpriteState`; written by `WrSpriteState` |
| $D010 | Sprite X MSB | Combined from `SpriteX` high bit for all 8 sprites |
| $D015 | Sprite enable | Written in `WrSpriteState`, `dMd0_droid`, `dMd1_bullet`, `BlowInto001`, `BuildIntroSprites` |
| $D016 | Ctrl reg 2 (hscroll, MC) | Written in `Irq_91` / `_d016Mode` with `hScroll` ZP value |
| $D017 | Sprite Y-expand | Written via `SpriteYExp` |
| $D01B | Sprite/bg priority | Written via `SpritePri` |
| $D01C | Sprite multicolor | Written via `SpriteMC` |
| $D01D | Sprite X-expand | Written via `SpriteXExp` |
| $D01E | Sprite–sprite collision | **Read** in `Irq_246`, result stored in `SprSprCollision` |
| $D027–$D02E | Sprite 0–7 color | Written via `SpriteColor`; also `FillCRAM` |

#### Screen / Scroll Registers
| Register | Name | Usage |
|----------|------|-------|
| $D011 | Ctrl reg 1 (vscroll, blanking) | Fine vertical scroll; screen blank during level transitions |
| $D012 | Raster line | Used as IRQ trigger line; next line value written by each IRQ handler |
| $D018 | Memory pointers | Selects character set and screen RAM bank; switched in each IRQ phase ($21, $2D, $2F) |
| $D019 | IRQ status | Acknowledged in each IRQ handler (write $01 or $05) |
| $D01A | IRQ enable | Set to $01 (raster) or $05 in IRQ chain |
| $D020 | Border color | Set during intro/level transitions |
| $D021 | Background color | Written every IRQ phase from `bgColor` / `Irq1bgColor` ZP |

#### Character Set / Screen Bank
- VIC-II bank: CIA2 $DD00 selects 16 KB VIC-II bank (bank 1 = $4000–$7FFF used)
- $D018 values:
  - `$21` → screen at $4000, chars at $4800 (alternate set, top-of-screen / console area)
  - `$2D` → screen at $4C00, chars at $6800 (scrolling game area)
  - `$2F` → screen at $4C00, chars at $7800 (sprite area restored)

### SID Sound Chip ($D400–$D7FF)

| Register Range | Purpose | Game Usage |
|----------------|---------|------------|
| $D400–$D401 | Voice 1 frequency | Note pitch for voice 1 |
| $D402–$D403 | Voice 1 pulse width | Waveform timbre |
| $D404 | Voice 1 control | Attack/gate control |
| $D405–$D406 | Voice 1 ADSR | Envelope shaping |
| $D407–$D40E | Voice 2 (same layout) | Background harmony |
| $D40F–$D415 | Voice 3 (same layout) | Melody or effects |
| $D416–$D417 | Filter cutoff | Global filter frequency |
| $D418 | Volume / filter mode | Master volume (bits 0–3); filter routing |

All written by `Sound` routine ($0500), called from `Irq_118` at 50 Hz.
Per-deck background sound parameters: `deckBgSndVar1/2/3` ($6E60–$6E8F).

### CIA1 ($DC00–$DC0F) — Keyboard & Joystick

| Register | Usage |
|----------|-------|
| $DC00 | Joystick port 1 / keyboard column select |
| $DC01 | Joystick port 2 (game uses this) / keyboard row read |
| $DC0D | CIA1 interrupt control |
| $DC0E | CIA1 Timer A control |
| $DC0F | CIA1 Timer B control |

`ReadJoystick` ($091A) reads $DC01, masks direction and fire bits.

### CIA2 ($DD00–$DD0F) — VIC-II Bank & Serial

| Register | Usage |
|----------|-------|
| $DD00 | VIC-II bank select (bits 0–1 inverted): `%xxxxxx01` = bank 1 ($4000–$7FFF) |
| $DD02 | Data direction register for $DD00 |

### Color RAM ($D800–$DBFF)
- 1000 bytes (40×25), one nibble per character cell (values 0–15)
- Written by `FillCRAM` ($0A52) — bulk fill
- Written by `BuildLevel` ($3590) — per-cell color from level data
- Written by `DoScore` — score digit colors

### Interrupt Vectors
| Address | Vector | Game Usage |
|---------|--------|------------|
| $FFFE–$FFFF | IRQ vector | Rewritten by each IRQ phase to chain: `Irq_254 → Irq_91 → Irq_118 → Irq_246 → Irq_254` |
| $FFFA–$FFFB | NMI vector | Points to `NMI` ($6FE9) which is just `RTI` |

---

## 5. RASTER INTERRUPT CHAIN (C64-Specific Architecture)

The game uses a 4-stage raster-synchronized interrupt system to:
- Apply split-screen scroll effects (status bar vs. game area)
- Switch character sets mid-frame for different display areas
- Update sprite pointers precisely
- Drive the SID audio engine at exactly 50 Hz

```
Frame start
    │
    ▼
Irq_254 (line 254 — off-screen bottom)
  • Clear sprite enable overrides
  • Set Irq vector → Irq_91
  • Set $D012 = 91
    │
    ▼
Irq_91 (line 91 — mid-upper screen)
  • Write hScroll → $D016
  • Write vScroll → $D011
  • Switch character set: $D018 = $2D  (game area)
  • Set Irq vector → Irq_118
  • Set $D012 = 118
    │
    ▼
Irq_118 (line 118 — mid-lower screen)
  • Restore character set: $D018 = $2F
  • Update background color: $D021
  • Load 8 sprite pointers → $4BF8–$4BFF
  • CALL Sound ($0500)          ← audio synthesis happens here
  • Set Irq vector → Irq_246
  • Set $D012 = 246
    │
    ▼
Irq_246 (line 246 — bottom of display)
  • READ sprite-sprite collision: $D01E → SprSprCollision
  • Set Irq vector → Irq_254
  • Set $D012 = 254
    │
    └─→ (loop each frame)
```

**BBC Micro port implication**: Replace this entire chain with a single VSYNC interrupt. The split-screen effect must be achieved differently (BBC Micro has no raster interrupt — use the 6845 CRTC light pen / line-count register, or accept a simpler single-mode layout).

---

## 6. DATA TABLES REFERENCE

### Movement / Direction
| Label | Address | Contents |
|-------|---------|----------|
| `nearXoffset` | $6B52 | X offsets for 12 adjacent tiles: `$FF, 1, 0, 0, $FF, 1, $FE, $FF, $FE, 2, 1, 2` |
| `nearYoffset` | $6B5E | Y offsets for 12 adjacent tiles |
| `dirXdelta` | $6D8F | X movement per direction (8 dirs): `0, 1, 2, 2, 2, 1, 0, 0` |
| `dirYdelta` | $6D8D | Y movement per direction (8 dirs) |
| `PlayerSpeed_t` | $6D97 | 9-entry speed table: `0, 5, 6, 0, 7, 0, 0, 0, 7` |

### Lifts
| Label | Address | Contents |
|-------|---------|----------|
| `liftShaftX` | $6CB0 | 8 shaft X positions: `5, 9, 20, 28, 26, 23, 15, 21` |
| `liftShaftY` | $6CB8 | 8 shaft Y positions: `0, 3, 0, 1, 2, 7, 1, 4` |
| `liftShaftHeight` | $6CC0 | 8 shaft heights: `10, 9, 5, 2, 6, 3, 2, 7` |
| `liftPosDeck` | $6CC8 | Maps lift stop → deck number (31 entries) |
| `liftIdx2Shaft` | $6CE7 | Maps lift index → shaft (32 entries) |
| `liftPosX` | $6D07 | Absolute X coordinates for 24 lift stops |
| `liftPosY` | $6D26 | Absolute Y coordinates for 24 lift stops |

### Collision
| Label | Address | Contents |
|-------|---------|----------|
| `CollisionType` | $6D6D | 16-byte matrix: `$80`=nop, `$40`=explode, `$20`=friendly-fire check, `$10`=free sprite, `$08`=reverse, `$04`=player-fire kill |

### Weapons
| Label | Address | Contents |
|-------|---------|----------|
| `BulletSprite_t` | $6E4C | 8 bullet sprite image indices (one per direction) |
| `BulletDisplacement_t` | $6E58 | Bullet spawn displacement: `$F4, 0, $C, 8` |
| `DisruptorImmune` | $6E5B | 5 droid types immune to disruptor: `8, 17, 18, 20, 23` |

### Animation
| Label | Address | Contents |
|-------|---------|----------|
| `RotAnim_3_16L/M/R` | $6B1E | Droid rotation frames (left, mid, right) |
| `RotAnim_4_15L/M/R` | ~$6B35 | Alternate droid rotation frames |
| `ChrAnimData1` | $6C23 | 4-frame character animation pointers |
| `ChrAnimData2` | $6C28 | 8-frame recharger icon animation |
| `XferWire_anim` | $6C6C | Transfer minigame wire animation sequence |
| `LowNrgColor_t` | $6D49 | 8 colors for low-energy flashing |
| `LowNrgXferCol_t` | $6D51 | 8 colors for low-energy transfer mode |
| `AlertColors` | $6D45 | 4 alert-level colors: `$E5, $E7, $E8, $E2` |

### Scoring
| Label | Address | Contents |
|-------|---------|----------|
| `AlertScore` | $6DE8 | Points per alert level: `0, 5, 10, 25` |
| `ShootScore` | $6DEC | Points for kills by droid type: `0–250` |
| `BumpScore` | $6DF6 | Points for collision: `0–200` |

### Colors
| Label | Address | Contents |
|-------|---------|----------|
| `SpriteColor_t` | $6D59 | 10 sprite color animation values |
| `SpriteMc_t` | $6D63 | 10 sprite multicolor settings |

### Sound
| Label | Address | Contents |
|-------|---------|----------|
| `deckBgSndVar1` | $6E60 | 16 sound parameters set 1 (per-deck) |
| `deckBgSndVar2` | $6E70 | 16 sound parameters set 2 (per-deck) |
| `deckBgSndVar3` | $6E80 | 16 sound parameters set 3 (per-deck) |

### Jump Tables
| Label | Address | Entries |
|-------|---------|---------|
| `conJump_t` | $6BE1 | 4 console screen addresses |
| `dInfoPgJump_t` | $6BE9 | 5 droid-info page addresses |
| `DroidModeJump` | $6BF3 | 4 droid-mode subroutine addresses |

### Text Strings
| Label | Address | Content |
|-------|---------|---------|
| `UnitType_txt` | $6B77 | `"UNIT TYPE ???"` |
| `AccessGranted_txt` | $6E00 | `"ACCESS GRANTED"` |
| `Ship_txt` | $6E12 | `"SHIP :"` |
| `Deck_txt` | $6E1C | `"DECK :"` |
| `Alert_txt` | $6E26 | `"ALERT :"` |
| `Transmission_txt` | $6E30 | `"TRANSMISSION"` |
| `Terminated_txt` | $6E3F | `"TERMINATED"` |
| `NewShip_txt` | $6DA0 | New ship message |
| `ShipClear_txt` | $6DCE | Level complete message |

---

## 7. GAME SUBSYSTEMS OVERVIEW

### Game Loop Architecture
```
main → StartGame → GameLoop (loops)
                       └→ RunGame (every frame, IRQ-synced)
                              ├→ RunDroids → dMd0/1/2 (per active sprite)
                              ├→ MovePlyFire / DoFire
                              ├→ DoCollision / DoCollision2
                              ├→ DrawScreen
                              ├→ DoScore
                              └→ DoAlertAndAging
```

### Droid AI State Machine
Each droid sprite is in one of 4 modes (indexed via `DroidModeJump`):
- **Mode 0** (`dMd0_droid`): Live droid — pathfind, shoot, chase
- **Mode 1** (`dMd1_bullet`): Active bullet projectile
- **Mode 2** (`dMd2_explosion`): Explosion animation (then free)
- **Mode 3** (`dMd1_bullet` again): Appears to be enemy bullet

### Transfer Minigame
A circuit-puzzle game played when the player initiates a transfer:
1. Player and target droid each get a side of a wire grid
2. Players place circuit components (pulsers, switches, splitters, etc.)
3. Each side tries to advance their signal to the other's end
4. First to complete the circuit wins/loses control of the droid
5. Wire animation driven by `XferWire_anim` table

### Scoring
- All scores stored as 4-byte BCD at $0021–$0024
- Points awarded by: kills, alert raises, bumping droids, transfer wins
- 2000 bonus on successful transfer
- Score displayed via `DoScore` → `UpdateTextScore`

---

## 8. BBC MICRO PORT CONSIDERATIONS

### Hardware Mapping

| C64 Feature | BBC Micro Equivalent | Notes |
|-------------|---------------------|-------|
| VIC-II hardware sprites (8×24×21px) | Software sprites via MODE 4/5 | Must write own sprite renderer |
| SID 3-voice synthesis | SN76489 PSG (3 voices) or SOUND statement | SID envelope curves must be approximated |
| CIA joystick ($DC01) | Analogue port ($FE60–$FE63) or 1MHz bus | Different bit mapping |
| CIA keyboard scan | Keyboard matrix via system VIA ($FE40–$FE4F) | OS call `OSBYTE &81` or direct scan |
| 4-stage raster IRQ chain | Single 50Hz VSYNC IRQ | No per-scanline interrupt; split-screen needs CRTC tricks |
| Color RAM ($D800) | No equivalent — color per-character via VDU | BBC Micro MODE 4: 2 colours/char cell in teletext or bitmap |
| $D018 char bank switching | CRTC reg 12/13 for screen start | Character set fixed in ROM; custom via `*FX 20` page or shadow RAM |
| VIC-II bank via CIA2 | N/A | BBC Micro has one linear address space |
| Screen RAM $4000/$4C00 | &3000–&7FFF (MODE 4 = 20KB) | Double-buffering: use &3000 / &5800 |
| BCD score arithmetic | Same 6502 SED/CLD instructions | Directly portable |
| All 6502 instructions | Identical | 100% instruction compatibility |

### Direct Port Candidates (No Hardware Change)
- All game logic (AI, collision, scoring, doors, lifts) — pure 6502 arithmetic
- Map data and level tables
- All text strings
- BCD score routines
- Direction/movement delta tables
- Jump table dispatch mechanism

### Requires Significant Rewrite
1. **Sprite system**: Write a software sprite blitter for MODE 4 (two pixels per byte) or MODE 5
2. **IRQ system**: Replace 4-stage raster chain with single VSYNC handler
3. **Sound**: Map SID voice registers to SN76489 PSG; rewrite `Sound` routine
4. **Input**: Map CIA port reads to BBC Micro system VIA / analogue port
5. **Screen memory layout**: 40-column character map → BBC MODE 4 or equivalent; recalculate all screen addressing
6. **Color model**: VIC-II 16-color palette → BBC Micro 4-color or 8-color per mode
7. **Character sets**: Custom char ROM banking → use OS character RAM or self-modifying page

### Memory Budget (BBC Micro)
- Total RAM: 32 KB ($0000–$7FFF)
- OS workspace: $0000–$00FF zero page (BBC OS uses $00–$8F; game zero page must move to $90+)
- Screen RAM MODE 4: $3000–$7FFF (20 KB) — very tight
- Available for game: ~$0090–$2FFF ≈ 12 KB for code + data + game screen buffers
- **Recommendation**: Use MODE 5 (160×256, 8 colours) or MODE 2 to reduce screen memory to 10–20 KB and free more RAM

### Key Port Strategy
1. Start with a **hardware abstraction layer** (HAL) for: sprites, sound, input, screen RAM writes
2. Replace all C64 register addresses with BBC Micro equivalents through the HAL
3. Port game logic verbatim once HAL is in place
4. Optimise for BBC Micro memory layout last

---

*Document generated from `paradroid_ce.lst` (18,339 lines), March 2026.*
