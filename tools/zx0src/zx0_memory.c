/*
 * (c) Copyright 2021 by Einar Saukas. All rights reserved.
 *
 * memory.c from the reference ZX0 (https://github.com/einar-saukas/ZX0),
 * BSD-3 like the rest — the one file missing from this build/ copy.
 */

#include <stdio.h>
#include <stdlib.h>

#include "zx0.h"

#define QTY_BLOCKS 10000

static BLOCK *ghost_root = NULL;
static BLOCK *dead_array = NULL;
static int dead_array_size = 0;

BLOCK *allocate(int bits, int index, int offset, BLOCK *chain) {
    BLOCK *ptr;

    if (ghost_root) {
        ptr = ghost_root;
        ghost_root = ptr->ghost_chain;
        if (ptr->chain && !--ptr->chain->references) {
            ptr->chain->ghost_chain = ghost_root;
            ghost_root = ptr->chain;
        }
    } else {
        if (!dead_array_size) {
            dead_array = (BLOCK *)malloc(QTY_BLOCKS*sizeof(BLOCK));
            if (!dead_array) {
                fprintf(stderr, "Error: Insufficient memory\n");
                exit(1);
            }
            dead_array_size = QTY_BLOCKS;
        }
        ptr = &dead_array[--dead_array_size];
    }
    ptr->bits = bits;
    ptr->index = index;
    ptr->offset = offset;
    if (chain)
        chain->references++;
    ptr->chain = chain;
    ptr->references = 0;
    return ptr;
}

void assign(BLOCK **ptr, BLOCK *chain) {
    chain->references++;
    if (*ptr && !--(*ptr)->references) {
        (*ptr)->ghost_chain = ghost_root;
        ghost_root = *ptr;
    }
    *ptr = chain;
}
