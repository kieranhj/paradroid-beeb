"""
dataflow_config.py - what beebgame's dataflow analyses need to know about
Paradroid (tools/beebasm_dataflow.py passes it as --config). Every field is
documented in beeb-port-kit's template/tools/dataflow/gamecfg.py.
"""

# beebasm_dataflow.py's own: the -v listing to read, and the source folders
# its address-taken scan reads.
LISTING = 'build/paradroid.lst'
SOURCES = ('src',)

# The findings are reported against build/dataflow-in/src/listing.s.
GAME_DIR = 'src'

# The interrupt: InstallIrq puts IrqHandler at the head of IRQ1V (main.asm),
# and nothing else is ever stored there. It can run between any two
# instructions: every byte it reads is live everywhere.
ISR_ROOTS = ('IrqHandler',)

VAR_SEGMENTS = ()
