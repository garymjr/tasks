const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const AddError = error{
    NotInitialized,
    MissingTitle,
    InvalidPriority,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "add"

    var title: ?[]const u8 = null;

    // Parse optional flags
    var body: ?[]const u8 = null;
    var priority: model.Priority = .medium;
    var tags = std.ArrayListUnmanaged([]const u8){};
    var no_color = false;
    defer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit(allocator);
    }

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--body")) {
            body = iter.next() orelse continue;
            continue;
        }
        if (std.mem.eql(u8, arg, "--priority")) {
            const prio_str = iter.next() orelse continue;
            priority = std.meta.stringToEnum(model.Priority, prio_str) orelse {
                try stdout.writeAll("Error: Invalid priority. Use: low, medium, high, critical\n");
                return error.InvalidPriority;
            };
            continue;
        }
        if (std.mem.eql(u8, arg, "--tags")) {
            const tags_str = iter.next() orelse continue;
            var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
            while (tag_iter.next()) |tag| {
                const trimmed = std.mem.trim(u8, tag, " ");
                if (trimmed.len > 0) {
                    try tags.append(allocator, try allocator.dupe(u8, trimmed));
                }
            }
            continue;
        }
        if (title == null) {
            title = arg;
        }
    }

    const title_value = title orelse {
        try stdout.writeAll("Error: Title is required\n");
        try stdout.writeAll("Usage: tasks add \"TITLE\" [--body DESC] [--tags TAG,TAG] [--priority PRIORITY]\n");
        return error.MissingTitle;
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Create new task
    const task = try task_store.create(title_value);
    if (body) |b| {
        task.body = try allocator.dupe(u8, b);
    }
    task.priority = priority;

    for (tags.items) |tag| {
        try task.tags.append(allocator, try allocator.dupe(u8, tag));
    }

    // Save
    try store.saveTasks(allocator, &task_store);

    const options = display.resolveOptions(stdout, no_color);

    // Show result
    try stdout.writeAll("Created task:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}

test "add creates task" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    const task = try task_store.create("Test task");
    try testing.expectEqualStrings("Test task", task.title);
    try testing.expectEqual(model.Status.todo, task.status);
    try testing.expectEqual(model.Priority.medium, task.priority);
}
