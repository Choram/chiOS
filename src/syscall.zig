const uart = @import("uart.zig");

pub const SYS_PUTC: usize = 1;
pub const SYS_EXIT: usize = 2;

pub fn dispatch(
    number: usize,
    a0: usize,
    a1: usize,
    a2: usize,
    a3: usize,
    a4: usize,
    a5: usize,
) usize {
    _ = a1;
    _ = a2;
    _ = a3;
    _ = a4;
    _ = a5;

    switch (number) {
        SYS_PUTC => {
            uart.putc(@truncate(a0));
            return 0;
        },

        SYS_EXIT => {
            uart.puts("\nUser program exited with status ");
            uart.putHex(a0);
            uart.putc('\n');

            while (true) {}
        },

        else => {
            return 0xffff_ffff;
        },
    }
}
