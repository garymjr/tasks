const std = @import("std");
const model = @import("../model.zig");
const Task = model.Task;
const store = @import("../store.zig");
const display = @import("../display.zig");

const NextError = error{
    NotInitialized,
    NoReadyTasks,
} || store.StorageError || std.fs.File.WriteError;

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File) !void {
    var iter = std.process.args();
    _ = iter.skip(); // Skip executable
    _ = iter.skip(); // Skip "next"

    // Check for --all flag
    const show_all = blk: {
        const arg = iter.next();
        break :blk arg != null and std.mem.eql(u8, arg.?, "--all");
    };

    // Load existing tasks
    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    // Get ready tasks
    var ready_tasks = task_store.getReadyTasks();
    defer ready_tasks.deinit(allocator);

    if (ready_tasks.items.len == 0) {
        try stderr.writeAll("No ready tasks found.\n");
        return error.NoReadyTasks;
    }

    // Sort by priority (high to low), then by created_at
    std.sort.insertion(*Task, ready_tasks.items, {}, compareTasks);

    if (show_all) {
        try stdout.writeAll("Ready tasks:\n");
        try stdout.writeAll("─────────────\n\n");

        for (ready_tasks.items, 0..) |task, i| {
            const num_str = try std.fmt.allocPrint(allocator, "{d}. ", .{i + 1});
            defer allocator.free(num_str);
            try stdout.writeAll(num_str);
            const detail = try display.renderTaskDetail(allocator, task);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            try stdout.writeAll("\n");
        }
    } else {
        // Show just the highest priority ready task
        const task = ready_tasks.items[0];
        try stdout.writeAll("Next ready task:\n");
        try stdout.writeAll("────────────────\n\n");

        const detail = try display.renderTaskDetail(allocator, task);
        defer allocator.free(detail);
        try stdout.writeAll(detail);

        if (ready_tasks.items.len > 1) {
            const msg = try std.fmt.allocPrint(allocator, "\n{d} more ready tasks available. Use 'tasks next --all' to see all.\n", .{ready_tasks.items.len - 1});
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        }
    }
}

fn compareTasks(context: void, a: *const Task, b: *const Task) bool {
    _ = context;

    // Sort by priority (critical > high > medium > low)
    // We want higher priority first, so return true if a.priority > b.priority
    if (a.priority != b.priority) {
        return @intFromEnum(a.priority) > @intFromEnum(b.priority);
    }

    // Then by created_at (oldest first)
    return a.created_at < b.created_at;
}
