const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const UnblockError = error{
    NotInitialized,
    MissingId,
    InvalidId,
    TaskNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "unblock"

    const id_str = iter.next() orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks unblock <ID>\n");
        return error.MissingId;
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task
    const task = task_store.findByShortId(id_str) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    // Check if not blocked
    if (task.status != .blocked) {
        try stdout.writeAll("Task is not blocked.\n\n");
        const detail = try display.renderTaskDetail(allocator, task);
        defer allocator.free(detail);
        try stdout.writeAll(detail);
        return;
    }

    // Reset to todo (unblock)
    task.setStatus(.todo);

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    try stdout.writeAll("Unblocked task (reset to todo):\n\n");
    const detail = try display.renderTaskDetail(allocator, task);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
