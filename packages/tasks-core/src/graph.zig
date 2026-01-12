const std = @import("std");
const model = @import("model.zig");
const Task = model.Task;
const TaskStore = model.TaskStore;
const parseUuid = model.parseUuid;
const formatUuid = model.formatUuid;

pub const GraphError = error{
    TaskNotFound,
    CycleDetected,
    InvalidId,
};

/// Render a dependency tree starting from the given task ID
pub fn renderTree(allocator: std.mem.Allocator, store: *TaskStore, task_id: model.Uuid) ![]const u8 {
    const task = store.findByUuid(task_id) orelse return error.TaskNotFound;

    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    try writer.writeAll("Dependency Tree:\n");
    try writeTreeNode(writer, allocator, store, task, "", true);

    return buffer.toOwnedSlice(allocator);
}

fn writeTreeNode(writer: anytype, allocator: std.mem.Allocator, store: *TaskStore, task: *const Task, prefix: []const u8, is_last: bool) !void {
    const connector = if (is_last) "└── " else "├── ";
    const id_str = formatUuid(task.id)[0..8];

    try writer.print("{s}{s}{s} [{s}] {s}\n", .{
        prefix,
        connector,
        id_str,
        statusSymbol(task.status),
        task.title,
    });

    if (task.dependencies.items.len > 0) {
        const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
            prefix,
            if (is_last) "    " else "│   ",
        });
        defer allocator.free(new_prefix);

        for (task.dependencies.items, 0..) |dep_str, i| {
            if (dep_str.len < 36) continue;
            const dep_id = parseUuid(dep_str[0..36]) catch continue;
            const dep = store.findByUuid(dep_id) orelse {
                const dep_id_short = dep_str[0..8];
                try writer.print("{s}{s}{s} (not found)\n", .{
                    new_prefix,
                    if (i == task.dependencies.items.len - 1) "└── " else "├── ",
                    dep_id_short,
                });
                continue;
            };

            const last = i == task.dependencies.items.len - 1;
            try writeTreeNode(writer, allocator, store, dep, new_prefix, last);
        }
    }
}

/// Render the reverse dependency tree (tasks blocked by this task)
pub fn renderReverseTree(allocator: std.mem.Allocator, store: *TaskStore, task_id: model.Uuid) ![]const u8 {
    const task = store.findByUuid(task_id) orelse return error.TaskNotFound;

    var buffer = std.ArrayListUnmanaged(u8){};
    const writer = buffer.writer(allocator);

    try writer.writeAll("Blocks:\n");
    try writeReverseTreeNode(writer, allocator, store, task, "", true);

    return buffer.toOwnedSlice(allocator);
}

fn writeReverseTreeNode(writer: anytype, allocator: std.mem.Allocator, store: *TaskStore, task: *const Task, prefix: []const u8, is_last: bool) !void {
    const id_str = formatUuid(task.id)[0..8];

    try writer.print("{s}{s}{s} [{s}] {s}\n", .{
        prefix,
        if (is_last) "└── " else "├── ",
        id_str,
        statusSymbol(task.status),
        task.title,
    });

    if (task.blocked_by.items.len > 0) {
        const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
            prefix,
            if (is_last) "    " else "│   ",
        });
        defer allocator.free(new_prefix);

        for (task.blocked_by.items, 0..) |blocked_str, i| {
            if (blocked_str.len < 36) continue;
            const blocked_id = parseUuid(blocked_str[0..36]) catch continue;
            const blocked_task = store.findByUuid(blocked_id) orelse {
                const blocked_id_short = blocked_str[0..8];
                try writer.print("{s}{s}{s} (not found)\n", .{
                    new_prefix,
                    if (i == task.blocked_by.items.len - 1) "└── " else "├── ",
                    blocked_id_short,
                });
                continue;
            };

            const last = i == task.blocked_by.items.len - 1;
            try writeReverseTreeNode(writer, allocator, store, blocked_task, new_prefix, last);
        }
    }
}

pub fn statusSymbol(status: model.Status) []const u8 {
    return switch (status) {
        .todo => "○",
        .in_progress => "◉",
        .done => "✓",
        .blocked => "⊗",
    };
}
