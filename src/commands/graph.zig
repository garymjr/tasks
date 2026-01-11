const std = @import("std");
const argparse = @import("argparse");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");
const json = @import("../json.zig");

const GraphError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "reverse", .long = "reverse", .kind = .flag, .help = "Show blocked tasks tree" },
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_value = try parser.getRequiredPositional("id");
    const show_reverse = parser.getFlag("reverse");
    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = task_store.findByShortId(id_value) orelse {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "Task not found");
            return error.TaskNotFound;
        }
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    const tree = if (show_reverse)
        try graph.renderReverseTree(allocator, &task_store, task.id)
    else
        try graph.renderTree(allocator, &task_store, task.id);
    defer allocator.free(tree);

    const cycle_detected = task_store.hasCycle(task.id);

    if (use_json) {
        var buffer: [8192]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"tree\":");
        try json.writeJsonString(out, tree);
        try out.writeAll(",\"root\":");
        try json.writeTask(out, task);
        try out.writeAll(",\"cycle_detected\":");
        try json.writeBool(out, cycle_detected);
        try out.writeAll("}\n");
        return;
    }

    try stdout.writeAll(tree);

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("\nTask Details:\n");
    try stdout.writeAll("─────────────\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);

    if (cycle_detected) {
        try stdout.writeAll("\n⚠️  Warning: Cycle detected in dependency tree!\n");
    }
}

