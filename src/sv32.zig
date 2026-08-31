const mem = @import("memory.zig");
const uart = @import("uart.zig");
const fdt = @import("fdt.zig");

pub const PAGE_SIZE = mem.PAGE_SIZE;
pub const ENTRIES_PER_PAGE: usize = 1024;

pub const PageTable = [ENTRIES_PER_PAGE]u32;

pub const PTE_V: u32 = 1 << 0;
pub const PTE_R: u32 = 1 << 1;
pub const PTE_W: u32 = 1 << 2;
pub const PTE_X: u32 = 1 << 3;
pub const PTE_U: u32 = 1 << 4;
pub const PTE_G: u32 = 1 << 5;
pub const PTE_A: u32 = 1 << 6;
pub const PTE_D: u32 = 1 << 7;

const PTE_RWX: u32 = PTE_R | PTE_W | PTE_X;

extern fn sfence_vma_all() void;
extern fn enable_sv32(root_pa: usize) void;

pub fn sfenceVma() void {
    sfence_vma_all();
}

pub fn enable(root_pa: usize) void {
    enable_sv32(root_pa);
}

fn isPageAligned(addr: usize) bool {
    return (addr & (PAGE_SIZE - 1)) == 0;
}

fn vpn1(va: usize) usize {
    return (va >> 22) & 0x3ff;
}

fn vpn0(va: usize) usize {
    return (va >> 12) & 0x3ff;
}

fn isValid(pte: u32) bool {
    return (pte & PTE_V) != 0;
}

fn isLeaf(pte: u32) bool {
    return (pte & PTE_RWX) != 0;
}

fn makePte(pa: usize, flags: u32) u32 {
    const ppn: u32 = @intCast(pa >> 12);
    return (ppn << 10) | flags;
}

fn pteToPa(pte: u32) usize {
    const ppn = pte >> 10;
    return @as(usize, ppn) << 12;
}

pub fn createRoot() ?*PageTable {
    const pa = mem.allocZeroedPage() orelse return null;
    return @ptrFromInt(pa);
}

pub fn mapPage(
    root: *PageTable,
    va: usize,
    pa: usize,
    flags: u32,
) bool {
    if (!isPageAligned(va) or !isPageAligned(pa))
        return false;

    // R = 0, W = 1 is an invalid Sv32 leaf encoding.
    if ((flags & PTE_W) != 0 and (flags & PTE_R) == 0)
        return false;

    // A leaf neads at least R or X
    if ((flags & (PTE_R | PTE_X)) == 0)
        return false;

    const idx1 = vpn1(va);
    const idx0 = vpn0(va);

    var level0: *PageTable = undefined;

    const root_pte = root[idx1];

    // If root[idx1] is empty.
    if (!isValid(root_pte)) {
        const level0_pa =
            mem.allocZeroedPage() orelse return false;

        level0 = @ptrFromInt(level0_pa);
        // This is non-leaf; V = 1 and RWX = 000
        root[idx1] = makePte(level0_pa, PTE_V);
    } else {
        // root[idx1] cannot be Leaf
        if (isLeaf(root_pte))
            return false;

        const level0_pa = pteToPa(root_pte);
        level0 = @ptrFromInt(level0_pa);
    }

    if (isValid(level0[idx0]))
        return false;

    // we just assume A = D = 1 for convenience
    var leaf_flags = flags | PTE_V | PTE_A;

    // Avoid needing dirty-bit handling during early bring-up.
    if ((flags & PTE_W) != 0)
        leaf_flags |= PTE_D;

    level0[idx0] = makePte(pa, leaf_flags);

    return true;
}

pub fn mapRange(
    root: *PageTable,
    va_start: usize,
    pa_start: usize,
    size: usize,
    flags: u32,
) bool {
    if (!isPageAligned(va_start) or
        !isPageAligned(pa_start) or
        (size & (PAGE_SIZE - 1)) != 0)
        return false;

    var offset: usize = 0;

    while (offset < size) : (offset += PAGE_SIZE) {
        if (!mapPage(
            root,
            va_start + offset,
            pa_start + offset,
            flags,
        ))
            return false;
    }

    return true;
}

pub fn identityMapRange(
    root: *PageTable,
    start: usize,
    size: usize,
    flags: u32,
) bool {
    return mapRange(root, start, start, size, flags);
}

pub fn init(ram: fdt.MemoryRegion) ?*PageTable {
    const root = createRoot() orelse {
        uart.puts("Cannot allocate root page table\n");
        return null;
    };

    uart.puts("Root page table OK\n");

    const root_pa = @intFromPtr(root);

    uart.puts("Root page table: ");
    uart.putHex(root_pa);
    uart.putc('\n');

    const ram_flag: usize = PTE_R | PTE_W | PTE_X;
    if (!identityMapRange(root, ram.base, ram.size, ram_flag)) {
        uart.puts("RAM mapping failed\n");
        return null;
    }

    uart.puts("RAM mapping OK\n");

    const uart_flag: usize = PTE_R | PTE_W;
    if (!identityMapRange(root, uart.UART_BASE, mem.PAGE_SIZE, uart_flag)) {
        uart.puts("UART mapping failed\n");
        return null;
    }

    uart.puts("UART mapping OK\n");

    uart.puts("Enabling Sv32...\n");

    enable_sv32(root_pa);

    uart.puts("Sv32 OK\n");

    return root;
}
