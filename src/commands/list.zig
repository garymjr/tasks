const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const ListError = error{
    NotInitialized,
    InvalidStatus,
    InvalidPriority,
    LoadFailed,
} || store.StorageError;

pub const args = [_]argparse.Arg{
    .{ .name = "status", .long = "status", .kind = .option, .help = "Filter by status", .validator = validateStatus },
    .{ .name = "priority", .long = "priority", .kind = .option, .help = "Filter by priority", .validator = validatePriority },
    .{ .name = "tags", .long = "tags", .kind = .option, .help = "Filter by tag" },
    .{ .name = "blocked", .long = "blocked", .kind = .flag, .help = "Only blocked tasks" },
    .{ .name = "unblocked", .long = "unblocked", .kind = .flag, .help = "Only unblocked tasks" },
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, argv: []const []const u8) !void {
    var parser = try argparse.Parser.init(allocator, args[0..]);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, err);
        if (showed_help) return;
        return err;
    };

    var status_filter: ?model.Status = null;
    if (parser.getOption("status")) |status_str| {
        status_filter = try parseStatus(status_str);
    }

    var priority_filter: ?model.Priority = null;
    if (parser.getOption("priority")) |priority_str| {
        priority_filter = try parsePriority(priority_str);
    }

    const tag_filter = parser.getOption("tags");
    const blocked_only = parser.getFlag("blocked");
    const unblocked_only = parser.getFlag("unblocked");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var filtered = std.ArrayListUnmanaged(*model.Task){};
    defer filtered.deinit(allocator);

    for (task_store.tasks.items) |task| {
        if (status_filter) |status| {
            if (task.status != status) continue;
        }

        if (priority_filter) |priority| {
            if (task.priority != priority) continue;
        }

        if (tag_filter) |tag| {
            var has_tag = false;
            for (task.tags.items) |task_tag| {
                if (std.mem.eql(u8, task_tag, tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (!has_tag) continue;
        }

        if (blocked_only) {
            if (task_store.isReady(task.*)) continue;
        }

        if (unblocked_only) {
            if (!task_store.isReady(task.*)) continue;
        }

        try filtered.append(allocator, task);
    }

    const options = display.resolveOptions(stdout, no_color);
    const output = try display.renderTaskTable(allocator, filtered.items, options);
    defer allocator.free(output);
    try stdout.writeAll(output);
}

fn parseStatus(value: []const u8) !model.Status {
    return std.meta.stringToEnum(model.Status, value) orelse argparse.Error.InvalidValue;
}

fn parsePriority(value: []const u8) !model.Priority {
    return std.meta.stringToEnum(model.Priority, value) orelse argparse.Error.InvalidValue;
}

fn validateStatus(value: []const u8) anyerror!void {
    _ = try parseStatus(value);
}

fn validatePriority(value: []const u8) anyerror!void {
    _ = try parsePriority(value);
}

fn writeParseError(allocator: std.mem.Allocator, parser: *argparse.Parser, stdout: std.fs.File, err: anyerror) !bool {
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
            try stdout.writeAll(message);
            try stdout.writeAll("\n");
            return false;
        },
    }
}

test "list filters by status" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var task_store = model.TaskStore.init(allocator);
    defer task_store.deinit();

    _ = try task_store.create("Task 1");
    const task2 = try task_store.create("Task 2");
    task2.setStatus(.in_progress);

    var filtered = task_store.filterByStatus(.in_progress);
    defer filtered.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), filtered.items.len);
}
