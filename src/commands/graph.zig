const std = @import("std");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const GraphError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "graph"

    const id_str = iter.next() orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks graph <ID>\n");
        return error.MissingId;
    };

    // Check for --reverse flag
    const show_reverse = blk: {
        const arg = iter.next();
        break :blk arg != null and std.mem.eql(u8, arg.?, "--reverse");
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Find task
    const task = task_store.findByShortId(id_str) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    if (show_reverse) {
        // Show reverse tree (tasks blocked by this task)
        const tree = try graph.renderReverseTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    } else {
        // Show forward tree (dependencies)
        const tree = try graph.renderTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    }

    // Show task details
    try stdout.writeAll("\nTask Details:\n");
    try stdout.writeAll("─────────────\n\n");
    const detail = try display.renderTaskDetail(allocator, task);
    defer allocator.free(detail);
    try stdout.writeAll(detail);

    // Show cycle warning if detected
    if (task_store.hasCycle(task.id)) {
        try stdout.writeAll("\n⚠️  Warning: Cycle detected in dependency tree!\n");
    }
}
