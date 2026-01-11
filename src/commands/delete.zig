const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const DeleteError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
    HasDependents,
    SaveFailed,
} || store.StorageError;

pub const args = [_]argparse.Arg{
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    var parser = try argparse.Parser.init(allocator, args[0..]);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

    const id_str = try parser.getRequiredPositional("id");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = blk: {
        if (task_store.findByIdString(id_str) catch null) |task_value| {
            break :blk task_value;
        }
        if (task_store.findByShortId(id_str)) |task_value| {
            break :blk task_value;
        }
        break :blk null;
    } orelse {
        const msg = try std.fmt.allocPrint(allocator, "Error: Task not found: {s}\n", .{id_str});
        defer allocator.free(msg);
        try stderr.writeAll(msg);
        return error.TaskNotFound;
    };

    const id_full = model.formatUuid(task.id);
    for (task_store.tasks.items) |task_item| {
        for (task_item.dependencies.items) |dep| {
            if (std.mem.eql(u8, dep, &id_full)) {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Error: Cannot delete task - other tasks depend on it.\n" ++
                        "Run 'tasks graph {s}' to see dependents.\n",
                    .{id_str[0..8]},
                );
                defer allocator.free(msg);
                try stderr.writeAll(msg);
                return error.HasDependents;
            }
        }
    }

    const id = task.id;
    try task_store.removeByUuid(id);

    try store.saveTasks(allocator, &task_store);

    const msg = try std.fmt.allocPrint(allocator, "Deleted task: {s}\n", .{id_str});
    defer allocator.free(msg);
    try stdout.writeAll(msg);
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

test "delete removes task" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    const task = try task_store.create("To delete");
    const id = task.id;

    try task_store.removeByUuid(id);
    try testing.expect(task_store.findByUuid(id) == null);
}
