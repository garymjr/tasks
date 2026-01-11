const std = @import("std");

pub fn formatTimestamp(timestamp: i64) []const u8 {
    // Convert Unix timestamp to local time string
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

    var buffer: [32]u8 = undefined;
    const month_str = monthName(month);
    const result = std.fmt.bufPrint(
        &buffer,
        "{s} {d:0>2} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2}",
        .{ month_str, day, year, hour, minute, second },
    ) catch "Invalid timestamp";

    // Return static buffer - caller should copy if needed
    // For now, we'll allocate in practice. This is for simple formatting.
    // A better implementation would accept a buffer allocator.
    var static_buf: [64]u8 = undefined;
    const len = @min(result.len, static_buf.len);
    @memcpy(static_buf[0..len], result);
    return static_buf[0..len];
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

    var buffer: [32]u8 = undefined;
    const result = if (diff < 60) {
        std.fmt.bufPrint(&buffer, "just now", .{}) catch "just now";
    } else if (diff < 3600) {
        const mins = diff / 60;
        std.fmt.bufPrint(&buffer, "{d}m ago", .{mins}) catch "recently";
    } else if (diff < 86400) {
        const hours = diff / 3600;
        std.fmt.bufPrint(&buffer, "{d}h ago", .{hours}) catch "today";
    } else if (diff < 604800) {
        const days = diff / 86400;
        std.fmt.bufPrint(&buffer, "{d}d ago", .{days}) catch "this week";
    } else {
        std.fmt.bufPrint(&buffer, "{d}w ago", .{diff / 604800}) catch "long ago";
    };

    var static_buf: [64]u8 = undefined;
    const len = @min(result.len, static_buf.len);
    @memcpy(static_buf[0..len], result);
    return static_buf[0..len];
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

pub fn pluralize(count: usize, singular: []const u8) []const u8 {
    if (count == 1) return singular;
    if (std.mem.endsWith(u8, singular, "s") or std.mem.endsWith(u8, singular, "x") or
       std.mem.endsWith(u8, singular, "ch") or std.mem.endsWith(u8, singular, "sh"))
    {
        // Already plural or irregular - return as-is for simplicity
        return singular;
    }
    return singular;
}

pub fn join(allocator: std.mem.Allocator, items: []const []const u8, sep: []const u8) ![]const u8 {
    if (items.len == 0) return allocator.dupe(u8, "");

    var total_len: usize = 0;
    for (items) |item| {
        total_len += item.len;
    }
    total_len += (items.len - 1) * sep.len;

    var result = try allocator.alloc(u8, total_len);
    var offset: usize = 0;

    for (items, 0..) |item, i| {
        @memcpy(result[offset..offset + item.len], item);
        offset += item.len;
        if (i < items.len - 1) {
            @memcpy(result[offset..offset + sep.len], sep);
            offset += sep.len;
        }
    }

    return result;
}

pub fn truncate(str: []const u8, max_len: usize) []const u8 {
    if (str.len <= max_len) return str;
    return str[0..max_len];
}

pub fn truncateWithEllipsis(buf: []u8, str: []const u8, max_len: usize) []const u8 {
    if (str.len <= max_len) return str;
    if (max_len == 0) return str[0..0];

    if (max_len <= 3) {
        for (0..max_len) |i| {
            buf[i] = '.';
        }
        return buf[0..max_len];
    }

    const keep = max_len - 3;
    @memcpy(buf[0..keep], str[0..keep]);
    @memcpy(buf[keep .. keep + 3], "...");
    return buf[0..max_len];
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

test "join strings" {
    const allocator = std.testing.allocator;

    const items = &[_][]const u8{ "a", "b", "c" };
    const joined = try join(allocator, items, ", ");
    defer allocator.free(joined);

    try std.testing.expectEqualStrings("a, b, c", joined);
}

test "join empty" {
    const allocator = std.testing.allocator;

    const items = &[_][]const u8{};
    const joined = try join(allocator, items, ", ");
    defer allocator.free(joined);

    try std.testing.expectEqualStrings("", joined);
}

test "join single" {
    const allocator = std.testing.allocator;

    const items = &[_][]const u8{"single"};
    const joined = try join(allocator, items, ", ");
    defer allocator.free(joined);

    try std.testing.expectEqualStrings("single", joined);
}

test "format relative to writer" {
    var buffer: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const now = std.time.timestamp();

    // Test just now
    try formatRelativeToWriter(writer, now);
    try std.testing.expectEqualStrings("just now", fbs.getWritten());

    // Reset buffer
    fbs.reset();

    // Test minutes ago
    try formatRelativeToWriter(writer, now - 120);
    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "m ago") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "2") != null);
}

test "truncate" {
    const long = "This is a very long string that needs truncation";
    const truncated = truncate(long, 20);
    try std.testing.expectEqual(@as(usize, 20), truncated.len);
}

test "truncate with ellipsis" {
    const long = "This is a very long string that needs truncation";
    var buf: [32]u8 = undefined;
    const truncated = truncateWithEllipsis(&buf, long, 20);
    try std.testing.expectEqual(@as(usize, 20), truncated.len);
    try std.testing.expect(std.mem.endsWith(u8, truncated, "..."));
}
