const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const TagsError = error{
    NotInitialized,
    LoadFailed,
} || store.StorageError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, err);
        if (showed_help) return;
        return err;
    };

    const no_color = parser.getFlag("no-color");

    const options = display.resolveOptions(stdout, no_color);
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    defer writer.interface.flush() catch {};
    const out = &writer.interface;

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var tag_counts = std.StringHashMap(usize).init(allocator);
    defer tag_counts.deinit();

    for (task_store.tasks.items) |task| {
        for (task.tags.items) |tag| {
            const count = tag_counts.get(tag);
            if (count) |count_value| {
                try tag_counts.put(tag, count_value + 1);
            } else {
                try tag_counts.put(tag, 1);
            }
        }
    }

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
                return a[1] > b[1];
            }
            return std.mem.order(u8, a[0], b[0]) == .lt;
        }
    }.lessThan);

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
            var index: usize = 0;
            while (index < tag_width - item[0].len) : (index += 1) {
                try out.writeByte(' ');
            }
        }
        try out.writeAll(" ");
        try display.writeStyledFmt(out, options, .bright_black, "({})", .{item[1]});
        try out.writeAll("\n");
    }
}

fn writeParseError(allocator: std.mem.Allocator, parser: *argparse.Parser, stdout: std.fs.File, err: anyerror) !bool {
    switch (err) {
        argparse.Error.ShowHelp => {
            const help = try parser.help();
            defer allocator.free(help);
            try stdout.writeAll(help);
            return true;
        },
        else => {
            const parse_err: argparse.Error = @errorCast(err);
            const message = try parser.formatError(allocator, parse_err, .{ .color = .auto });
            defer allocator.free(message);
            try stdout.writeAll(message);
            try stdout.writeAll("\n");
            return false;
        },
    }
}
