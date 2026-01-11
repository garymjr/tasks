const std = @import("std");

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
        @memcpy(result[offset .. offset + item.len], item);
        offset += item.len;
        if (i < items.len - 1) {
            @memcpy(result[offset .. offset + sep.len], sep);
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
