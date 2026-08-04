\ ============================================================
\ hardware.asm — BBC Master 128 hardware register constants
\ ============================================================

\ ---- CRTC (Motorola 6845) ----
CRTC_ADDR  = &FE00              \ 6845 address register (write)
CRTC_DATA  = &FE01              \ 6845 data register (read/write)

\ CRTC register numbers
CRTC_R0  = 0                    \ Horizontal Total - 1
CRTC_R1  = 1                    \ Horizontal Displayed
CRTC_R2  = 2                    \ H Sync Position
CRTC_R3  = 3                    \ H/V Sync Widths
CRTC_R4  = 4                    \ Vertical Total - 1
CRTC_R5  = 5                    \ Vertical Total Adjust
CRTC_R6  = 6                    \ Vertical Displayed
CRTC_R7  = 7                    \ V Sync Position
CRTC_R8  = 8                    \ Interlace & Skew
CRTC_R9  = 9                    \ Max Scan Line Address (char height-1)
CRTC_R10 = 10                   \ Cursor Start
CRTC_R11 = 11                   \ Cursor End
CRTC_R12 = 12                   \ Start Address High
CRTC_R13 = 13                   \ Start Address Low

\ ---- Video ULA ----
VID_ULA_CTRL  = &FE20            \ Video ULA control register
VID_ULA_PAL   = &FE21            \ Video ULA palette register

\ ---- ACCCON — BBC Master shadow RAM / paging ----
ACCCON     = &FE34
ACCCON_SHADOW = &08              \ bit 3: 1 = video reads shadow RAM
ACCCON_CPU    = &04              \ bit 2: 1 = CPU accesses shadow at &3000–&7FFF
ACCCON_HAZEL  = &02              \ bit 1: 1 = HAZEL RAM at &C000–&DFFF

\ ---- System VIA ($FE40–$FE4F) ----
SYS_VIA_PB   = &FE40            \ Port B (output: LED etc.)
SYS_VIA_PA   = &FE4F            \ Port A (no handshake)
SND_DATA     = &FE41            \ SN76489 write (System VIA PA with handshake)
SYS_VIA_DDRB = &FE42            \ Port B direction register
SYS_VIA_DDRA = &FE43            \ Port A direction register
SYS_VIA_T1CL = &FE44            \ Timer 1 counter low
SYS_VIA_T1CH = &FE45            \ Timer 1 counter high
SYS_VIA_T1LL = &FE46            \ Timer 1 latch low
SYS_VIA_T1LH = &FE47            \ Timer 1 latch high
SYS_VIA_T2CL = &FE48            \ Timer 2 counter low
SYS_VIA_T2CH = &FE49            \ Timer 2 counter high
SYS_VIA_SR   = &FE4A            \ Shift Register
SYS_VIA_ACR  = &FE4B            \ Auxiliary Control Register
SYS_VIA_PCR  = &FE4C            \ Peripheral Control Register
SYS_VIA_IFR  = &FE4D            \ Interrupt Flag Register
SYS_VIA_IER  = &FE4E            \ Interrupt Enable Register

\ System VIA IFR/IER bit masks
SYS_IFR_CA2  = &01              \ CA2 interrupt
SYS_IFR_CA1  = &02              \ CA1 interrupt — this is VSYNC on BBC
SYS_IFR_SR   = &04              \ Shift register
SYS_IFR_CB2  = &08              \ CB2
SYS_IFR_CB1  = &10              \ CB1
SYS_IFR_T2   = &20              \ Timer 2
SYS_IFR_T1   = &40              \ Timer 1
SYS_IFR_ANY  = &80              \ Any interrupt active

\ ---- User VIA ($FE60–$FE6F) ----
USR_VIA_PB   = &FE60            \ Port B
USR_VIA_PA   = &FE6F            \ Port A (no handshake) — analogue port data
USR_VIA_DDRB = &FE62
USR_VIA_DDRA = &FE63
USR_VIA_T1CL = &FE64            \ Timer 1 counter low (we use this for mid-frame)
USR_VIA_T1CH = &FE65            \ Timer 1 counter high
USR_VIA_T1LL = &FE66            \ Timer 1 latch low
USR_VIA_T1LH = &FE67            \ Timer 1 latch high
USR_VIA_T2CL = &FE68
USR_VIA_T2CH = &FE69
USR_VIA_SR   = &FE6A
USR_VIA_ACR  = &FE6B            \ ACR: bits 7–6 control T1 mode
USR_VIA_PCR  = &FE6C
USR_VIA_IFR  = &FE6D            \ Interrupt Flag Register
USR_VIA_IER  = &FE6E            \ Interrupt Enable Register

\ User VIA IFR/IER bit masks
USR_IFR_T1   = &40              \ Timer 1 timeout

\ ---- Analogue (ADC) port — joystick ----
ADC_STATUS   = &FEC8            \ Analogue to Digital status/control
ADC_HI       = &FEC9            \ ADC result high byte
ADC_LO       = &FECA            \ ADC result low byte

\ ---- OS vectors & entry points ----
IRQ1V        = &0204            \ Secondary IRQ vector (lo, hi)
BRKV         = &0202            \ BRK vector
OSBYTE       = &FFF4            \ OSBYTE entry
OSWORD       = &FFF1            \ OSWORD entry
OSRDCH       = &FFE0            \ Read character from current input
OSWRCH       = &FFEE            \ Write character to current output

\ ---- Sideways RAM banking ----
ROMSEL       = &FE30            \ ROM select register (0–15)
ROMSEL_BANK0 = 0                \ Sideways RAM bank 0 (level maps)
ROMSEL_BANK1 = 1                \ Sideways RAM bank 1 (sprites/tiles)
ROMSEL_BANK2 = 2                \ Sideways RAM bank 2 (sound + xfer game)
ROMSEL_BANK3 = 3                \ Sideways RAM bank 3 (overflow)
SIDEWAYS     = &8000            \ Sideways RAM visible at $8000–$BFFF

\ ---- Screen memory layout ----
SCREEN_BASE  = &3000            \ Start of screen buffer (main RAM)
\ Shadow RAM buffer is also at &3000 when ACCCON_CPU set

\ Virtual scroll buffer dimensions
VBUF_COLS    = 24               \ Tile columns (192 px)
VBUF_ROWS    = 26               \ Tile rows   (208 px)
VBUF_BYTES   = 96               \ Bytes per scanline (192 px / 2 px/byte)
VBUF_STRIDE  = VBUF_BYTES       \ Alias: bytes per scanline in virtual buffer

\ Displayed viewport within virtual buffer
VIEW_COLS    = 20               \ Visible tile columns (160 px)
VIEW_ROWS    = 25               \ Visible tile rows (200 px)
VIEW_BYTES   = 80               \ Bytes per visible scanline

\ HUD (status bar) — scanlines 200–255
HUD_TOP_ROW  = 25               \ Tile row within screen (scanline 200)
HUD_ROWS     = 7                \ 7 tile rows × 8 px = 56 px
HUD_BYTES    = 80               \ Standard 80 bytes/scanline (no virtual pad)

\ CRTC start address for screen at SCREEN_BASE
\ physical = SCREEN_BASE + CRTC_addr * CRTC_BYTES_PER_UNIT + RA * VBUF_BYTES
\ where CRTC_BYTES_PER_UNIT = 2 (ULA fetches 2 bytes per CRTC clock in MODE 2)
\ and   R1 = VBUF_COLS * 2 = 48 (virtual buffer width in CRTC chars)
\ CRTC_start for SCREEN_BASE = 0 (CRTC address 0 maps to SCREEN_BASE)
\ NOTE: These values are for the virtual-buffer CRTC configuration set in
\       HAL_InitCRTC.  They may need adjustment after emulator testing.
CRTC_R1_VAL  = 48               \ Displayed+virtual width: 48 CRTC chars = 96 bytes
\ *** Phase 1 TODO: verify R1 in emulator — standard MODE 2 may use R1=40 ***

\ Timer 1 latch for mid-frame IRQ at scanline 200
\ Each scanline = 64 µs, adjusted for ~3-scanline IRQ latency
TIMER1_LATCH = (200 - 3) * 64  \ = 12608 = &3140

\ ---- Droid state table base ($0300) ----
DROID_TABLE  = &0300
DROID_STRIDE = 16               \ bytes per droid entry

\ ---- Sprite runtime state ($0400) ----
SPR_STATE    = &0400            \ Start of sprite runtime state
SPR_SLOT_SZ  = 160              \ bytes per sprite slot (background save etc.)
SPR_BGSAVE_SZ = 136             \ 17 rows × 8 bytes (16px wide + 1-byte misalign)
\ 8 slots × 160 bytes = 1280 bytes at $0400–$08FF

\ ---- Sprite/tile data in sideways RAM bank 1 ----
SPR_DEF_BASE = &8000            \ Base of sprite definitions in bank 1
SPR_DEF_SZ   = 512              \ 512 bytes per sprite definition (mask+data)
TILE_BASE    = SPR_DEF_BASE + (8 * SPR_DEF_SZ) \ Tiles after 8 sprite slots = $9000
TILE_SZ      = 32               \ 32 bytes per tile (8 rows × 4 bytes)

\ ---- SN76489 register encoding ----
\ Byte to write: $1 C C X X X X X  (latch byte for tone channel)
\                $0 0 X X X X X X  (data byte)
\ Channel C: 0=tone0, 1=tone1, 2=tone2, 3=noise
\ For tone channel C, freq reg N: write $80|($C<<5)|($N AND $0F), then $00|(N>>4)
\ For attenuation channel C, vol V: write $90|($C<<5)|(15-V)
SN_TONE0_LATCH = &80            \ Tone channel 0 frequency latch
SN_TONE1_LATCH = &A0            \ Tone channel 1 frequency latch
SN_TONE2_LATCH = &C0            \ Tone channel 2 frequency latch
SN_NOISE_LATCH = &E0            \ Noise channel control latch
SN_VOL0_LATCH  = &90            \ Volume channel 0 latch
SN_VOL1_LATCH  = &B0            \ Volume channel 1 latch
SN_VOL2_LATCH  = &D0            \ Volume channel 2 latch
SN_NVOL_LATCH  = &F0            \ Volume noise channel latch
SN_MUTE        = &0F            \ Attenuation = 15 (silence)
