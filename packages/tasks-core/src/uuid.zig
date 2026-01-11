const std = @import("std");

pub const Uuid = struct {
    data: [16]u8,
};

pub fn formatUuid(uuid: Uuid) [36]u8 {
    var result: [36]u8 = undefined;
    const d = uuid.data;
    const hex = "0123456789abcdef";

    var idx: usize = 0;
    for (d, 0..) |byte, i| {
        result[idx] = hex[byte >> 4];
        result[idx + 1] = hex[byte & 0x0F];
        idx += 2;
        if (i == 3 or i == 5 or i == 7 or i == 9) {
            result[idx] = '-';
            idx += 1;
        }
    }

    return result;
}

pub fn uuidToString(uuid: Uuid) [36]u8 {
    return formatUuid(uuid);
}

pub fn generateUuid() Uuid {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    random_bytes[6] = (random_bytes[6] & 0x0F) | 0x40;
    random_bytes[8] = (random_bytes[8] & 0x3F) | 0x80;

    return Uuid{ .data = random_bytes };
}

pub fn parseUuid(str: []const u8) !Uuid {
    if (str.len < 36) return error.InvalidUuid;

    var data: [16]u8 = undefined;
    const hex = "0123456789abcdef";
    var str_idx: usize = 0;

    inline for (0..16) |i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            str_idx += 1;
        }

        const hi = str[str_idx];
        const lo = str[str_idx + 1];
        str_idx += 2;

        const hi_val = std.mem.indexOfScalar(u8, hex[0..], std.ascii.toLower(hi)) orelse return error.InvalidUuid;
        const lo_val = std.mem.indexOfScalar(u8, hex[0..], std.ascii.toLower(lo)) orelse return error.InvalidUuid;

        data[i] = @as(u8, @intCast(hi_val * 16 + lo_val));
    }

    return Uuid{ .data = data };
}

test "generate uuid" {
    const uuid1 = generateUuid();
    const uuid2 = generateUuid();
    const str1 = uuidToString(uuid1);
    const str2 = uuidToString(uuid2);
    try std.testing.expect(!std.mem.eql(u8, &str1, &str2));
    try std.testing.expect(str1.len == 36);
}

test "parse uuid" {
    const uuid = generateUuid();
    const str = uuidToString(uuid);
    const parsed = try parseUuid(&str);
    try std.testing.expect(std.mem.eql(u8, &uuid.data, &parsed.data));
}
