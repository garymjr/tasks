const std = @import("std");
const argparse = @import("argparse");
const graph = @import("tasks-core").graph;
const store = @import("../store.zig");
const display = @import("../display.zig");
const json = @import("../json.zig");
const model = @import("tasks-core").model;

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

    const cycle_detected = task_store.hasCycle(task.id);

    if (use_json) {
        var buffer: [8192]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"tree\":");
        try writeGraphTreeJson(out, &task_store, task, show_reverse);
        try out.writeAll(",\"root\":");
        try json.writeTask(out, task);
        try out.writeAll(",\"cycle_detected\":");
        try json.writeBool(out, cycle_detected);
        try out.writeAll("}\n");
        return;
    }

    const tree = if (show_reverse)
        try graph.renderReverseTree(allocator, &task_store, task.id)
    else
        try graph.renderTree(allocator, &task_store, task.id);
    defer allocator.free(tree);

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

fn writeGraphTreeJson(writer: anytype, task_store: *model.TaskStore, task: *const model.Task, show_reverse: bool) !void {
    const id_str = model.formatUuid(task.id);
    try writer.writeAll("{\"id\":");
    try json.writeJsonString(writer, &id_str);
    try writer.writeAll(",\"missing\":false,\"title\":");
    try json.writeJsonString(writer, task.title);
    try writer.writeAll(",\"status\":");
    try json.writeJsonString(writer, @tagName(task.status));
    try writer.writeAll(",\"children\":[");

    const deps = if (show_reverse) task.blocked_by.items else task.dependencies.items;
    var first_child = true;

    for (deps) |dep_str| {
        const trimmed = dep_str[0..@min(dep_str.len, 36)];
        const dep_id = model.parseUuid(trimmed) catch continue;

        if (!first_child) {
            try writer.writeAll(",");
        }
        first_child = false;

        const dep = task_store.findByUuid(dep_id) orelse {
            try writeMissingGraphNodeJson(writer, trimmed);
            continue;
        };

        try writeGraphTreeJson(writer, task_store, dep, show_reverse);
    }

    try writer.writeAll("]}");
}

fn writeMissingGraphNodeJson(writer: anytype, id_str: []const u8) !void {
    try writer.writeAll("{\"id\":");
    try json.writeJsonString(writer, id_str);
    try writer.writeAll(",\"missing\":true,\"title\":null,\"status\":null,\"children\":[]}");
}

test "graph json output excludes ascii tree" {
    const allocator = std.testing.allocator;
    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    const root = try task_store.create("Root");
    const child = try task_store.create("Child");
    const child_id = model.uuidToString(child.id);

    try root.dependencies.append(allocator, try allocator.dupe(u8, &child_id));

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try writeGraphTreeJson(buffer.writer(), &task_store, root, false);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "└") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "├") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "│") == null);
}
