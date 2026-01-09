const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{});
    _ = gpa.deinit();

    const cmd = try cli.parse();

    switch (cmd) {
        .help => std.debug.print("Command not yet implemented: {s}\n", .{@tagName(cmd)}),
        else => std.debug.print("Command not yet implemented: {s}\n", .{@tagName(cmd)}),
    }
}
