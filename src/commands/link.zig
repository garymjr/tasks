const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const graph = @import("../graph.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");

const LinkError = error{
    NotInitialized,
    MissingIds,
    InvalidId,
    TaskNotFound,
    CycleDetected,
    SelfDependency,
    AlreadyDependent,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, argv: []const []const u8) !void {
    const args = [_]argparse.Arg{
        .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
        .{ .name = "child", .kind = .positional, .position = 0, .required = true, .help = "Child task ID" },
        .{ .name = "parent", .kind = .positional, .position = 1, .required = true, .help = "Parent task ID" },
    };

    var parser = try argparse.Parser.init(allocator, &args);
    defer parser.deinit();

    parser.parse(argv) catch |err| {
        const showed_help = try writeParseError(allocator, &parser, stdout, stderr, err);
        if (showed_help) return;
        return err;
    };

    const child_id_value = try parser.getRequiredPositional("child");
    const parent_id_value = try parser.getRequiredPositional("parent");
    const no_color = parser.getFlag("no-color");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const child = task_store.findByShortId(child_id_value) orelse {
        try stderr.writeAll("Error: Child task not found\n");
        return error.TaskNotFound;
    };

    const parent = task_store.findByShortId(parent_id_value) orelse {
        try stderr.writeAll("Error: Parent task not found\n");
        return error.TaskNotFound;
    };

    const options = display.resolveOptions(stdout, no_color);

    const child_id_str_full = model.formatUuid(child.id);
    const parent_id_str_full = model.formatUuid(parent.id);
    if (std.mem.eql(u8, &child_id_str_full, &parent_id_str_full)) {
        try stderr.writeAll("Error: Task cannot depend on itself\n");
        return error.SelfDependency;
    }

    for (child.dependencies.items) |dep| {
        const dep_id = model.formatUuid(model.parseUuid(dep[0..36]) catch unreachable);
        if (std.mem.eql(u8, &dep_id, &parent_id_str_full)) {
            try stdout.writeAll("Dependency already exists.\n\n");
            const detail = try display.renderTaskDetail(allocator, child, options);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            return;
        }
    }

    try child.dependencies.append(allocator, try allocator.dupe(u8, &parent_id_str_full));
    const has_cycle = task_store.hasCycle(child.id);
    const idx = child.dependencies.items.len - 1;
    const test_dep = child.dependencies.orderedRemove(idx);
    allocator.free(test_dep);

    if (has_cycle) {
        try stderr.writeAll("Error: Adding this dependency would create a cycle\n");
        return error.CycleDetected;
    }

    try child.dependencies.append(allocator, try allocator.dupe(u8, &parent_id_str_full));
    child.updateTimestamp();

    try task_store.updateBlockedBy();

    try store.saveTasks(allocator, &task_store);

    const msg = try std.fmt.allocPrint(allocator, "Added dependency:\n  {s} → {s}\n\n", .{ child_id_value, parent_id_value });
    defer allocator.free(msg);
    try stdout.writeAll(msg);

    try stdout.writeAll("Child task:\n");
    const child_detail = try display.renderTaskDetail(allocator, child, options);
    defer allocator.free(child_detail);
    try stdout.writeAll(child_detail);

    try stdout.writeAll("\nParent task:\n");
    const parent_detail = try display.renderTaskDetail(allocator, parent, options);
    defer allocator.free(parent_detail);
    try stdout.writeAll(parent_detail);
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
