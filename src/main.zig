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
        .tag => {
            try commands.tag.run(allocator, stdout, stderr);
        },
        .untag => {
            try commands.untag.run(allocator, stdout, stderr);
        },
        .tags => {
            try commands.tags.run(allocator, stdout);
        },
        .search => {
            try commands.search.run(allocator, stdout, stderr);
        },
        .stats => {
            try commands.stats.run(allocator, stdout);
        },
    }
}
