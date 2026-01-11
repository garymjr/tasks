const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("../store.zig");
const display = @import("../display.zig");
const json = @import("../json.zig");

const EditError = error{
    NotInitialized,
    MissingId,
    InvalidId,
    TaskNotFound,
    InvalidPriority,
    InvalidStatus,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "title", .long = "title", .kind = .option, .help = "Task title" },
    .{ .name = "body", .long = "body", .kind = .option, .help = "Task body" },
    .{ .name = "status", .long = "status", .kind = .option, .help = "Task status", .validator = validateStatus },
    .{ .name = "priority", .long = "priority", .kind = .option, .help = "Task priority", .validator = validatePriority },
    .{ .name = "tags", .long = "tags", .kind = .option, .help = "Comma-separated tags" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_value = try parser.getRequiredPositional("id");
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

    const title = parser.getOption("title");
    const body = parser.getOption("body");
    const has_body = parser.getOption("body") != null;

    var status: ?model.Status = null;
    if (parser.getOption("status")) |status_str| {
        status = try parseStatus(status_str);
    }

    var priority: ?model.Priority = null;
    if (parser.getOption("priority")) |priority_str| {
        priority = try parsePriority(priority_str);
    }

    var tags: ?std.ArrayListUnmanaged([]const u8) = null;
    if (parser.getOption("tags")) |tags_str| {
        var new_tags = std.ArrayListUnmanaged([]const u8){};
        var tag_iter = std.mem.splitScalar(u8, tags_str, ',');
        while (tag_iter.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " ");
            if (trimmed.len > 0) {
                try new_tags.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
        tags = new_tags;
    }

    if (title) |title_value| {
        allocator.free(task.title);
        task.title = try allocator.dupe(u8, title_value);
        task.updateTimestamp();
    }

    if (has_body) {
        if (task.body) |old_body| {
            allocator.free(old_body);
        }
        if (body) |body_value| {
            task.body = try allocator.dupe(u8, body_value);
        } else {
            task.body = null;
        }
        task.updateTimestamp();
    }

    if (status) |status_value| {
        task.setStatus(status_value);
    }

    if (priority) |priority_value| {
        task.priority = priority_value;
        task.updateTimestamp();
    }

    if (tags) |*new_tags| {
        for (task.tags.items) |tag| {
            allocator.free(tag);
        }
        task.tags.clearRetainingCapacity();

        for (new_tags.items) |tag| {
            try task.tags.append(allocator, try allocator.dupe(u8, tag));
        }

        for (new_tags.items) |tag| {
            allocator.free(tag);
        }
        new_tags.deinit(allocator);
        task.updateTimestamp();
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

    try stdout.writeAll("Updated task:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}

fn parseStatus(value: []const u8) !model.Status {
    return std.meta.stringToEnum(model.Status, value) orelse argparse.Error.InvalidValue;
}

fn parsePriority(value: []const u8) !model.Priority {
    return std.meta.stringToEnum(model.Priority, value) orelse argparse.Error.InvalidValue;
}

fn validateStatus(value: []const u8) anyerror!void {
    _ = try parseStatus(value);
}

fn validatePriority(value: []const u8) anyerror!void {
    _ = try parsePriority(value);
}
