pub const UART_BASE: usize = 0x10000000;

const UART_THR: usize = 0;
const UART_LSR: usize = 5;

const LSR_THRE: u8 = 1 << 5;

fn reg(offset: usize) *volatile u8 {
    return @ptrFromInt(UART_BASE + offset);
}

pub fn putc(c: u8) void {
    while ((reg(UART_LSR).* & LSR_THRE) == 0) {}
    reg(UART_THR).* = c;
}

pub fn puts(s: []const u8) void {
    for (s) |c| {
        putc(c);
    }
}

// prints 32-bit hex numbers
pub fn putHex(value: usize) void {
    const digits = "0123456789abcdef";
    putc('0');
    putc('x');
    var shift: u5 = 28;

    while (true) {
        const digit = (value >> shift) & 0xf;
        putc(digits[digit]);

        if (shift == 0)
            break;

        shift -= 4;
    }
}

pub fn putDec(value: usize) void {
    if (value == 0) {
        putc('0');
        return;
    }

    var buf: [10]u8 = undefined;
    var n = value;
    var i: usize = 0;

    while (n != 0) {
        const digit = n % 10;
        buf[i] = '0' + @as(u8, @intCast(digit));
        n /= 10;
        i += 1;
    }

    while (i != 0) {
        i -= 1;
        putc(buf[i]);
    }
}
