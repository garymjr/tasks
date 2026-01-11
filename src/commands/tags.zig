const std = @import("std");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const TagsError = error{
    NotInitialized,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip();
    _ = iter.skip();

    var no_color = false;
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            no_color = true;
        }
    }

    const options = display.resolveOptions(stdout, no_color);
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    defer writer.interface.flush() catch {};
    const out = &writer.interface;

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
    try out.writeAll("Tags:\n");
    try out.writeAll("───────\n");

    if (sorted_tags.items.len == 0) {
        try out.writeAll("(no tags)\n");
        return;
    }

    const tag_width: usize = 30;

    for (sorted_tags.items) |item| {
        try display.writeStyled(out, options, .cyan, item[0]);
        if (item[0].len < tag_width) {
            var i: usize = 0;
            while (i < tag_width - item[0].len) : (i += 1) {
                try out.writeByte(' ');
            }
        }
        try out.writeAll(" ");
        try display.writeStyledFmt(out, options, .bright_black, "({})", .{item[1]});
        try out.writeAll("\n");
    }
}
