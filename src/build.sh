#!/usr/bin/env sh
set -eu

ARCH=rv32i_zicsr
ABI=ilp32

mkdir -p build/obj build/elf

echo "[AS] Assembling firmware.s"
riscv32-elf-as -march=$ARCH -mabi=$ABI firmware.s -o build/obj/firmware.o

echo "[AS] Assembling kernel_entry.s"
riscv32-elf-as -march=$ARCH -mabi=$ABI kernel_entry.s -o build/obj/kernel_entry.o

echo "[AS] Assembling sv32_control.s"
riscv32-elf-as -march=$ARCH -mabi=$ABI sv32_control.s -o build/obj/sv32_control.o

echo "[AS] Assembling trap_entry.s"
riscv32-elf-as -march=$ARCH -mabi=$ABI trap_entry.s -o build/obj/trap_entry.o

echo "[CP] Compile kernel.zig"
zig build-obj kernel.zig \
    -target riscv32-freestanding \
    -mcpu generic_rv32+zicsr \
    -O Debug \
    -fcompiler-rt \
    -femit-bin=build/obj/kernel.o

echo "[LD] Linking firmware"
riscv32-elf-ld -m elf32lriscv \
    -T linker_firmware.ld \
    build/obj/firmware.o \
    -o build/elf/firmware.elf

echo "[LD] Linking kernel"
riscv32-elf-ld -m elf32lriscv \
    -T linker_kernel.ld \
    build/obj/kernel_entry.o \
    build/obj/kernel.o \
    build/obj/sv32_control.o \
    build/obj/trap_entry.o \
    -o build/elf/kernel.elf

if [ "${1:-}" = "--run" ]; then
    qemu-system-riscv32 -M virt \
        -bios build/elf/firmware.elf \
        -device loader,file=build/elf/kernel.elf \
        -display none \
        -serial stdio \
        -monitor none
fi
