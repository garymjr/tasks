const std = @import("std");
const argparse = @import("argparse");
const store = @import("../store.zig");

const InitError = error{
    AlreadyInitialized,
    InitFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, parser: *argparse.Parser) !void {
    const use_json = parser.getFlag("json");

    if (store.exists()) {
        if (use_json) {
            try stdout.writeAll("{\"ok\":false,\"message\":\"Already initialized in this directory\"}\n");
        } else {
            try stdout.writeAll("Error: Already initialized in this directory\n");
        }
        return error.AlreadyInitialized;
    }

    store.initStore(allocator) catch |err| {
        if (use_json) {
            const msg = try std.fmt.allocPrint(allocator, "{{\"ok\":false,\"message\":\"Failed to initialize: {}\"}}\n", .{err});
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        } else {
            const msg = try std.fmt.allocPrint(allocator, "Error: Failed to initialize: {}\n", .{err});
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        }
        return error.InitFailed;
    };

    if (use_json) {
        try stdout.writeAll("{\"ok\":true,\"message\":\"Initialized tasks repository in .tasks/\"}\n");
        return;
    }

    try stdout.writeAll("Initialized tasks repository in .tasks/\n");
}


test "init creates directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    _ = store.initStore(allocator) catch |err| {
        if (err == error.AlreadyInitialized) {
            _ = store.deinitStore() catch {};
            _ = store.initStore(allocator) catch return err;
        } else {
            return err;
        }
    };

    try testing.expect(store.exists());
}
