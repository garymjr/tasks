const std = @import("std");
const argparse = @import("argparse");
const commands = @import("commands/mod.zig");

const Context = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File,
    stderr: std.fs.File,
};

var context: ?Context = null;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const command = buildCommand();

    if (argv.len == 1) {
        const help = try command.helpText(allocator);
        defer allocator.free(help);
        try stdout.writeAll(help);
        return;
    }

    if (argv.len > 1 and std.mem.eql(u8, argv[1], "help")) {
        try printHelpFor(allocator, stdout, command, argv);
        return;
    }

    context = .{ .allocator = allocator, .stdout = stdout, .stderr = stderr };
    defer context = null;

    command.run(allocator, argv) catch |err| {
        switch (err) {
            argparse.Error.ShowHelp => {
                const help = try command.helpFor(allocator, argv);
                defer allocator.free(help);
                try stdout.writeAll(help);
                return;
            },
            argparse.Error.UnknownCommand,
            argparse.Error.UnknownArgument,
            argparse.Error.MissingValue,
            argparse.Error.MissingRequired,
            argparse.Error.InvalidValue,
            argparse.Error.DuplicateArgument,
            => {
                const parse_err: argparse.Error = @errorCast(err);
                const message = try command.formatError(allocator, parse_err, argv, .{ .color = .auto });
                defer allocator.free(message);
                try stderr.writeAll(message);
                try stderr.writeAll("\n");
                return err;
            },
            else => return err,
        }
    };
}

fn printHelpFor(allocator: std.mem.Allocator, stdout: std.fs.File, command: argparse.Command, argv: []const []const u8) !void {
    if (argv.len <= 2) {
        const help = try command.helpText(allocator);
        defer allocator.free(help);
        try stdout.writeAll(help);
        return;
    }

    const help_argv_len = argv.len - 1;
    var help_argv = try allocator.alloc([]const u8, help_argv_len);
    defer allocator.free(help_argv);

    help_argv[0] = argv[0];
    std.mem.copyForwards([]const u8, help_argv[1..], argv[2..]);

    const help = try command.helpFor(allocator, help_argv);
    defer allocator.free(help);
    try stdout.writeAll(help);
}

fn buildCommand() argparse.Command {
    return .{
        .name = "tasks",
        .help = "Task management",
        .subcommands = &[_]argparse.Command{
            .{ .name = "init", .help = "Initialize in current directory", .args = commands.init.args[0..], .handler = handleInit },
            .{ .name = "add", .help = "Add a new task", .args = commands.add.args[0..], .handler = handleAdd },
            .{ .name = "list", .help = "List all tasks", .args = commands.list.args[0..], .handler = handleList },
            .{ .name = "show", .help = "Show task details", .args = commands.show.args[0..], .handler = handleShow },
            .{ .name = "edit", .help = "Edit a task", .args = commands.edit.args[0..], .handler = handleEdit },
            .{ .name = "delete", .help = "Delete a task", .args = commands.delete.args[0..], .handler = handleDelete },
            .{ .name = "done", .help = "Mark task as done", .args = commands.done.args[0..], .handler = handleDone },
            .{ .name = "block", .help = "Mark task as blocked", .args = commands.block.args[0..], .handler = handleBlock },
            .{ .name = "unblock", .help = "Unblock task", .args = commands.unblock.args[0..], .handler = handleUnblock },
            .{ .name = "link", .help = "Add dependency", .args = commands.link.args[0..], .handler = handleLink },
            .{ .name = "unlink", .help = "Remove dependency", .args = commands.unlink.args[0..], .handler = handleUnlink },
            .{ .name = "graph", .help = "Show dependency tree", .args = commands.graph.args[0..], .handler = handleGraph },
            .{ .name = "tag", .help = "Add tag", .args = commands.tag.args[0..], .handler = handleTag },
            .{ .name = "untag", .help = "Remove tag", .args = commands.untag.args[0..], .handler = handleUntag },
            .{ .name = "tags", .help = "List all tags", .args = commands.tags.args[0..], .handler = handleTags },
            .{ .name = "search", .help = "Search tasks", .args = commands.search.args[0..], .handler = handleSearch },
            .{ .name = "next", .help = "Show next ready task", .args = commands.next.args[0..], .handler = handleNext },
            .{ .name = "stats", .help = "Show statistics", .args = commands.stats.args[0..], .handler = handleStats },
        },
    };
}

fn handleInit(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.init.run(ctx.allocator, ctx.stdout, parser);
}

fn handleAdd(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.add.run(ctx.allocator, ctx.stdout, parser);
}

fn handleList(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.list.run(ctx.allocator, ctx.stdout, parser);
}

fn handleShow(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.show.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleEdit(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.edit.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleDelete(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.delete.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleDone(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.done.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleBlock(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.block.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleUnblock(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.unblock.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleLink(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.link.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleUnlink(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.unlink.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleGraph(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.graph.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleTag(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.tag.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleUntag(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.untag.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleTags(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.tags.run(ctx.allocator, ctx.stdout, parser);
}

fn handleSearch(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.search.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleNext(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.next.run(ctx.allocator, ctx.stdout, ctx.stderr, parser);
}

fn handleStats(parser: *argparse.Parser, argv: []const []const u8) anyerror!void {
    _ = argv;
    const ctx = context.?;
    try commands.stats.run(ctx.allocator, ctx.stdout, parser);
}

test "help text lists commands" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const command = buildCommand();
    const help = try command.helpText(allocator);
    defer allocator.free(help);

    try testing.expect(std.mem.indexOf(u8, help, "add") != null);
    try testing.expect(std.mem.indexOf(u8, help, "list") != null);
}
