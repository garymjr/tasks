const std = @import("std");
const store = @import("../store.zig");

const InitError = error{
    AlreadyInitialized,
    InitFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    if (store.exists()) {
        try stdout.writeAll("Error: Already initialized in this directory\n");
        return error.AlreadyInitialized;
    }

    store.initStore(allocator) catch |e| {
        const msg = try std.fmt.allocPrint(allocator, "Error: Failed to initialize: {}\n", .{e});
        defer allocator.free(msg);
        try stdout.writeAll(msg);
        return error.InitFailed;
    };

    try stdout.writeAll("Initialized tasks repository in .tasks/\n");
}

test "init creates directory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    _ = store.initStore(allocator) catch |e| {
        if (e == error.AlreadyInitialized) {
            _ = store.deinitStore() catch {};
            _ = store.initStore(allocator) catch return e;
        } else {
            return e;
        }
    };

    try testing.expect(store.exists());
}
