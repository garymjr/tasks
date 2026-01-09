const std = @import("std");

pub const Command = enum {
    add,
    list,
    show,
    help,
};

pub fn parse() !Command {
    var iter = std.process.args();
    _ = iter.skip();

    const cmd_str = iter.next() orelse {
        return .help;
    };

    return std.meta.stringToEnum(Command, cmd_str) orelse {
        return error.UnknownCommand;
    };
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Tasks CLI - Task management
        \\
        \\Commands: add, list, show, help
        \\
    );
}

test "parse help" {
    try std.testing.expectEqual(Command.help, parse());
}

test "parse list" {
    try std.testing.expectEqual(Command.list, parse());
}

test "parse invalid" {
    try std.testing.expectError(error.UnknownCommand, parseWithArgs(&[_][]const u8{"tasks", "invalid"}));
}

fn parseWithArgs(argv: []const []const u8) !Command {
    if (argv.len < 2) return .help;
    return std.meta.stringToEnum(Command, argv[1]) orelse {
        return error.UnknownCommand;
    };
}
