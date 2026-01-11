const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const ShowError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
    LoadFailed,
} || store.StorageError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_value = try parser.getRequiredPositional("id");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = blk: {
        if (task_store.findByIdString(id_value) catch null) |task_value| {
            break :blk task_value;
        }
        if (task_store.findByShortId(id_value)) |task_value| {
            break :blk task_value;
        }
        break :blk null;
    } orelse {
        const msg = try std.fmt.allocPrint(allocator, "Error: Task not found: {s}\n", .{id_value});
        defer allocator.free(msg);
        try stderr.writeAll(msg);
        return error.TaskNotFound;
    };

    const options = display.resolveOptions(stdout, no_color);

    const output = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(output);
    try stdout.writeAll(output);
}


