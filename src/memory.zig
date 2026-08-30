pub const PAGE_SIZE: usize = 4096;

pub const Region = struct {
    start: usize,
    end: usize,
};

pub const FreePage = struct {
    next: ?*FreePage,
};

var free_head: ?*FreePage = null;
var free_count: usize = 0;

fn alignUp(x: usize) usize {
    return (x + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
}

fn alignDown(x: usize) usize {
    return x & ~(PAGE_SIZE - 1);
}

fn overlaps(start: usize, end: usize, region: Region) bool {
    return start < region.end and region.start < end;
}

fn isReserved(start: usize, end: usize, reserved: []const Region) bool {
    for (reserved) |region| {
        if (overlaps(start, end, region))
            return true;
    }

    return false;
}

pub fn freePageCount() usize {
    return free_count;
}

pub fn init(ram_base: usize, ram_size: usize, reserved: []const Region) void {
    free_head = null;
    free_count = 0;

    const start = alignUp(ram_base);
    const end = alignDown(ram_base + ram_size);
    var addr = start;

    while (addr < end) : (addr += PAGE_SIZE) {
        if (isReserved(addr, addr + PAGE_SIZE, reserved))
            continue;

        freePage(addr);
    }
}

pub fn freePage(addr: usize) void {
    const page: *FreePage = @ptrFromInt(addr);
    page.next = free_head;
    free_head = page;
    free_count += 1;
}

pub fn allocPage() ?usize {
    const page = free_head orelse return null;
    free_head = page.next;
    free_count -= 1;
    return @intFromPtr(page);
}

pub fn allocZeroedPage() ?usize {
    const addr = allocPage() orelse return null;
    const ptr: [*]u8 = @ptrFromInt(addr);
    @memset(ptr[0..PAGE_SIZE], 0);
    return addr;
}
