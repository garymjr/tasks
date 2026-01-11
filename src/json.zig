const std = @import("std");
const model = @import("model.zig");

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            else => {
                if (byte < 0x20) {
                    const hex = "0123456789abcdef";
                    var esc: [6]u8 = .{ '\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0x0F] };
                    try writer.writeAll(&esc);
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn writeBool(writer: anytype, value: bool) !void {
    try writer.writeAll(if (value) "true" else "false");
}

pub fn writeOptionalString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

pub fn writeOptionalTimestamp(writer: anytype, value: ?i64) !void {
    if (value) |timestamp| {
        try writer.print("{}", .{timestamp});
    } else {
        try writer.writeAll("null");
    }
}

pub fn writeStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeAll("[");
    for (values, 0..) |value, index| {
        if (index > 0) try writer.writeAll(",");
        try writeJsonString(writer, value);
    }
    try writer.writeAll("]");
}

pub fn writeTask(writer: anytype, task: *const model.Task) !void {
    const id_str = model.formatUuid(task.id);

    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, &id_str);
    try writer.writeAll(",\"title\":");
    try writeJsonString(writer, task.title);
    try writer.writeAll(",\"body\":");
    try writeOptionalString(writer, task.body);
    try writer.writeAll(",\"status\":");
    try writeJsonString(writer, @tagName(task.status));
    try writer.writeAll(",\"priority\":");
    try writeJsonString(writer, @tagName(task.priority));
    try writer.writeAll(",\"tags\":");
    try writeStringArray(writer, task.tags.items);
    try writer.writeAll(",\"dependencies\":");
    try writeStringArray(writer, task.dependencies.items);
    try writer.writeAll(",\"created_at\":");
    try writer.print("{}", .{task.created_at});
    try writer.writeAll(",\"updated_at\":");
    try writer.print("{}", .{task.updated_at});
    try writer.writeAll(",\"completed_at\":");
    try writeOptionalTimestamp(writer, task.completed_at);
    try writer.writeAll("}");
}

pub fn writeTaskArray(writer: anytype, tasks: []const *model.Task) !void {
    try writer.writeAll("[");
    for (tasks, 0..) |task, index| {
        if (index > 0) try writer.writeAll(",");
        try writeTask(writer, task);
    }
    try writer.writeAll("]");
}

pub fn writeError(writer: anytype, message: []const u8) !void {
    try writer.writeAll("{\"error\":");
    try writeJsonString(writer, message);
    try writer.writeAll("}\n");
}

test "writeJsonString escapes characters" {
    const testing = std.testing;
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try writeJsonString(buffer.writer(), "\"line\n");
    try testing.expectEqualStrings("\\\"line\\n\"", buffer.items);
}

test "writeTask outputs expected fields" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task = try model.Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    task.body = try allocator.dupe(u8, "Body");
    try task.tags.append(allocator, try allocator.dupe(u8, "tag1"));
    try task.dependencies.append(allocator, try allocator.dupe(u8, "dep-id"));

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try writeTask(buffer.writer(), &task);

    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"title\":\"Test task\"") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"body\":\"Body\"") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"tags\":[\"tag1\"]") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"dependencies\":[\"dep-id\"]") != null);
}
