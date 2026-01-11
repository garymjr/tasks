const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("tasks-store-json");
const display = @import("tasks-render");
const json = @import("../json.zig");
const utils = @import("../utils.zig");

const AddError = error{
    NotInitialized,
    MissingTitle,
    InvalidPriority,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "body", .long = "body", .kind = .option, .help = "Task body" },
    .{ .name = "priority", .long = "priority", .kind = .option, .help = "Task priority", .validator = validatePriority },
    .{ .name = "tags", .long = "tags", .kind = .option, .help = "Comma-separated tags" },
    .{ .name = "title", .kind = .positional, .position = 0, .required = true, .help = "Task title" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, parser: *argparse.Parser) !void {
    const title_value = try parser.getRequiredPositional("title");
    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");
    const body = parser.getOption("body");
    const body_hint = body == null or std.mem.trim(u8, body.?, " \t\r\n").len == 0;

    var priority: model.Priority = .medium;
    if (parser.getOption("priority")) |priority_str| {
        priority = try parsePriority(priority_str);
    }

    var tags = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (tags.items) |tag| allocator.free(tag);
        tags.deinit(allocator);
    }

    if (parser.getOption("tags")) |tags_str| {
        var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
        while (tag_iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                try tags.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
    }

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = try task_store.create(title_value);
    task.body = try utils.normalizeBody(allocator, body);
    task.priority = priority;

    for (tags.items) |tag| {
        try task.tags.append(allocator, try allocator.dupe(u8, tag));
    }

    try store.saveTasks(allocator, &task_store);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"task\":");
        try json.writeTask(out, task);
        try out.writeAll("}\n");
        return;
    }

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("Created task:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
    if (body_hint) {
        try stdout.writeAll("\nHint: add a body to give tasks more context.\n");
    }
}

fn parsePriority(value: []const u8) !model.Priority {
    return std.meta.stringToEnum(model.Priority, value) orelse argparse.Error.InvalidValue;
}

fn validatePriority(value: []const u8) anyerror!void {
    _ = try parsePriority(value);
}

test "add creates task" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    const task = try task_store.create("Test task");
    try testing.expectEqualStrings("Test task", task.title);
    try testing.expectEqual(model.Status.todo, task.status);
    try testing.expectEqual(model.Priority.medium, task.priority);
}
