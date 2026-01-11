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

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
        .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

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

test "show requires id" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stdout_buf = std.ArrayList(u8).init(allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(allocator);
    defer stderr_buf.deinit();

    const stdout_file: std.fs.File = .{ .handle = .{ .writer = stdout_buf.writer() } };
    const stderr_file: std.fs.File = .{ .handle = .{ .writer = stderr_buf.writer() } };

    const argv = &[_][]const u8{"show"};
    const result = run(allocator, stdout_file, stderr_file, argv);
    try testing.expectError(argparse.Error.MissingRequired, result);
}
