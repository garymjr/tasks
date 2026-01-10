const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const SearchError = error{
    NotInitialized,
    MissingQuery,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "search"

    // Query can be the remaining arguments joined by spaces
    var query_parts = std.ArrayListUnmanaged([]const u8){};
    defer query_parts.deinit(allocator);

    while (iter.next()) |arg| {
        try query_parts.append(allocator, arg);
    }

    if (query_parts.items.len == 0) {
        try stderr.writeAll("Error: Search query is required\n");
        try stderr.writeAll("Usage: tasks search <QUERY>\n");
        return error.MissingQuery;
    }

    // Join query parts with spaces
    const query = try std.mem.join(allocator, " ", query_parts.items);
    defer allocator.free(query);

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Search
    var results = task_store.search(query);
    defer results.deinit(allocator);

    // Render output
    if (results.items.len == 0) {
        const msg = try std.fmt.allocPrint(allocator, "No tasks found matching: {s}\n", .{query});
        defer allocator.free(msg);
        try stdout.writeAll(msg);
        return;
    }

    const header = try std.fmt.allocPrint(allocator, "Found {} task(s) matching: {s}\n\n", .{ results.items.len, query });
    defer allocator.free(header);
    try stdout.writeAll(header);

    const output = try display.renderTaskTable(allocator, results.items);
    defer allocator.free(output);
    try stdout.writeAll(output);
}
