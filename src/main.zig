const std = @import("std");
const cli = @import("cli.zig");
const store = @import("store.zig");
const commands = @import("commands/mod.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    const cmd = try cli.parse();

    switch (cmd) {
        .help => {
            try cli.printHelp(stdout);
        },
        .init => {
            try commands.init.run(allocator, stdout);
        },
        .add => {
            try commands.add.run(allocator, stdout);
        },
        .list => {
            try commands.list.run(allocator, stdout);
        },
        .show => {
            try commands.show.run(allocator, stdout, stderr);
        },
        .delete => {
            try commands.delete.run(allocator, stdout, stderr);
        },
        .edit => {
            try commands.edit.run(allocator, stdout, stderr);
        },
        .done => {
            try commands.done.run(allocator, stdout, stderr);
        },
        .block => {
            try commands.block.run(allocator, stdout, stderr);
        },
        .unblock => {
            try commands.unblock.run(allocator, stdout, stderr);
        },
        .link => {
            try commands.link.run(allocator, stdout, stderr);
        },
        .unlink => {
            try commands.unlink.run(allocator, stdout, stderr);
        },
        .next => {
            try commands.next.run(allocator, stdout, stderr);
        },
        .graph => {
            try commands.graph.run(allocator, stdout, stderr);
        },
        else => {
            if (!store.exists()) {
                try stderr.writeAll("Error: Not initialized. Run 'tasks init' first.\n");
                return error.NotInitialized;
            }

            var task_store = try store.loadTasks(allocator);
            defer task_store.deinit();

            const msg = try std.fmt.allocPrint(allocator, "Command not yet implemented: {s}\n", .{@tagName(cmd)});
            defer allocator.free(msg);
            try stdout.writeAll(msg);
        },
    }
}
