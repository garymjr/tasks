const std = @import("std");
const argparse = @import("argparse");
const store = @import("../store.zig");

const InitError = error{
    AlreadyInitialized,
    InitFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{};

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, err);
        if (showed_help) return;
        return err;
    };

    if (store.exists()) {
        try stdout.writeAll("Error: Already initialized in this directory\n");
        return error.AlreadyInitialized;
    }

    store.initStore(allocator) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Error: Failed to initialize: {}\n", .{err});
        defer allocator.free(msg);
        try stdout.writeAll(msg);
        return error.InitFailed;
    };

    try stdout.writeAll("Initialized tasks repository in .tasks/\n");
}

fn writeParseError(allocator: std.mem.Allocator, parser: *argparse.Parser, stdout: std.fs.File, err: anyerror) !bool {
    switch (err) {
        argparse.Error.ShowHelp => {
            const help = try parser.help();
            defer allocator.free(help);
            try stdout.writeAll(help);
            return true;
        },
        else => {
            const parse_err: argparse.Error = @errorCast(err);
            const message = try parser.formatError(allocator, parse_err, .{ .color = .auto });
            defer allocator.free(message);
            try stdout.writeAll(message);
            try stdout.writeAll("\n");
            return false;
        },
    }
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
