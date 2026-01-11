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

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "query", .kind = .positional, .position = 0, .required = true, .help = "Search query" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    _ = stderr;
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

