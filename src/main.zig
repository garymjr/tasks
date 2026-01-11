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

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const cmd = try cli.parse(argv);
    const command_argv = if (argv.len > 1) argv[1..] else argv[0..0];

    switch (cmd) {
        .help => {
            try cli.printHelp(stdout);
        },
        .init => {
            try commands.init.run(allocator, stdout, command_argv);
        },
        .add => {
            try commands.add.run(allocator, stdout, command_argv);
        },
        .list => {
            try commands.list.run(allocator, stdout, command_argv);
        },
        .show => {
            try commands.show.run(allocator, stdout, stderr, command_argv);
        },
        .delete => {
            try commands.delete.run(allocator, stdout, stderr, command_argv);
        },
        .edit => {
            try commands.edit.run(allocator, stdout, stderr, command_argv);
        },
        .done => {
            try commands.done.run(allocator, stdout, stderr, command_argv);
        },
        .block => {
            try commands.block.run(allocator, stdout, stderr, command_argv);
        },
        .unblock => {
            try commands.unblock.run(allocator, stdout, stderr, command_argv);
        },
        .link => {
            try commands.link.run(allocator, stdout, stderr, command_argv);
        },
        .unlink => {
            try commands.unlink.run(allocator, stdout, stderr, command_argv);
        },
        .next => {
            try commands.next.run(allocator, stdout, stderr, command_argv);
        },
        .graph => {
            try commands.graph.run(allocator, stdout, stderr, command_argv);
        },
        .tag => {
            try commands.tag.run(allocator, stdout, stderr, command_argv);
        },
        .untag => {
            try commands.untag.run(allocator, stdout, stderr, command_argv);
        },
        .tags => {
            try commands.tags.run(allocator, stdout, command_argv);
        },
        .search => {
            try commands.search.run(allocator, stdout, stderr, command_argv);
        },
        .stats => {
            try commands.stats.run(allocator, stdout, command_argv);
        },
    }
}
