const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const AddError = error{
    NotInitialized,
    MissingTitle,
    InvalidPriority,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "body", .long = "body", .kind = .option, .help = "Task body" },
    .{ .name = "priority", .long = "priority", .kind = .option, .help = "Task priority", .validator = validatePriority },
    .{ .name = "tags", .long = "tags", .kind = .option, .help = "Comma-separated tags" },
    .{ .name = "title", .kind = .positional, .position = 0, .required = true, .help = "Task title" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, parser: *argparse.Parser) !void {
    const title_value = try parser.getRequiredPositional("title");
    const no_color = parser.getFlag("no-color");
    const body = parser.getOption("body");

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
    if (body) |body_value| {
        task.body = try allocator.dupe(u8, body_value);
    }
    task.priority = priority;

    for (tags.items) |tag| {
        try task.tags.append(allocator, try allocator.dupe(u8, tag));
    }

    try store.saveTasks(allocator, &task_store);

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("Created task:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
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
