#!/usr/bin/bash

# usage: rv_asm.sh [file.s]   (default main.s) -> main.bin, main.list
FNAME=${1:-main.s}

ONAME=main
STARTADDR=0
DATAADDR=1000
TESTDIR=.

# RISCV_PREFIX as in 4.build/sw_build/Makefile (default: xPack riscv-none-elf-)
PREFIX=${RISCV_PREFIX:-riscv-none-elf-}

${PREFIX}as -fpic -march=rv32imafdc -aghlms=$TESTDIR/$ONAME.list -o $TESTDIR/$ONAME.o $TESTDIR/$FNAME
${PREFIX}ld $TESTDIR/$ONAME.o -Ttext $STARTADDR -Tdata $DATAADDR -melf32lriscv -o $ONAME.bin
