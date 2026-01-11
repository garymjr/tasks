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

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
    .{ .name = "tag", .kind = .positional, .position = 1, .required = true, .help = "Tag" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
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

