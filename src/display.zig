const std = @import("std");
const model = @import("model.zig");
const Task = model.Task;
const formatUuid = model.formatUuid;
const utils = @import("utils.zig");

pub const Color = enum {
    reset,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_white,
};

pub fn ansiCode(c: Color) []const u8 {
    return switch (c) {
        .reset => "\x1b[0m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .magenta => "\x1b[35m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .bright_black => "\x1b[90m",
        .bright_white => "\x1b[97m",
    };
}

pub fn renderTaskTable(allocator: std.mem.Allocator, tasks: []const *Task) ![]const u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    if (tasks.len == 0) {
        try writer.writeAll("No tasks found.\n");
        return buffer.toOwnedSlice(allocator);
    }

    try writer.writeAll("ID      Status    Priority  Title\n");
    try writer.writeAll("────────────────────────────────────────────\n");

    for (tasks) |task| {
        const id_str = formatUuid(task.id)[0..8];
        const status_name = statusName(task.status);
        const priority_name = priorityName(task.priority);

        try writer.print("{s}  {s:<9} {s:<9} {s}\n", .{
            id_str,
            status_name,
            priority_name,
            task.title,
        });
    }

    return buffer.toOwnedSlice(allocator);
}

pub fn renderTaskDetail(allocator: std.mem.Allocator, task: *const Task) ![]const u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    const id_str = formatUuid(task.id);

    try writer.print("ID:          {s}\n", .{id_str});
    try writer.print("Title:       {s}\n", .{task.title});
    try writer.print("Status:      {s}\n", .{statusName(task.status)});
    try writer.print("Priority:    {s}\n", .{priorityName(task.priority)});

    if (task.tags.items.len > 0) {
        try writer.writeAll("Tags:        ");
        for (task.tags.items, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(tag);
        }
        try writer.writeAll("\n");
    }

    if (task.dependencies.items.len > 0) {
        try writer.writeAll("Depends on:  ");
        for (task.dependencies.items, 0..) |dep, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s}", .{dep[0..8]});
        }
        try writer.writeAll("\n");
    } else {
        try writer.writeAll("Depends on:  (none)\n");
    }

    try writer.print("Created:     {s}\n", .{utils.formatRelativeAlloc(allocator, task.created_at) catch "?"});

    if (task.updated_at != task.created_at) {
        try writer.print("Updated:     {s}\n", .{utils.formatRelativeAlloc(allocator, task.updated_at) catch "?"});
    }

    if (task.completed_at) |completed| {
        try writer.print("Completed:   {s}\n", .{utils.formatRelativeAlloc(allocator, completed) catch "?"});
    }

    if (task.body) |body| {
        try writer.writeAll("\nDescription:\n");
        try writer.print("  {s}\n", .{body});
    }

    return buffer.toOwnedSlice(allocator);
}

pub fn statusSymbol(status: model.Status) []const u8 {
    return switch (status) {
        .todo => "●",
        .in_progress => "◉",
        .done => "✓",
        .blocked => "⊘",
    };
}

pub fn statusName(status: model.Status) []const u8 {
    return switch (status) {
        .todo => "todo",
        .in_progress => "in_progress",
        .done => "done",
        .blocked => "blocked",
    };
}

pub fn prioritySymbol(priority: model.Priority) []const u8 {
    return switch (priority) {
        .low => "○",
        .medium => "◐",
        .high => "●",
        .critical => "⚠",
    };
}

pub fn priorityName(priority: model.Priority) []const u8 {
    return switch (priority) {
        .low => "low",
        .medium => "medium",
        .high => "high",
        .critical => "critical",
    };
}

test "render task table" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    var tasks = [_]*const Task{&task};
    const output = try renderTaskTable(allocator, &tasks);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "Test task") != null);
}

test "render task detail" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    const output = try renderTaskDetail(allocator, &task);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "Test task") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Status:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Priority:") != null);
}
