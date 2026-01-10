const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");

const TagsError = error{
    NotInitialized,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Collect tag counts
    var tag_counts = std.StringHashMap(usize).init(allocator);
    defer tag_counts.deinit();

    for (task_store.tasks.items) |task| {
        for (task.tags.items) |tag| {
            const count = tag_counts.get(tag);
            if (count) |c| {
                try tag_counts.put(tag, c + 1);
            } else {
                try tag_counts.put(tag, 1);
            }
        }
    }

    // Sort tags by count (descending), then alphabetically
    const TagCount = struct { []const u8, usize };
    var sorted_tags = std.ArrayListUnmanaged(TagCount){};
    defer sorted_tags.deinit(allocator);

    var tag_iter = tag_counts.iterator();
    while (tag_iter.next()) |entry| {
        try sorted_tags.append(allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    std.sort.insertion(TagCount, sorted_tags.items, {}, struct {
        fn lessThan(_: void, a: TagCount, b: TagCount) bool {
            if (a[1] != b[1]) {
                return a[1] > b[1]; // Sort by count descending
            }
            return std.mem.order(u8, a[0], b[0]) == .lt; // Then alphabetically
        }
    }.lessThan);

    // Render output
    try stdout.writeAll("Tags:\n");
    try stdout.writeAll("───────\n");

    if (sorted_tags.items.len == 0) {
        try stdout.writeAll("(no tags)\n");
        return;
    }

    for (sorted_tags.items) |item| {
        const line = try std.fmt.allocPrint(allocator, "{s:<30} ({})\n", .{ item[0], item[1] });
        defer allocator.free(line);
        try stdout.writeAll(line);
    }
}
