const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("tasks-store-json");
const display = @import("tasks-render");
const json = @import("../json.zig");

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
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, parser: *argparse.Parser) !void {
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
    const use_json = parser.getFlag("json");

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

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"tasks\":");
        try json.writeTaskArray(out, filtered.items);
        try out.writeAll("}\n");
        return;
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
