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

pub const RenderOptions = struct {
    use_color: bool,
};

pub fn resolveOptions(stdout: std.fs.File, no_color: bool) RenderOptions {
    return .{ .use_color = stdout.isTty() and !no_color };
}

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

pub fn writeStyled(writer: anytype, options: RenderOptions, color: Color, text: []const u8) !void {
    if (options.use_color) try writer.writeAll(ansiCode(color));
    try writer.writeAll(text);
    if (options.use_color) try writer.writeAll(ansiCode(.reset));
}

pub fn writeStyledFmt(writer: anytype, options: RenderOptions, color: Color, comptime fmt: []const u8, args: anytype) !void {
    if (options.use_color) try writer.writeAll(ansiCode(color));
    try writer.print(fmt, args);
    if (options.use_color) try writer.writeAll(ansiCode(.reset));
}

fn writeColor(writer: anytype, options: RenderOptions, color: Color) !void {
    if (options.use_color) try writer.writeAll(ansiCode(color));
}

fn writeReset(writer: anytype, options: RenderOptions) !void {
    if (options.use_color) try writer.writeAll(ansiCode(.reset));
}

fn writeRepeated(writer: anytype, value: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeAll(value);
    }
}

fn textWidth(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch text.len;
}

fn writePadded(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    const visible_len = textWidth(text);
    if (visible_len < width) {
        try writeRepeated(writer, " ", width - visible_len);
    }
}

fn writeCell(writer: anytype, options: RenderOptions, color: ?Color, text: []const u8, width: usize) !void {
    if (color) |shade| {
        try writeColor(writer, options, shade);
    }
    try writePadded(writer, text, width);
    if (color != null) {
        try writeReset(writer, options);
    }
}

fn writeBorder(writer: anytype, left: []const u8, mid: []const u8, right: []const u8, widths: []const usize) !void {
    try writer.writeAll(left);
    for (widths, 0..) |width, idx| {
        try writeRepeated(writer, "─", width + 2);
        if (idx + 1 < widths.len) {
            try writer.writeAll(mid);
        }
    }
    try writer.writeAll(right);
    try writer.writeAll("\n");
}

fn sanitizedLen(text: []const u8) usize {
    var count: usize = 0;
    for (text) |ch| {
        if (ch < 0x20 or ch == 0x7f) {
            count += 1;
        } else {
            count += 1;
        }
    }
    return count;
}

fn sanitizeTruncateTitle(buf: []u8, text: []const u8, max_len: usize) []const u8 {
    if (max_len == 0) return buf[0..0];

    const total_len = sanitizedLen(text);
    if (total_len <= max_len) {
        var i: usize = 0;
        for (text) |ch| {
            if (i >= max_len) break;
            buf[i] = if (ch < 0x20 or ch == 0x7f) ' ' else ch;
            i += 1;
        }
        return buf[0..i];
    }

    if (max_len <= 3) {
        for (0..max_len) |i| {
            buf[i] = '.';
        }
        return buf[0..max_len];
    }

    const keep = max_len - 3;
    var i: usize = 0;
    for (text) |ch| {
        if (i >= keep) break;
        buf[i] = if (ch < 0x20 or ch == 0x7f) ' ' else ch;
        i += 1;
    }
    @memcpy(buf[keep .. keep + 3], "...");
    return buf[0..max_len];
}

fn statusColor(status: model.Status) Color {
    return switch (status) {
        .todo => .yellow,
        .in_progress => .blue,
        .done => .green,
        .blocked => .red,
    };
}

fn priorityColor(priority: model.Priority) ?Color {
    return switch (priority) {
        .low => .bright_black,
        .medium => null,
        .high => .yellow,
        .critical => .red,
    };
}

pub fn renderTaskTable(allocator: std.mem.Allocator, tasks: []const *Task, options: RenderOptions) ![]const u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    if (tasks.len == 0) {
        try writer.writeAll("No tasks found.\n");
        return buffer.toOwnedSlice(allocator);
    }

    const id_width: usize = 8;
    const status_width: usize = 15;
    const priority_width: usize = 12;
    const max_title_width: usize = 40;

    var title_width: usize = 5;
    for (tasks) |task| {
        const visible_len = sanitizedLen(task.title);
        title_width = @max(title_width, @min(visible_len, max_title_width));
    }

    const widths = [_]usize{ id_width, status_width, priority_width, title_width };

    try writeBorder(writer, "┌", "┬", "┐", &widths);
    try writer.writeAll("│ ");
    try writePadded(writer, "ID", id_width);
    try writer.writeAll(" │ ");
    try writePadded(writer, "Status", status_width);
    try writer.writeAll(" │ ");
    try writePadded(writer, "Priority", priority_width);
    try writer.writeAll(" │ ");
    try writePadded(writer, "Title", title_width);
    try writer.writeAll(" │\n");
    try writeBorder(writer, "├", "┼", "┤", &widths);

    for (tasks) |task| {
        const id_str = formatUuid(task.id)[0..8];

        var status_buf: [32]u8 = undefined;
        const status_text = try std.fmt.bufPrint(&status_buf, "{s} {s}", .{
            statusSymbol(task.status),
            statusName(task.status),
        });

        var priority_buf: [32]u8 = undefined;
        const priority_text = try std.fmt.bufPrint(&priority_buf, "{s} {s}", .{
            prioritySymbol(task.priority),
            priorityName(task.priority),
        });

        var title_buf: [40]u8 = undefined;
        const title = sanitizeTruncateTitle(&title_buf, task.title, title_width);

        try writer.writeAll("│ ");
        try writePadded(writer, id_str, id_width);
        try writer.writeAll(" │ ");
        try writeCell(writer, options, statusColor(task.status), status_text, status_width);
        try writer.writeAll(" │ ");
        try writeCell(writer, options, priorityColor(task.priority), priority_text, priority_width);
        try writer.writeAll(" │ ");
        try writePadded(writer, title, title_width);
        try writer.writeAll(" │\n");
    }

    try writeBorder(writer, "└", "┴", "┘", &widths);

    return buffer.toOwnedSlice(allocator);
}

pub fn renderTaskDetail(allocator: std.mem.Allocator, task: *const Task, options: RenderOptions) ![]const u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    const id_str = formatUuid(task.id);

    try writer.print("ID:          {s}\n", .{id_str});
    try writer.print("Title:       {s}\n", .{task.title});
    try writer.writeAll("Status:      ");
    try writeStyledFmt(writer, options, statusColor(task.status), "{s} {s}", .{
        statusSymbol(task.status),
        statusName(task.status),
    });
    try writer.writeAll("\n");
    try writer.writeAll("Priority:    ");
    if (priorityColor(task.priority)) |shade| {
        try writeStyledFmt(writer, options, shade, "{s} {s}", .{
            prioritySymbol(task.priority),
            priorityName(task.priority),
        });
    } else {
        try writer.print("{s} {s}", .{ prioritySymbol(task.priority), priorityName(task.priority) });
    }
    try writer.writeAll("\n");

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

    try writer.writeAll("Created:     ");
    try utils.formatRelativeToWriter(writer, task.created_at);
    try writer.writeAll("\n");

    if (task.updated_at != task.created_at) {
        try writer.writeAll("Updated:     ");
        try utils.formatRelativeToWriter(writer, task.updated_at);
        try writer.writeAll("\n");
    }

    if (task.completed_at) |completed| {
        try writer.writeAll("Completed:   ");
        try utils.formatRelativeToWriter(writer, completed);
        try writer.writeAll("\n");
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

    var tasks = [_]*Task{&task};
    const output = try renderTaskTable(allocator, &tasks, .{ .use_color = false });
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "Test task") != null);
}

test "render task table sanitizes title newlines" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try Task.init(allocator, "Quote \"test\"\nLine");
    defer task.deinit(allocator);

    var tasks = [_]*Task{&task};
    const output = try renderTaskTable(allocator, &tasks, .{ .use_color = false });
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "Quote \"test\" Line") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"test\"\nLine") == null);
}

test "render task detail" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    const output = try renderTaskDetail(allocator, &task, .{ .use_color = false });
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "Test task") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Status:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Priority:") != null);
}
