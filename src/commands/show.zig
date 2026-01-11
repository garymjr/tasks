const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const ShowError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "show"

    var no_color = false;
    var id_str: ?[]const u8 = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
            continue;
        }
        if (id_str == null) {
            id_str = arg;
        }
    }

    const id_value = id_str orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks show <ID>\n");
        return error.MissingId;
    };

    // Load tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task (try full UUID first, then short ID)
    const task = blk: {
        if (task_store.findByIdString(id_value) catch null) |t| {
            break :blk t;
        }
        if (task_store.findByShortId(id_value)) |t| {
            break :blk t;
        }
        break :blk null;
    } orelse {
        const msg = try std.fmt.allocPrint(allocator, "Error: Task not found: {s}\n", .{id_value});
        defer allocator.free(msg);
        try stderr.writeAll(msg);
        return error.TaskNotFound;
    };

    const options = display.resolveOptions(stdout, no_color);

    // Show details
    const output = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(output);
    try stdout.writeAll(output);
}

test "show requires id" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stdout_buf = std.ArrayList(u8).init(allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(allocator);
    defer stderr_buf.deinit();

    const result = run(allocator, .{ .handle = .{ .writer = stdout_buf.writer() } }, .{ .handle = .{ .writer = stderr_buf.writer() } });
    try testing.expectError(error.MissingId, result);
}
