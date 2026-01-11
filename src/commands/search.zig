const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("../store.zig");
const display = @import("../display.zig");
const json = @import("../json.zig");

const SearchError = error{
    NotInitialized,
    MissingQuery,
    LoadFailed,
} || store.StorageError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "query", .kind = .positional, .position = 0, .required = true, .help = "Search query" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    _ = stderr;
    const query_parts = parser.getPositionals();
    const query = try std.mem.join(allocator, " ", query_parts);
    defer allocator.free(query);

    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var results = task_store.search(query);
    defer results.deinit(allocator);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"query\":");
        try json.writeJsonString(out, query);
        try out.writeAll(",\"tasks\":");
        try json.writeTaskArray(out, results.items);
        try out.writeAll("}\n");
        return;
    }

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
