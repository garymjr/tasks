const std = @import("std");
const argparse = @import("argparse");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const GraphError = error{
    NotInitialized,
    MissingId,
    TaskNotFound,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "reverse", .long = "reverse", .kind = .flag, .help = "Show blocked tasks tree" },
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
    const show_reverse = parser.getFlag("reverse");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = task_store.findByShortId(id_value) orelse {
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    if (show_reverse) {
        const tree = try graph.renderReverseTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    } else {
        const tree = try graph.renderTree(allocator, &task_store, task.id);
        defer allocator.free(tree);
        try stdout.writeAll(tree);
    }

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("\nTask Details:\n");
    try stdout.writeAll("─────────────\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);

    if (task_store.hasCycle(task.id)) {
        try stdout.writeAll("\n⚠️  Warning: Cycle detected in dependency tree!\n");
    }
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
