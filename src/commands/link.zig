const std = @import("std");
const model = @import("../model.zig");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const LinkError = error{
    NotInitialized,
    MissingIds,
    InvalidId,
    TaskNotFound,
    CycleDetected,
    SelfDependency,
    AlreadyDependent,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "link"

    const child_id_str = iter.next() orelse {
        try stderr.writeAll("Error: Child task ID is required\n");
        try stderr.writeAll("Usage: tasks link <CHILD_ID> <PARENT_ID>\n");
        return error.MissingIds;
    };

    const parent_id_str = iter.next() orelse {
        try stderr.writeAll("Error: Parent task ID is required\n");
        try stderr.writeAll("Usage: tasks link <CHILD_ID> <PARENT_ID>\n");
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

    // Check for self-dependency
    const child_id_str_full = model.formatUuid(child.id);
    const parent_id_str_full = model.formatUuid(parent.id);
    if (std.mem.eql(u8, &child_id_str_full, &parent_id_str_full)) {
        try stderr.writeAll("Error: Task cannot depend on itself\n");
        return error.SelfDependency;
    }

    // Check if already dependent
    for (child.dependencies.items) |dep| {
        const dep_id = model.formatUuid(model.parseUuid(dep[0..36]) catch unreachable);
        if (std.mem.eql(u8, &dep_id, &parent_id_str_full)) {
            try stdout.writeAll("Dependency already exists.\n\n");
            const detail = try display.renderTaskDetail(allocator, child);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            return;
        }
    }

    // Check for cycle
    try child.dependencies.append(allocator, try allocator.dupe(u8, &parent_id_str_full));
    const has_cycle = task_store.hasCycle(child.id);
    const idx = child.dependencies.items.len - 1;
    const test_dep = child.dependencies.orderedRemove(idx);
    allocator.free(test_dep);

    if (has_cycle) {
        try stderr.writeAll("Error: Adding this dependency would create a cycle\n");
        return error.CycleDetected;
    }

    // Add dependency
    try child.dependencies.append(allocator, try allocator.dupe(u8, &parent_id_str_full));
    child.updateTimestamp();

    // Update blocked_by
    try task_store.updateBlockedBy();

    // Save
    try store.saveTasks(allocator, &task_store);

    // Show result
    const msg = try std.fmt.allocPrint(allocator, "Added dependency:\n  {s} → {s}\n\n", .{child_id_str, parent_id_str});
    defer allocator.free(msg);
    try stdout.writeAll(msg);

    try stdout.writeAll("Child task:\n");
    const child_detail = try display.renderTaskDetail(allocator, child);
    defer allocator.free(child_detail);
    try stdout.writeAll(child_detail);

    try stdout.writeAll("\nParent task:\n");
    const parent_detail = try display.renderTaskDetail(allocator, parent);
    defer allocator.free(parent_detail);
    try stdout.writeAll(parent_detail);
}
