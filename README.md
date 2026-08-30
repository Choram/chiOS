# chiOS

A small experimental 32-bit RISC-V operating system written in Zig.

Currently targeting QEMU `virt` with an S-mode kernel, Sv32 virtual
memory, trap handling, user-mode execution, and basic process
management.

## Status

- [x] M-mode → S-mode transition
- [x] FDT parsing
- [x] Physical page allocator
- [x] Sv32 virtual memory
- [x] Trap handling
- [x] User-mode execution
- [x] Process abstraction
- [ ] Scheduler
- [ ] System calls
- [ ] Filesystem
- [ ] Shell
