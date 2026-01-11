const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const EditError = error{
    NotInitialized,
    MissingId,
    InvalidId,
    TaskNotFound,
    InvalidPriority,
    InvalidStatus,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "edit"

    var no_color = false;
    var id_str: ?[]const u8 = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
            continue;
        }
        id_str = arg;
        break;
    }

    const id_value = id_str orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks edit <ID> [--title TXT] [--body TXT] [--status S] [--priority P] [--tags TAGS]\n");
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

    // Parse flags
    var title: ?[]const u8 = null;
    var body: ?[]const u8 = null;
    var has_body = false;
    var status: ?model.Status = null;
    var priority: ?model.Priority = null;
    var tags: ?std.ArrayListUnmanaged([]const u8) = null;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--title")) {
            title = iter.next() orelse continue;
        } else if (std.mem.eql(u8, arg, "--body")) {
            body = iter.next() orelse continue;
            has_body = true;
        } else if (std.mem.eql(u8, arg, "--status")) {
            const status_str = iter.next() orelse continue;
            status = std.meta.stringToEnum(model.Status, status_str) orelse {
                try stderr.writeAll("Error: Invalid status. Use: todo, in_progress, done, blocked\n");
                return error.InvalidStatus;
            };
        } else if (std.mem.eql(u8, arg, "--priority")) {
            const prio_str = iter.next() orelse continue;
            priority = std.meta.stringToEnum(model.Priority, prio_str) orelse {
                try stderr.writeAll("Error: Invalid priority. Use: low, medium, high, critical\n");
                return error.InvalidPriority;
            };
        } else if (std.mem.eql(u8, arg, "--tags")) {
            const tags_str = iter.next() orelse continue;
            var new_tags = std.ArrayListUnmanaged([]const u8){};
            var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
            while (tag_iter.next()) |tag| {
                const trimmed = std.mem.trim(u8, tag, " ");
                if (trimmed.len > 0) {
                    try new_tags.append(allocator, try allocator.dupe(u8, trimmed));
                }
            }
            tags = new_tags;
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
        }
    }

    // Apply changes
    if (title) |t| {
        allocator.free(task.title);
        task.title = try allocator.dupe(u8, t);
        task.updateTimestamp();
    }

    if (has_body) {
        if (task.body) |old_body| {
            allocator.free(old_body);
        }
        if (body) |b| {
            task.body = try allocator.dupe(u8, b);
        } else {
            task.body = null;
        }
        task.updateTimestamp();
    }

    if (status) |s| {
        task.setStatus(s);
    }

    if (priority) |p| {
        task.priority = p;
        task.updateTimestamp();
    }

    if (tags) |*new_tags| {
        // Clear old tags
        for (task.tags.items) |tag| {
            allocator.free(tag);
        }
        task.tags.clearRetainingCapacity();

        // Add new tags
        for (new_tags.items) |tag| {
            try task.tags.append(allocator, try allocator.dupe(u8, tag));
        }

        // Cleanup temp tags
        for (new_tags.items) |tag| {
            allocator.free(tag);
        }
        new_tags.deinit(allocator);
        task.updateTimestamp();
    }

    // Save
    try store.saveTasks(allocator, &task_store);

    const options = display.resolveOptions(stdout, no_color);

    // Show result
    try stdout.writeAll("Updated task:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
