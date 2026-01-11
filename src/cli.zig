const std = @import("std");

pub const Command = enum {
    add,
    list,
    show,
    edit,
    delete,
    done,
    block,
    unblock,
    link,
    unlink,
    tag,
    untag,
    tags,
    search,
    next,
    graph,
    stats,
    help,
    init,
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

pub fn printHelp(stdout: std.fs.File) !void {
    try stdout.writeAll(
        \\Tasks CLI - Task management
        \\
        \\Global Flags:
        \\  --no-color            Disable ANSI colors
        \\
        \\Core Commands:
        \\  init                    Initialize in current directory
        \\  add "TITLE"             Add a new task
        \\  list                    List all tasks
        \\  show <ID>               Show task details
        \\  edit <ID>               Edit a task
        \\  delete <ID>             Delete a task
        \\  done <ID>               Mark task as done
        \\
        \\Status:
        \\  block <ID>              Mark task as blocked
        \\  unblock <ID>            Unblock task (reset to todo)
        \\  next                    Show next ready task
        \\  next --all              Show all ready tasks
        \\
        \\Dependencies:
        \\  link <CHILD> <PARENT>   Add dependency
        \\  unlink <CHILD> <PARENT> Remove dependency
        \\  graph <ID>              Show dependency tree
        \\  graph <ID> --reverse    Show blocked tasks tree
        \\
        \\Tags:
        \\  tag <ID> <TAG>          Add tag
        \\  untag <ID> <TAG>        Remove tag
        \\  tags                    List all tags
        \\
        \\Other:
        \\  search QUERY            Search tasks
        \\  stats                   Show statistics
        \\  help                    Show this help
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
