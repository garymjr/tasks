const std = @import("std");
const argparse = @import("argparse");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const GraphError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "reverse", .long = "reverse", .kind = .flag, .help = "Show blocked tasks tree" },
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_value = try parser.getRequiredPositional("id");
    const show_reverse = parser.getFlag("reverse");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = task_store.findByShortId(id_value) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    if (show_reverse) {
        const tree = try graph.renderReverseTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    } else {
        const tree = try graph.renderTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    }

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("\nTask Details:\n");
    try stdout.writeAll("─────────────\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);

    if (task_store.hasCycle(task.id)) {
        try stdout.writeAll("\n⚠️  Warning: Cycle detected in dependency tree!\n");
    }
}

