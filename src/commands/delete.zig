const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const DeleteError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
    HasDependents,
    SaveFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "delete"

    const id_str = iter.next() orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks delete <ID>\n");
        return error.MissingId;
    };

    // Load tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task
    const task = blk: {
        if (task_store.findByIdString(id_str) catch null) |t| {
            break :blk t;
        }
        if (task_store.findByShortId(id_str)) |t| {
            break :blk t;
        }
        break :blk null;
    } orelse {
        const msg = try std.fmt.allocPrint(allocator, "Error: Task not found: {s}\n", .{id_str});
        defer allocator.free(msg);
        try stderr.writeAll(msg);
        return error.TaskNotFound;
    };

    // Check if other tasks depend on this one
    const id_full = model.formatUuid(task.id);
    for (task_store.tasks.items) |t| {
        for (t.dependencies.items) |dep| {
            if (std.mem.eql(u8, dep, &id_full)) {
                const msg = try std.fmt.allocPrint(allocator,
                    "Error: Cannot delete task - other tasks depend on it.\n" ++
                    "Run 'tasks graph {s}' to see dependents.\n", .{id_str[0..8]});
                defer allocator.free(msg);
                try stderr.writeAll(msg);
                return error.HasDependents;
            }
        }
    }

    // Remove task
    const id = task.id;
    try task_store.removeByUuid(id);

    // Save
    try store.saveTasks(allocator, &task_store);

    const msg = try std.fmt.allocPrint(allocator, "Deleted task: {s}\n", .{id_str});
    defer allocator.free(msg);
    try stdout.writeAll(msg);
}

test "delete removes task" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    const task = try task_store.create("To delete");
    const id = task.id;

    try task_store.removeByUuid(id);
    try testing.expect(task_store.findByUuid(id) == null);
}
