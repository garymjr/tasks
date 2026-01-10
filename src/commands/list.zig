const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const ListError = error{
    NotInitialized,
    InvalidStatus,
    InvalidPriority,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "list"

    // Parse optional flags
    var status_filter: ?model.Status = null;
    var priority_filter: ?model.Priority = null;
    var tag_filter: ?[]const u8 = null;
    var blocked_only = false;
    var unblocked_only = false;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--status")) {
            const status_str = iter.next() orelse continue;
            status_filter = std.meta.stringToEnum(model.Status, status_str) orelse {
                try stdout.writeAll("Error: Invalid status. Use: todo, in_progress, done, blocked\n");
                return error.InvalidStatus;
            };
        } else if (std.mem.eql(u8, arg, "--priority")) {
            const prio_str = iter.next() orelse continue;
            priority_filter = std.meta.stringToEnum(model.Priority, prio_str) orelse {
                try stdout.writeAll("Error: Invalid priority. Use: low, medium, high, critical\n");
                return error.InvalidPriority;
            };
        } else if (std.mem.eql(u8, arg, "--tags")) {
            tag_filter = iter.next();
        } else if (std.mem.eql(u8, arg, "--blocked")) {
            blocked_only = true;
        } else if (std.mem.eql(u8, arg, "--unblocked")) {
            unblocked_only = true;
        }
    }

    // Load tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Apply filters
    var filtered = std.ArrayListUnmanaged(*model.Task){};
    defer filtered.deinit(allocator);

    for (task_store.tasks.items) |task| {
        if (status_filter) |s| {
            if (task.status != s) continue;
        }

        if (priority_filter) |p| {
            if (task.priority != p) continue;
        }

        if (tag_filter) |tag| {
            var has_tag = false;
            for (task.tags.items) |t| {
                if (std.mem.eql(u8, t, tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (!has_tag) continue;
        }

        if (blocked_only) {
            if (task_store.isReady(task.*)) continue;
        }

        if (unblocked_only) {
            if (!task_store.isReady(task.*)) continue;
        }

        try filtered.append(allocator, task);
    }

    // Render
    const output = try display.renderTaskTable(allocator, filtered.items);
    defer allocator.free(output);
    try stdout.writeAll(output);
}

test "list filters by status" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    _ = try task_store.create("Task 1");
    const task2 = try task_store.create("Task 2");
    task2.setStatus(.in_progress);

    var filtered = task_store.filterByStatus(.in_progress);
    defer filtered.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), filtered.items.len);
}
