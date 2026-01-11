const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const Task = model.Task;
const store = @import("tasks-store-json");
const display = @import("tasks-render");
const json = @import("../json.zig");

const NextError = error{
    NotInitialized,
    NoReadyTasks,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "all", .long = "all", .kind = .flag, .help = "Show all ready tasks" },
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const show_all = parser.getFlag("all");
    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    var ready_tasks = task_store.getReadyTasks();
    defer ready_tasks.deinit(allocator);

    if (ready_tasks.items.len == 0) {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "No ready tasks found.");
            return error.NoReadyTasks;
        }
        try stderr.writeAll("No ready tasks found.\n");
        return error.NoReadyTasks;
    }

    std.sort.insertion(*Task, ready_tasks.items, {}, compareTasks);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"mode\":");
        if (show_all) {
            try json.writeJsonString(out, "many");
        } else {
            try json.writeJsonString(out, "one");
        }
        try out.writeAll(",\"tasks\":");
        if (show_all) {
            try json.writeTaskArray(out, ready_tasks.items);
        } else {
            const task = ready_tasks.items[0];
            try out.writeAll("[");
            try json.writeTask(out, task);
            try out.writeAll("]");
        }
        try out.writeAll("}\n");
        return;
    }

    const options = display.resolveOptions(stdout, no_color);

    if (show_all) {
        try stdout.writeAll("Ready tasks:\n");
        try stdout.writeAll("─────────────\n\n");

        for (ready_tasks.items, 0..) |task, index| {
            const num_str = try std.fmt.allocPrint(allocator, "{d}. ", .{index + 1});
            defer allocator.free(num_str);
            try stdout.writeAll(num_str);
            const detail = try display.renderTaskDetail(allocator, task, options);
            defer allocator.free(detail);
            try stdout.writeAll(detail);
            try stdout.writeAll("\n");
        }
    } else {
        const task = ready_tasks.items[0];
        try stdout.writeAll("Next ready task:\n");
        try stdout.writeAll("────────────────\n\n");

        const detail = try display.renderTaskDetail(allocator, task, options);
        defer allocator.free(detail);
        try stdout.writeAll(detail);

        if (ready_tasks.items.len > 1) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "\n{d} more ready tasks available. Use 'tasks next --all' to see all.\n",
                .{ready_tasks.items.len - 1},
            );
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        }
    }
}

fn compareTasks(context: void, a: *const Task, b: *const Task) bool {
    _ = context;

    if (a.priority != b.priority) {
        return @intFromEnum(a.priority) > @intFromEnum(b.priority);
    }

    return a.created_at < b.created_at;
}
