const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const UntagError = error{
    NotInitialized,
    MissingId,
    MissingTag,
    InvalidId,
    TaskNotFound,
    TagNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
        .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
        .{ .name = "tag", .kind = .positional, .position = 1, .required = true, .help = "Tag" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

    const id_value = try parser.getRequiredPositional("id");
    const tag_value = try parser.getRequiredPositional("tag");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = task_store.findByShortId(id_value) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    var found = false;
    for (task.tags.items, 0..) |tag_item, index| {
        if (std.mem.eql(u8, tag_item, tag_value)) {
            allocator.free(tag_item);
            _ = task.tags.orderedRemove(index);
            found = true;
            break;
        }
    }

    if (!found) {
        try stderr.writeAll("Error: Tag not found on this task\n");
        return error.TagNotFound;
    }

    task.updateTimestamp();

    try store.saveTasks(allocator, &task_store);

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("Removed tag:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}

fn writeParseError(
    allocator: std.mem.Allocator,
    parser: *argparse.Parser,
    stdout: std.fs.File,
    stderr: std.fs.File,
    err: anyerror,
) !bool {
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
            try stderr.writeAll(message);
            try stderr.writeAll("\n");
            return false;
        },
    }
}
