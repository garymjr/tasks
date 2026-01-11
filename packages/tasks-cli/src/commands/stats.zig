const std = @import("std");
const argparse = @import("argparse");
const model = @import("tasks-core").model;
const TaskStore = model.TaskStore;
const Status = model.Status;
const Priority = model.Priority;
const display = @import("tasks-render");
const json = @import("../json.zig");

const Stats = struct {
    total: usize = 0,
    by_status: [std.enums.directEnumArrayLen(Status, 0)]usize = [_]usize{0} ** 4,
    by_priority: [std.enums.directEnumArrayLen(Priority, 0)]usize = [_]usize{0} ** 4,
    completed_this_week: usize = 0,
    created_this_week: usize = 0,
    total_tags: usize = 0,
    unique_tags: std.StringHashMap(usize),
    blocked_tasks: usize = 0,

    fn init(allocator: std.mem.Allocator) Stats {
        return Stats{
            .unique_tags = std.StringHashMap(usize).init(allocator),
        };
    }

    fn deinit(self: *Stats) void {
        var it = self.unique_tags.iterator();
        while (it.next()) |entry| {
            self.unique_tags.allocator.free(entry.key_ptr.*);
        }
        self.unique_tags.deinit();
    }
};

pub const args = [_]argparse.Arg{
    .{ .name = "no-color", .long = "no-color", .kind = .flag, .help = "Disable ANSI colors" },
    .{ .name = "json", .long = "json", .kind = .flag, .help = "Output JSON" },
};

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File, parser: *argparse.Parser) !void {
    const store = @import("tasks-store-json");

    const no_color = parser.getFlag("no-color");
    const use_json = parser.getFlag("json");

    const options = display.resolveOptions(stdout, no_color);

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    if (task_store.tasks.items.len == 0) {
        if (use_json) {
            try stdout.writeAll("{\"total\":0,\"by_status\":{\"todo\":0,\"in_progress\":0,\"done\":0,\"blocked\":0},\"by_priority\":{\"low\":0,\"medium\":0,\"high\":0,\"critical\":0},\"completed_this_week\":0,\"created_this_week\":0,\"total_tags\":0,\"unique_tags\":0,\"blocked_tasks\":0,\"completion_rate\":0,\"top_tags\":[]}\n");
            return;
        }
        try stdout.writeAll("No tasks found. Add a task with 'tasks add \"Title\"'.\n");
        return;
    }

    var stats = Stats.init(allocator);
    defer stats.deinit();

    const now = std.time.timestamp();
    const one_week_ago = now - (7 * 86400);

    for (task_store.tasks.items) |task| {
        stats.total += 1;
        stats.by_status[@intFromEnum(task.status)] += 1;
        stats.by_priority[@intFromEnum(task.priority)] += 1;

        stats.total_tags += task.tags.items.len;
        for (task.tags.items) |tag| {
            const gop = try stats.unique_tags.getOrPut(tag);
            if (!gop.found_existing) {
                gop.key_ptr.* = try allocator.dupe(u8, tag);
                gop.value_ptr.* = 0;
            }
            gop.value_ptr.* += 1;
        }

        if (task.status == .blocked or task.blocked_by.items.len > 0) {
            stats.blocked_tasks += 1;
        }

        if (task.completed_at) |completed| {
            if (completed > one_week_ago) {
                stats.completed_this_week += 1;
            }
        }
        if (task.created_at > one_week_ago) {
            stats.created_this_week += 1;
        }
    }

    const completion_rate: f64 = if (stats.total > 0)
        @as(f64, @floatFromInt(stats.by_status[@intFromEnum(Status.done)])) / @as(f64, @floatFromInt(stats.total)) * 100.0
    else
        0.0;

    if (use_json) {
        try writeStatsJson(stdout, &stats, completion_rate);
        return;
    }

    try renderStats(stdout, &stats, completion_rate, options);
}

fn writeStatsJson(stdout: std.fs.File, stats: *const Stats, completion_rate: f64) !void {
    var buffer: [8192]u8 = undefined;
    var writer = stdout.writer(&buffer);
    defer writer.interface.flush() catch {};
    const out = &writer.interface;

    const TagEntry = struct { tag: []const u8, count: usize };
    var tag_entries = try std.ArrayList(TagEntry).initCapacity(stats.unique_tags.allocator, stats.unique_tags.count());
    defer tag_entries.deinit(stats.unique_tags.allocator);

    var it = stats.unique_tags.iterator();
    while (it.next()) |entry| {
        try tag_entries.append(stats.unique_tags.allocator, .{ .tag = entry.key_ptr.*, .count = entry.value_ptr.* });
    }

    std.sort.insertion(TagEntry, tag_entries.items, {}, struct {
        fn lessThan(_: void, a: TagEntry, b: TagEntry) bool {
            return a.count > b.count;
        }
    }.lessThan);

    try out.writeAll("{\"total\":");
    try out.print("{}", .{stats.total});
    try out.writeAll(",\"by_status\":{\"todo\":");
    try out.print("{}", .{stats.by_status[@intFromEnum(Status.todo)]});
    try out.writeAll(",\"in_progress\":");
    try out.print("{}", .{stats.by_status[@intFromEnum(Status.in_progress)]});
    try out.writeAll(",\"done\":");
    try out.print("{}", .{stats.by_status[@intFromEnum(Status.done)]});
    try out.writeAll(",\"blocked\":");
    try out.print("{}", .{stats.by_status[@intFromEnum(Status.blocked)]});
    try out.writeAll("},\"by_priority\":{\"low\":");
    try out.print("{}", .{stats.by_priority[@intFromEnum(Priority.low)]});
    try out.writeAll(",\"medium\":");
    try out.print("{}", .{stats.by_priority[@intFromEnum(Priority.medium)]});
    try out.writeAll(",\"high\":");
    try out.print("{}", .{stats.by_priority[@intFromEnum(Priority.high)]});
    try out.writeAll(",\"critical\":");
    try out.print("{}", .{stats.by_priority[@intFromEnum(Priority.critical)]});
    try out.writeAll("},\"completed_this_week\":");
    try out.print("{}", .{stats.completed_this_week});
    try out.writeAll(",\"created_this_week\":");
    try out.print("{}", .{stats.created_this_week});
    try out.writeAll(",\"total_tags\":");
    try out.print("{}", .{stats.total_tags});
    try out.writeAll(",\"unique_tags\":");
    try out.print("{}", .{stats.unique_tags.count()});
    try out.writeAll(",\"blocked_tasks\":");
    try out.print("{}", .{stats.blocked_tasks});
    try out.writeAll(",\"completion_rate\":");
    try out.print("{d:.1}", .{completion_rate});
    try out.writeAll(",\"top_tags\":[");

    const max_tags = @min(10, tag_entries.items.len);
    for (tag_entries.items[0..max_tags], 0..) |entry, index| {
        if (index > 0) try out.writeAll(",");
        try out.writeAll("{\"name\":");
        try json.writeJsonString(out, entry.tag);
        try out.writeAll(",\"count\":");
        try out.print("{}", .{entry.count});
        try out.writeAll("}");
    }

    try out.writeAll("]}\n");
}

fn renderStats(stdout: std.fs.File, stats: *const Stats, completion_rate: f64, options: display.RenderOptions) !void {
    const allocator = stats.unique_tags.allocator;
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    defer writer.interface.flush() catch {};
    const out = &writer.interface;

    const TagEntry = struct { tag: []const u8, count: usize };

    try out.writeAll("┌─────────────────────────────────────────────────────────────┐\n");
    try out.writeAll("│                         Task Statistics                     │\n");
    try out.writeAll("└─────────────────────────────────────────────────────────────┘\n");

    try out.writeAll("\n");
    try display.writeStyled(out, options, .cyan, "📊 Overview");
    try out.writeAll("\n");
    try out.writeAll("────────────────────────────────────────────────────────────\n");

    const total_line = try std.fmt.allocPrint(allocator, "Total Tasks:          {d}\n", .{stats.total});
    defer allocator.free(total_line);
    try out.writeAll(total_line);

    const rate_line = try std.fmt.allocPrint(allocator, "Completion Rate:      {d:.1}%\n", .{completion_rate});
    defer allocator.free(rate_line);
    try out.writeAll(rate_line);

    const tags_line = try std.fmt.allocPrint(allocator, "Total Tags:          {d} ({d} unique)\n", .{ stats.total_tags, stats.unique_tags.count() });
    defer allocator.free(tags_line);
    try out.writeAll(tags_line);

    const blocked_line = try std.fmt.allocPrint(allocator, "Blocked Tasks:        {d}\n", .{stats.blocked_tasks});
    defer allocator.free(blocked_line);
    try out.writeAll(blocked_line);

    try out.writeAll("\n");
    try display.writeStyled(out, options, .cyan, "✅ By Status");
    try out.writeAll("\n");
    try out.writeAll("────────────────────────────────────────────────────────────\n");

    const todo_line = try std.fmt.allocPrint(allocator, "Todo:                 {d}\n", .{stats.by_status[@intFromEnum(Status.todo)]});
    defer allocator.free(todo_line);
    try out.writeAll(todo_line);

    const in_progress_line = try std.fmt.allocPrint(allocator, "In Progress:          {d}\n", .{stats.by_status[@intFromEnum(Status.in_progress)]});
    defer allocator.free(in_progress_line);
    try out.writeAll(in_progress_line);

    const done_line = try std.fmt.allocPrint(allocator, "Done:                 {d}\n", .{stats.by_status[@intFromEnum(Status.done)]});
    defer allocator.free(done_line);
    try out.writeAll(done_line);

    const blocked_status_line = try std.fmt.allocPrint(allocator, "Blocked:              {d}\n", .{stats.by_status[@intFromEnum(Status.blocked)]});
    defer allocator.free(blocked_status_line);
    try out.writeAll(blocked_status_line);

    try out.writeAll("\n");
    try display.writeStyled(out, options, .cyan, "⚡ By Priority");
    try out.writeAll("\n");
    try out.writeAll("────────────────────────────────────────────────────────────\n");

    const low_line = try std.fmt.allocPrint(allocator, "Low:                  {d}\n", .{stats.by_priority[@intFromEnum(Priority.low)]});
    defer allocator.free(low_line);
    try out.writeAll(low_line);

    const medium_line = try std.fmt.allocPrint(allocator, "Medium:               {d}\n", .{stats.by_priority[@intFromEnum(Priority.medium)]});
    defer allocator.free(medium_line);
    try out.writeAll(medium_line);

    const high_line = try std.fmt.allocPrint(allocator, "High:                 {d}\n", .{stats.by_priority[@intFromEnum(Priority.high)]});
    defer allocator.free(high_line);
    try out.writeAll(high_line);

    const critical_line = try std.fmt.allocPrint(allocator, "Critical:             {d}\n", .{stats.by_priority[@intFromEnum(Priority.critical)]});
    defer allocator.free(critical_line);
    try out.writeAll(critical_line);

    try out.writeAll("\n");
    try display.writeStyled(out, options, .cyan, "📈 This Week");
    try out.writeAll("\n");
    try out.writeAll("────────────────────────────────────────────────────────────\n");

    const created_line = try std.fmt.allocPrint(allocator, "Tasks Created:        {d}\n", .{stats.created_this_week});
    defer allocator.free(created_line);
    try out.writeAll(created_line);

    const completed_week_line = try std.fmt.allocPrint(allocator, "Tasks Completed:      {d}\n", .{stats.completed_this_week});
    defer allocator.free(completed_week_line);
    try out.writeAll(completed_week_line);

    if (stats.unique_tags.count() > 0) {
        try out.writeAll("\n");
        try display.writeStyled(out, options, .cyan, "🏷️  Top Tags");
        try out.writeAll("\n");
        try out.writeAll("────────────────────────────────────────────────────────────\n");

        var tag_entries = try std.ArrayList(TagEntry).initCapacity(stats.unique_tags.allocator, stats.unique_tags.count());
        defer tag_entries.deinit(stats.unique_tags.allocator);

        var it = stats.unique_tags.iterator();
        while (it.next()) |entry| {
            try tag_entries.append(allocator, .{ .tag = entry.key_ptr.*, .count = entry.value_ptr.* });
        }

        std.sort.insertion(TagEntry, tag_entries.items, {}, struct {
            fn lessThan(_: void, a: TagEntry, b: TagEntry) bool {
                return a.count > b.count;
            }
        }.lessThan);

        const max_tags = @min(10, tag_entries.items.len);
        for (tag_entries.items[0..max_tags]) |entry| {
            const tag_line = try std.fmt.allocPrint(allocator, "  {s:<20} {d:>4} tasks\n", .{ entry.tag, entry.count });
            defer allocator.free(tag_line);
            try out.writeAll(tag_line);
        }
    }

    try out.writeAll("\n");
}

test "calculate stats" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var store = TaskStore.init(allocator);
    defer store.deinit();

    var task1 = try store.create("Task 1");
    task1.status = .done;

    var task2 = try store.create("Task 2");
    task2.status = .todo;
    try task2.tags.append(allocator, try allocator.dupe(u8, "bug"));
    defer allocator.free(task2.tags.items[0]);

    var task3 = try store.create("Task 3");
    task3.status = .in_progress;

    var stats = Stats.init(allocator);
    defer stats.deinit();

    for (store.tasks.items) |task| {
        stats.total += 1;
        stats.by_status[@intFromEnum(task.status)] += 1;
    }

    try testing.expectEqual(@as(usize, 3), stats.total);
    try testing.expectEqual(@as(usize, 1), stats.by_status[@intFromEnum(Status.done)]);
    try testing.expectEqual(@as(usize, 1), stats.by_status[@intFromEnum(Status.todo)]);
    try testing.expectEqual(@as(usize, 1), stats.by_status[@intFromEnum(Status.in_progress)]);
}
