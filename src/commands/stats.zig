const std = @import("std");
const model = @import("../model.zig");
const TaskStore = model.TaskStore;
const Status = model.Status;
const Priority = model.Priority;
const display = @import("../display.zig");
const utils = @import("../utils.zig");

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

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    const store = @import("../store.zig");

    var task_store = try store.loadTasks(allocator);
    defer task_store.deinit();

    if (task_store.tasks.items.len == 0) {
        try stdout.writeAll("No tasks found. Add a task with 'tasks add \"Title\"'.\n");
        return;
    }

    var stats = Stats.init(allocator);
    defer stats.deinit();

    const now = std.time.timestamp();
    const one_week_ago = now - (7 * 86400);

    // Calculate statistics
    for (task_store.tasks.items) |task| {
        stats.total += 1;
        stats.by_status[@intFromEnum(task.status)] += 1;
        stats.by_priority[@intFromEnum(task.priority)] += 1;

        // Count tags
        stats.total_tags += task.tags.items.len;
        for (task.tags.items) |tag| {
            const gop = try stats.unique_tags.getOrPut(tag);
            if (!gop.found_existing) {
                gop.key_ptr.* = try allocator.dupe(u8, tag);
                gop.value_ptr.* = 0;
            }
            gop.value_ptr.* += 1;
        }

        // Count blocked tasks
        if (task.status == .blocked or task.blocked_by.items.len > 0) {
            stats.blocked_tasks += 1;
        }

        // Count tasks completed/created this week
        if (task.completed_at) |completed| {
            if (completed > one_week_ago) {
                stats.completed_this_week += 1;
            }
        }
        if (task.created_at > one_week_ago) {
            stats.created_this_week += 1;
        }
    }

    // Calculate completion rate
    const completion_rate: f64 = if (stats.total > 0)
        @as(f64, @floatFromInt(stats.by_status[@intFromEnum(Status.done)])) / @as(f64, @floatFromInt(stats.total)) * 100.0
    else
        0.0;

    try renderStats(stdout, &stats, completion_rate);
}

fn renderStats(stdout: std.fs.File, stats: *const Stats, completion_rate: f64) !void {
    const allocator = stats.unique_tags.allocator;

    const TagEntry = struct { tag: []const u8, count: usize };

    try stdout.writeAll("┌─────────────────────────────────────────────────────────────┐\n");
    try stdout.writeAll("│                         Task Statistics                     │\n");
    try stdout.writeAll("└─────────────────────────────────────────────────────────────┘\n");

    try stdout.writeAll("\n📊 Overview\n");
    try stdout.writeAll("────────────────────────────────────────────────────────────\n");

    const total_line = try std.fmt.allocPrint(allocator, "Total Tasks:          {d}\n", .{stats.total});
    defer allocator.free(total_line);
    try stdout.writeAll(total_line);

    const rate_line = try std.fmt.allocPrint(allocator, "Completion Rate:      {d:.1}%\n", .{completion_rate});
    defer allocator.free(rate_line);
    try stdout.writeAll(rate_line);

    const tags_line = try std.fmt.allocPrint(allocator, "Total Tags:          {d} ({d} unique)\n", .{ stats.total_tags, stats.unique_tags.count() });
    defer allocator.free(tags_line);
    try stdout.writeAll(tags_line);

    const blocked_line = try std.fmt.allocPrint(allocator, "Blocked Tasks:        {d}\n", .{stats.blocked_tasks});
    defer allocator.free(blocked_line);
    try stdout.writeAll(blocked_line);

    try stdout.writeAll("\n✅ By Status\n");
    try stdout.writeAll("────────────────────────────────────────────────────────────\n");

    const todo_line = try std.fmt.allocPrint(allocator, "Todo:                 {d}\n", .{stats.by_status[@intFromEnum(Status.todo)]});
    defer allocator.free(todo_line);
    try stdout.writeAll(todo_line);

    const in_progress_line = try std.fmt.allocPrint(allocator, "In Progress:          {d}\n", .{stats.by_status[@intFromEnum(Status.in_progress)]});
    defer allocator.free(in_progress_line);
    try stdout.writeAll(in_progress_line);

    const done_line = try std.fmt.allocPrint(allocator, "Done:                 {d}\n", .{stats.by_status[@intFromEnum(Status.done)]});
    defer allocator.free(done_line);
    try stdout.writeAll(done_line);

    const blocked_status_line = try std.fmt.allocPrint(allocator, "Blocked:              {d}\n", .{stats.by_status[@intFromEnum(Status.blocked)]});
    defer allocator.free(blocked_status_line);
    try stdout.writeAll(blocked_status_line);

    try stdout.writeAll("\n⚡ By Priority\n");
    try stdout.writeAll("────────────────────────────────────────────────────────────\n");

    const low_line = try std.fmt.allocPrint(allocator, "Low:                  {d}\n", .{stats.by_priority[@intFromEnum(Priority.low)]});
    defer allocator.free(low_line);
    try stdout.writeAll(low_line);

    const medium_line = try std.fmt.allocPrint(allocator, "Medium:               {d}\n", .{stats.by_priority[@intFromEnum(Priority.medium)]});
    defer allocator.free(medium_line);
    try stdout.writeAll(medium_line);

    const high_line = try std.fmt.allocPrint(allocator, "High:                 {d}\n", .{stats.by_priority[@intFromEnum(Priority.high)]});
    defer allocator.free(high_line);
    try stdout.writeAll(high_line);

    const critical_line = try std.fmt.allocPrint(allocator, "Critical:             {d}\n", .{stats.by_priority[@intFromEnum(Priority.critical)]});
    defer allocator.free(critical_line);
    try stdout.writeAll(critical_line);

    try stdout.writeAll("\n📈 This Week\n");
    try stdout.writeAll("────────────────────────────────────────────────────────────\n");

    const created_line = try std.fmt.allocPrint(allocator, "Tasks Created:        {d}\n", .{stats.created_this_week});
    defer allocator.free(created_line);
    try stdout.writeAll(created_line);

    const completed_week_line = try std.fmt.allocPrint(allocator, "Tasks Completed:      {d}\n", .{stats.completed_this_week});
    defer allocator.free(completed_week_line);
    try stdout.writeAll(completed_week_line);

    if (stats.unique_tags.count() > 0) {
        try stdout.writeAll("\n🏷️  Top Tags\n");
        try stdout.writeAll("────────────────────────────────────────────────────────────\n");

        // Sort tags by count
        var tag_entries = try std.ArrayList(TagEntry).initCapacity(stats.unique_tags.allocator, stats.unique_tags.count());
        defer tag_entries.deinit(stats.unique_tags.allocator);

        var it = stats.unique_tags.iterator();
        while (it.next()) |entry| {
            try tag_entries.append(allocator, .{ .tag = entry.key_ptr.*, .count = entry.value_ptr.* });
        }

        // Sort descending by count
        std.sort.insertion(TagEntry, tag_entries.items, {}, struct {
            fn lessThan(_: void, a: TagEntry, b: TagEntry) bool {
                return a.count > b.count;
            }
        }.lessThan);

        // Show top 10 tags
        const max_tags = @min(10, tag_entries.items.len);
        for (tag_entries.items[0..max_tags]) |entry| {
            const tag_line = try std.fmt.allocPrint(allocator, "  {s:<20} {d:>4} tasks\n", .{ entry.tag, entry.count });
            defer allocator.free(tag_line);
            try stdout.writeAll(tag_line);
        }
    }

    try stdout.writeAll("\n");
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
