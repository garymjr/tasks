const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("tasks-store-json");
const json = @import("../json.zig");

const DeleteError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
    HasDependents,
    SaveFailed,
} || store.StorageError;

pub const args = [_]argparse.Arg{
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

fn shortId(id_str: []const u8) []const u8 {
    return id_str[0..@min(id_str.len, 8)];
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_str = try parser.getRequiredPositional("id");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = blk: {
        if (task_store.findByIdString(id_str) catch null) |task_value| {
            break :blk task_value;
        }
        if (task_store.findByShortId(id_str)) |task_value| {
            break :blk task_value;
        }
        break :blk null;
    } orelse {
        if (use_json) {
            const msg = try std.fmt.allocPrint(allocator, "Task not found: {s}", .{id_str});
            defer allocator.free(msg);
            var buffer: [512]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, msg);
            return error.TaskNotFound;
        }
        const msg = try std.fmt.allocPrint(allocator, "Error: Task not found: {s}\n", .{id_str});
        defer allocator.free(msg);
        try stderr.writeAll(msg);
        return error.TaskNotFound;
    };

    const id_full = model.formatUuid(task.id);
    for (task_store.tasks.items) |task_item| {
        for (task_item.dependencies.items) |dep| {
            if (std.mem.eql(u8, dep, &id_full)) {
                const short_id = shortId(id_str);
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Cannot delete task - other tasks depend on it. Run 'tasks graph {s}' to see dependents.",
                    .{short_id},
                );
                defer allocator.free(msg);
                if (use_json) {
                    var buffer: [512]u8 = undefined;
                    var writer = stdout.writer(&buffer);
                    defer writer.interface.flush() catch {};
                    const out = &writer.interface;
                    try json.writeError(out, msg);
                    return error.HasDependents;
                }
                const stderr_msg = try std.fmt.allocPrint(
                    allocator,
                    "Error: Cannot delete task - other tasks depend on it.\n" ++
                        "Run 'tasks graph {s}' to see dependents.\n",
                    .{short_id},
                );
                defer allocator.free(stderr_msg);
                try stderr.writeAll(stderr_msg);
                return error.HasDependents;
            }
        }
    }

    const id = task.id;
    const title = try allocator.dupe(u8, task.title);
    defer allocator.free(title);
    try task_store.removeByUuid(id);

    try store.saveTasks(allocator, &task_store);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        const deleted_id_full = model.formatUuid(id);
        try out.writeAll("{\"deleted_id\":");
        try json.writeJsonString(out, &deleted_id_full);
        try out.writeAll(",\"deleted_title\":");
        try json.writeJsonString(out, title);
        try out.writeAll("}\n");
        return;
    }

    const msg = try std.fmt.allocPrint(allocator, "Deleted task: {s}\n", .{id_str});
    defer allocator.free(msg);
    try stdout.writeAll(msg);
}

test "shortId handles short inputs" {
    const testing = std.testing;

    try testing.expectEqualStrings("abc", shortId("abc"));
    try testing.expectEqualStrings("12345678", shortId("1234567890"));
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
