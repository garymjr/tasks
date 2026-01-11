const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const TagError = error{
    NotInitialized,
    MissingId,
    MissingTag,
    InvalidId,
    TaskNotFound,
    TagAlreadyExists,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "tag"

    var no_color = false;
    var id_str: ?[]const u8 = null;
    var tag: ?[]const u8 = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
            continue;
        }
        if (id_str == null) {
            id_str = arg;
            continue;
        }
        if (tag == null) {
            tag = arg;
        }
    }

    const id_value = id_str orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks tag <ID> <TAG>\n");
        return error.MissingId;
    };

    const tag_value = tag orelse {
        try stderr.writeAll("Error: Tag is required\n");
        try stderr.writeAll("Usage: tasks tag <ID> <TAG>\n");
        return error.MissingTag;
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

    // Check if tag already exists
    for (task.tags.items) |t| {
        if (std.mem.eql(u8, t, tag_value)) {
            try stdout.writeAll("Tag already exists on this task.\n\n");
            const detail = try display.renderTaskDetail(allocator, task, options);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            return;
        }
    }

    // Add tag
    try task.tags.append(allocator, try allocator.dupe(u8, tag_value));
    task.updateTimestamp();

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    try stdout.writeAll("Added tag:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
