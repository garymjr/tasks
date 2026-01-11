const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const Task = model.Task;
const store = @import("../store.zig");
const display = @import("../display.zig");

const NextError = error{
    NotInitialized,
    NoReadyTasks,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "all", .long = "all", .kind = .flag, .help = "Show all ready tasks" },
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

    const show_all = parser.getFlag("all");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var ready_tasks = task_store.getReadyTasks();
    defer ready_tasks.deinit(allocator);

    if (ready_tasks.items.len == 0) {
        try stderr.writeAll("No ready tasks found.\n");
        return error.NoReadyTasks;
    }

    const options = display.resolveOptions(stdout, no_color);

    std.sort.insertion(*Task, ready_tasks.items, {}, compareTasks);

    if (show_all) {
        try stdout.writeAll("Ready tasks:\n");
        try stdout.writeAll("─────────────\n\n");

        for (ready_tasks.items, 0..) |task, index| {
            const num_str = try std.fmt.allocPrint(allocator, "{d}. ", .{index + 1});
            defer allocator.free(num_str);
            try stdout.writeAll(num_str);
            const detail = try display.renderTaskDetail(allocator, task, options);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            try stdout.writeAll("\n");
        }
    } else {
        const task = ready_tasks.items[0];
        try stdout.writeAll("Next ready task:\n");
        try stdout.writeAll("────────────────\n\n");

        const detail = try display.renderTaskDetail(allocator, task, options);
        defer allocator.free(detail);
        try stdout.writeAll(detail);

        if (ready_tasks.items.len > 1) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "\n{d} more ready tasks available. Use 'tasks next --all' to see all.\n",
                .{ready_tasks.items.len - 1},
            );
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        }
    }
}

fn compareTasks(context: void, a: *const Task, b: *const Task) bool {
    _ = context;

    if (a.priority != b.priority) {
        return @intFromEnum(a.priority) > @intFromEnum(b.priority);
    }

    return a.created_at < b.created_at;
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
