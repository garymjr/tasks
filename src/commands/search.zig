const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const SearchError = error{
    NotInitialized,
    MissingQuery,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
        .{ .name = "query", .kind = .positional, .position = 0, .required = true, .help = "Search query" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

    const query_parts = parser.getPositionals();
    const query = try std.mem.join(allocator, " ", query_parts);
    defer allocator.free(query);

    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var results = task_store.search(query);
    defer results.deinit(allocator);

    if (results.items.len == 0) {
        const msg = try std.fmt.allocPrint(allocator, "No tasks found matching: {s}\n", .{query});
        defer allocator.free(msg);
        try stdout.writeAll(msg);
        return;
    }

    const header = try std.fmt.allocPrint(allocator, "Found {} task(s) matching: {s}\n\n", .{ results.items.len, query });
    defer allocator.free(header);
    try stdout.writeAll(header);

    const options = display.resolveOptions(stdout, no_color);
    const output = try display.renderTaskTable(allocator, results.items, options);
    defer allocator.free(output);
    try stdout.writeAll(output);
}

fn writeParseError(
    allocator: std.mem.Allocator,
    parser: *argparse.Parser,
    stdout: std.fs.File,
    stderr: std.fs.File,
    err: anyerror,
) !bool {
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
            try stderr.writeAll(message);
            try stderr.writeAll("\n");
            return false;
        },
    }
}
