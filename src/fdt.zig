const FDT_MAGIC: u32 = 0xd00dfeed;

const FDT_BEGIN_NODE: u32 = 1;
const FDT_END_NODE: u32 = 2;
const FDT_PROP: u32 = 3;
const FDT_NOP: u32 = 4;
const FDT_END: u32 = 9;

pub const MemoryRegion = struct {
    base: usize,
    size: usize,
};

// read big-endian cell
fn readBe32(ptr: [*]const u8, offset: usize) u32 {
    return (@as(u32, ptr[offset]) << 24) |
        (@as(u32, ptr[offset + 1]) << 16) |
        (@as(u32, ptr[offset + 2]) << 8) |
        (@as(u32, ptr[offset + 3]));
}

fn align4(x: usize) usize {
    return (x + 3) & ~@as(usize, 3);
}

fn stringEquals(ptr: [*]const u8, offset: usize, s: []const u8) bool {
    for (s, 0..) |c, i| {
        if (ptr[offset + i] != c) {
            return false;
        }
    }

    return ptr[offset + s.len] == 0;
}

fn stringStartsWith(ptr: [*]const u8, offset: usize, prefix: []const u8) bool {
    for (prefix, 0..) |c, i| {
        if (ptr[offset + i] != c)
            return false;
    }

    return true;
}

fn isMemoryNode(ptr: [*]const u8, offset: usize) bool {
    return stringStartsWith(ptr, offset, "memory@");
}

pub fn totalSize(fdt_addr: usize) ?usize {
    const fdt: [*]const u8 = @ptrFromInt(fdt_addr);

    if (readBe32(fdt, 0) != FDT_MAGIC)
        return null;

    return @intCast(readBe32(fdt, 4));
}

// concatenate two cells (or if cells == 1, then just return the one cell)
fn readCells(ptr: [*]const u8, offset: usize, cells: u32) ?u64 {
    if (cells == 0 or cells > 2)
        return null;

    var value: u64 = 0;
    var i: u32 = 0;

    while (i < cells) : (i += 1) {
        value <<= 32;
        value |= readBe32(ptr, offset + @as(usize, @intCast(i)) * 4);
    }

    return value;
}

pub fn findMemory(fdt_addr: usize) ?MemoryRegion {
    const fdt: [*]const u8 = @ptrFromInt(fdt_addr);
    if (readBe32(fdt, 0) != FDT_MAGIC)
        return null;

    const total_size: usize = @intCast(readBe32(fdt, 4));
    const struct_offset: usize = @intCast(readBe32(fdt, 8));
    const string_offset: usize = @intCast(readBe32(fdt, 12));

    // rules to read reg
    var address_cells: u32 = 2;
    var size_cells: u32 = 1;

    var depth: usize = 0;
    // memory_depth indicates whether we are in memory area or not
    var memory_depth: ?usize = null;

    var offset = struct_offset;

    while (offset < total_size) {
        const token = readBe32(fdt, offset);
        offset += 4;

        switch (token) {
            FDT_BEGIN_NODE => {
                const name_offset = offset;
                while (offset < total_size and fdt[offset] != 0)
                    offset += 1;

                if (offset >= total_size)
                    return null;

                offset = align4(offset + 1);
                depth += 1;

                // Root's direct child: memory@...
                if (depth == 2 and isMemoryNode(fdt, name_offset))
                    memory_depth = depth;
            },

            FDT_END_NODE => {
                // if we were at memory node, END_NODE indicates that
                // we exited the memory node
                if (memory_depth != null and memory_depth.? == depth)
                    memory_depth = null;

                if (depth == 0)
                    return null;

                depth -= 1;
            },

            FDT_PROP => {
                if (offset + 8 > total_size)
                    return null;

                const len: usize = @intCast(readBe32(fdt, offset));
                const name_offset: usize = @intCast(readBe32(fdt, offset + 4));

                const data_offset = offset + 8;
                const name = string_offset + name_offset;

                if (data_offset + len > total_size)
                    return null;

                // properties of root node
                if (depth == 1) {
                    if (stringEquals(fdt, name, "#address-cells"))
                        address_cells = readBe32(fdt, data_offset);

                    if (stringEquals(fdt, name, "#size-cells"))
                        size_cells = readBe32(fdt, data_offset);
                }

                if (memory_depth != null and
                    memory_depth.? == depth and
                    stringEquals(fdt, name, "reg"))
                {

                    // reg = <[address] [size]>
                    // [address] has size of address_cells * 4
                    // [size] has size of syze_cells * 4
                    // hence, [address] starts at data_offset
                    // and [size] starts at data_offset + addr_bytes
                    const addr_bytes = @as(usize, @intCast(address_cells)) * 4;
                    const required =
                        @as(usize, @intCast(address_cells + size_cells)) * 4;

                    if (len < required)
                        return null;

                    const base = readCells(
                        fdt,
                        data_offset,
                        address_cells,
                    ) orelse return null;

                    const size = readCells(
                        fdt,
                        data_offset + addr_bytes,
                        size_cells,
                    ) orelse return null;

                    // This kernel currently uses RV32 usize address
                    if (base > 0xffffffff or size > 0xffffffff)
                        return null;

                    return .{
                        .base = @intCast(base),
                        .size = @intCast(size),
                    };
                }

                offset = align4(data_offset + len);
            },

            FDT_NOP => {},

            FDT_END => return null,

            else => return null,
        }
    }

    return null;
}
