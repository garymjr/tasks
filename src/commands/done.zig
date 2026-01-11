const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const store = @import("tasks-store-json");
const display = @import("tasks-render");
const json = @import("../json.zig");

const DoneError = error{
    NotInitialized,
    MissingId,
    InvalidId,
    TaskNotFound,
    SaveFailed,
} || store.StorageError || std.fs.File.WriteError;

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
    .{ .name = "id", .kind = .positional, .position = 0, .required = true, .help = "Task ID" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, stderr: std.fs.File, parser: *argparse.Parser) !void {
    const id_value = try parser.getRequiredPositional("id");
    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    const task = task_store.findByShortId(id_value) orelse {
        if (use_json) {
            var buffer: [256]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try json.writeError(out, "Task not found");
            return error.TaskNotFound;
        }
        try stderr.writeAll("Error: Task not found\n");
        return error.TaskNotFound;
    };

    if (task.status == .done) {
        if (use_json) {
            var buffer: [4096]u8 = undefined;
            var writer = stdout.writer(&buffer);
            defer writer.interface.flush() catch {};
            const out = &writer.interface;
            try out.writeAll("{\"already_done\":true,\"task\":");
            try json.writeTask(out, task);
            try out.writeAll("}\n");
            return;
        }

        const options = display.resolveOptions(stdout, no_color);
        try stdout.writeAll("Task is already done.\n\n");
        const detail = try display.renderTaskDetail(allocator, task, options);
        defer allocator.free(detail);
        try stdout.writeAll(detail);
        return;
    }

    task.markDone();

    try store.saveTasks(allocator, &task_store);

    if (use_json) {
        var buffer: [4096]u8 = undefined;
        var writer = stdout.writer(&buffer);
        defer writer.interface.flush() catch {};
        const out = &writer.interface;
        try out.writeAll("{\"already_done\":false,\"task\":");
        try json.writeTask(out, task);
        try out.writeAll("}\n");
        return;
    }

    const options = display.resolveOptions(stdout, no_color);

    try stdout.writeAll("Marked task as done:\n\n");
    const detail = try display.renderTaskDetail(allocator, task, options);
    defer allocator.free(detail);
    try stdout.writeAll(detail);
}
