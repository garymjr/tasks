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

    var id_str: ?[]const u8 = null;
    var show_reverse = false;
    var no_color = false;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--reverse")) {
            show_reverse = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
            continue;
        }
        if (id_str == null) {
            id_str = arg;
        }
    }

    const id_value = id_str orelse {
        try stderr.writeAll("Error: Task ID is required\n");
        try stderr.writeAll("Usage: tasks graph <ID>\n");
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

    const options = display.resolveOptions(stdout, no_color);

    // Show task details
    try stdout.writeAll("\nTask Details:\n");
    try stdout.writeAll("─────────────\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);

    // Show cycle warning if detected
    if (task_store.hasCycle(task.id)) {
        try stdout.writeAll("\n⚠️  Warning: Cycle detected in dependency tree!\n");
    }
}
