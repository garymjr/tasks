const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const UnlinkError = error{
    NotInitialized,
    MissingIds,
    InvalidId,
    TaskNotFound,
    DependencyNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "unlink"

    const child_id_str = iter.next() orelse {
        try stderr.writeAll("Error: Child task ID is required\n");
        try stderr.writeAll("Usage: tasks unlink <CHILD_ID> <PARENT_ID>\n");
        return error.MissingIds;
    };

    const parent_id_str = iter.next() orelse {
        try stderr.writeAll("Error: Parent task ID is required\n");
        try stderr.writeAll("Usage: tasks unlink <CHILD_ID> <PARENT_ID>\n");
        return error.MissingIds;
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find tasks
    const child = task_store.findByShortId(child_id_str) orelse {
        try stderr.writeAll("Error: Child task not found\n");
        return error.TaskNotFound;
    };

    const parent = task_store.findByShortId(parent_id_str) orelse {
        try stderr.writeAll("Error: Parent task not found\n");
        return error.TaskNotFound;
    };

    // Find and remove dependency
    const parent_id_str_full = model.formatUuid(parent.id);
    var found_index: ?usize = null;

    for (child.dependencies.items, 0..) |dep, i| {
        const dep_id = model.formatUuid(model.parseUuid(dep[0..36]) catch unreachable);
        if (std.mem.eql(u8, &dep_id, &parent_id_str_full)) {
            found_index = i;
            break;
        }
    }

    if (found_index) |idx| {
        allocator.free(child.dependencies.items[idx]);
        _ = child.dependencies.orderedRemove(idx);
    } else {
        try stderr.writeAll("Error: Dependency not found\n");
        return error.DependencyNotFound;
    }

    child.updateTimestamp();

    // Update blocked_by
    try task_store.updateBlockedBy();

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    const msg = try std.fmt.allocPrint(allocator, "Removed dependency:\n  {s} → {s}\n\n", .{child_id_str, parent_id_str});
    defer allocator.free(msg);
    try stdout.writeAll(msg);

    const detail = try display.renderTaskDetail(allocator, child);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
