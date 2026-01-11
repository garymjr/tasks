const std = @import("std");

threadlocal var timestamp_buf: [64]u8 = undefined;
threadlocal var relative_buf: [64]u8 = undefined;

pub fn formatTimestamp(timestamp: i64) []const u8 {
    const epoch = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(@max(0, timestamp))) };

    const day_seconds = epoch.getDaySeconds();
    const day_index = epoch.getEpochDay();

    var year: i32 = 1970;
    var month: std.time.epoch.Month = undefined;
    var day: u8 = undefined;

    const year_day = day_index.calculateYearDay();
    year = @as(i32, @intCast(year_day.year));
    const md = year_day.calculateMonthDay();
    month = md.month;
    day = md.day_index + 1;

    const hour: u5 = day_seconds.getHoursIntoDay();
    const minute: u6 = day_seconds.getMinutesIntoHour();
    const second: u6 = day_seconds.getSecondsIntoMinute();

    const month_str = monthName(month);
    const result = std.fmt.bufPrint(
        &timestamp_buf,
        "{s} {d:0>2} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2}",
        .{ month_str, day, year, hour, minute, second },
    ) catch "Invalid timestamp";
    return result;
}

pub fn formatTimestampAlloc(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const epoch = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(@max(0, timestamp))) };

    const day_seconds = epoch.getDaySeconds();
    const day_index = epoch.getEpochDay();

    var year: i32 = 1970;
    var month: std.time.epoch.Month = undefined;
    var day: u8 = undefined;

    const year_day = day_index.calculateYearDay();
    year = @as(i32, @intCast(year_day.year));
    const md = year_day.calculateMonthDay();
    month = md.month;
    day = md.day_index + 1;

    const hour: u5 = day_seconds.getHoursIntoDay();
    const minute: u6 = day_seconds.getMinutesIntoHour();
    const second: u6 = day_seconds.getSecondsIntoMinute();

    const month_str = monthName(month);
    return std.fmt.allocPrint(
        allocator,
        "{s} {d:0>2} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2}",
        .{ month_str, day, year, hour, minute, second },
    );
}

pub fn formatRelative(timestamp: i64) []const u8 {
    const now = std.time.timestamp();
    const diff = now - timestamp;

    const result = if (diff < 60) {
        std.fmt.bufPrint(&relative_buf, "just now", .{}) catch "just now";
    } else if (diff < 3600) {
        const mins = diff / 60;
        std.fmt.bufPrint(&relative_buf, "{d}m ago", .{mins}) catch "recently";
    } else if (diff < 86400) {
        const hours = diff / 3600;
        std.fmt.bufPrint(&relative_buf, "{d}h ago", .{hours}) catch "today";
    } else if (diff < 604800) {
        const days = diff / 86400;
        std.fmt.bufPrint(&relative_buf, "{d}d ago", .{days}) catch "this week";
    } else {
        std.fmt.bufPrint(&relative_buf, "{d}w ago", .{diff / 604800}) catch "long ago";
    };
    return result;
}

pub fn formatRelativeAlloc(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const now = std.time.timestamp();
    const diff = now - timestamp;

    if (diff < 60) {
        return allocator.dupe(u8, "just now");
    } else if (diff < 3600) {
        const mins = @divTrunc(diff, 60);
        return std.fmt.allocPrint(allocator, "{d}m ago", .{mins});
    } else if (diff < 86400) {
        const hours = @divTrunc(diff, 3600);
        return std.fmt.allocPrint(allocator, "{d}h ago", .{hours});
    } else if (diff < 604800) {
        const days = @divTrunc(diff, 86400);
        return std.fmt.allocPrint(allocator, "{d}d ago", .{days});
    } else {
        const weeks = @divTrunc(diff, 604800);
        return std.fmt.allocPrint(allocator, "{d}w ago", .{weeks});
    }
}

pub fn formatRelativeToWriter(writer: anytype, timestamp: i64) !void {
    const now = std.time.timestamp();
    const diff = now - timestamp;

    if (diff < 60) {
        try writer.writeAll("just now");
    } else if (diff < 3600) {
        const mins = @divTrunc(diff, 60);
        try writer.print("{d}m ago", .{mins});
    } else if (diff < 86400) {
        const hours = @divTrunc(diff, 3600);
        try writer.print("{d}h ago", .{hours});
    } else if (diff < 604800) {
        const days = @divTrunc(diff, 86400);
        try writer.print("{d}d ago", .{days});
    } else {
        const weeks = @divTrunc(diff, 604800);
        try writer.print("{d}w ago", .{weeks});
    }
}

fn monthName(month: std.time.epoch.Month) []const u8 {
    return switch (month) {
        .jan => "Jan",
        .feb => "Feb",
        .mar => "Mar",
        .apr => "Apr",
        .may => "May",
        .jun => "Jun",
        .jul => "Jul",
        .aug => "Aug",
        .sep => "Sep",
        .oct => "Oct",
        .nov => "Nov",
        .dec => "Dec",
    };
}

test "format timestamp alloc" {
    const allocator = std.testing.allocator;

    const ts: i64 = 1736450400; // 2025-01-09 12:00:00 UTC
    const formatted = try formatTimestampAlloc(allocator, ts);
    defer allocator.free(formatted);

    try std.testing.expect(formatted.len > 0);
}

test "format relative alloc" {
    const allocator = std.testing.allocator;

    const now = std.time.timestamp();
    const recent = try formatRelativeAlloc(allocator, now - 30);
    defer allocator.free(recent);
    try std.testing.expectEqualStrings("just now", recent);

    const minutes = try formatRelativeAlloc(allocator, now - 120);
    defer allocator.free(minutes);
    try std.testing.expect(std.mem.indexOf(u8, minutes, "m ago") != null);
}

test "format relative to writer" {
    var buffer: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const now = std.time.timestamp();

    try formatRelativeToWriter(writer, now);
    try std.testing.expectEqualStrings("just now", fbs.getWritten());

    fbs.reset();

    try formatRelativeToWriter(writer, now - 120);
    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "m ago") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "2") != null);
}
