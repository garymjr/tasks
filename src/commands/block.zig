const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const BlockError = error{
    NotInitialized,
    MissingId,
    InvalidId,
    TaskNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "block"

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
        try stderr.writeAll("Usage: tasks block <ID>\n");
        return error.MissingId;
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task
    const task = task_store.findByShortId(id_value) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    const options = display.resolveOptions(stdout, no_color);

    // Check if already blocked
    if (task.status == .blocked) {
        try stdout.writeAll("Task is already blocked.\n\n");
        const detail = try display.renderTaskDetail(allocator, task, options);
        defer allocator.free(detail);
        try stdout.writeAll(detail);
        return;
    }

    // Mark as blocked
    task.setStatus(.blocked);

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    try stdout.writeAll("Marked task as blocked:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
