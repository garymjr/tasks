const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const UntagError = error{
    NotInitialized,
    MissingId,
    MissingTag,
    InvalidId,
    TaskNotFound,
    TagNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "untag"

    const id_str = iter.next() orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks untag <ID> <TAG>\n");
        return error.MissingId;
    };

    const tag = iter.next() orelse {
        try stderr.writeAll("Error: Tag is required\n");
        try stderr.writeAll("Usage: tasks untag <ID> <TAG>\n");
        return error.MissingTag;
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task
    const task = task_store.findByShortId(id_str) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    // Find and remove tag
    var found = false;
    for (task.tags.items, 0..) |t, i| {
        if (std.mem.eql(u8, t, tag)) {
            allocator.free(t);
            _ = task.tags.orderedRemove(i);
            found = true;
            break;
        }
    }

    if (!found) {
        try stderr.writeAll("Error: Tag not found on this task\n");
        return error.TagNotFound;
    }

    task.updateTimestamp();

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    try stdout.writeAll("Removed tag:\n\n");
    const detail = try display.renderTaskDetail(allocator, task);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
