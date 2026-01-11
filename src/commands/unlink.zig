const std = @import("std");
const argparse = @import("argparse");
const model = @import("../model.zig");
const store = @import("../store.zig");
const display = @import("../display.zig");
const json = @import("../json.zig");

const UnlinkError = error{
    NotInitialized,
    MissingIds,
    InvalidId,
    TaskNotFound,
    DependencyNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "child", .kind = .positional, .position = 0, .required = true, .help = "Child task ID" },
    .{ .name = "parent", .kind = .positional, .position = 1, .required = true, .help = "Parent task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const child_id_value = try parser.getRequiredPositional("child");
    const parent_id_value = try parser.getRequiredPositional("parent");
    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const child = task_store.findByShortId(child_id_value) orelse {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "Child task not found");
            return error.TaskNotFound;
        }
        try stderr.writeAll("Error: Child task not found\n");
        return error.TaskNotFound;
    };

    const parent = task_store.findByShortId(parent_id_value) orelse {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "Parent task not found");
            return error.TaskNotFound;
        }
        try stderr.writeAll("Error: Parent task not found\n");
        return error.TaskNotFound;
    };

    const parent_id_str_full = model.formatUuid(parent.id);
    var found_index: ?usize = null;

    for (child.dependencies.items, 0..) |dep, index| {
        const dep_id = model.formatUuid(model.parseUuid(dep[0..36]) catch unreachable);
        if (std.mem.eql(u8, &dep_id, &parent_id_str_full)) {
            found_index = index;
            break;
        }
    }

    if (found_index) |index| {
        allocator.free(child.dependencies.items[index]);
        _ = child.dependencies.orderedRemove(index);
    } else {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "Dependency not found");
            return error.DependencyNotFound;
        }
        try stderr.writeAll("Error: Dependency not found\n");
        return error.DependencyNotFound;
    }

    child.updateTimestamp();

    try task_store.updateBlockedBy();

    try store.saveTasks(allocator, &task_store);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"was_linked\":true,\"child\":");
        try json.writeTask(out, child);
        try out.writeAll(",\"parent\":");
        try json.writeTask(out, parent);
        try out.writeAll("}\n");
        return;
    }

    const options = display.resolveOptions(stdout, no_color);

    const msg = try std.fmt.allocPrint(allocator, "Removed dependency:\n  {s} → {s}\n\n", .{ child_id_value, parent_id_value });
    defer allocator.free(msg);
    try stdout.writeAll(msg);

    const detail = try display.renderTaskDetail(allocator, child, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
