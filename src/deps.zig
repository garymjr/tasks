const std = @import("std");
const uuid = @import("uuid.zig");

pub fn updateBlockedBy(store: anytype) !void {
    for (store.tasks.items) |task| {
        for (task.blocked_by.items) |blocked| {
            store.allocator.free(blocked);
        }
        task.blocked_by.clearRetainingCapacity();
    }

    for (store.tasks.items) |task| {
        for (task.dependencies.items) |dep_str| {
            const dep_id = uuid.parseUuid(dep_str[0..36]) catch continue;
            const dep = store.findByUuid(dep_id) orelse continue;
            const id_str = uuid.formatUuid(task.id);
            try dep.blocked_by.append(store.allocator, try store.allocator.dupe(u8, &id_str));
        }
    }
}

pub fn hasCycle(store: anytype, start_id: anytype) bool {
    const UuidType = @TypeOf(start_id);
    var visited = std.AutoHashMap(UuidType, u8).init(store.allocator);
    defer visited.deinit();
    var in_stack = std.AutoHashMap(UuidType, u8).init(store.allocator);
    defer in_stack.deinit();
    return hasCycleDfs(UuidType, store, start_id, &visited, &in_stack);
}

pub fn isReady(store: anytype, task: anytype) bool {
    for (task.dependencies.items) |dep_str| {
        const dep_id = uuid.parseUuid(dep_str[0..36]) catch continue;
        const dep = store.findByUuid(dep_id) orelse continue;
        if (dep.status != .done) return false;
    }
    return true;
}

pub fn getReadyTasks(store: anytype) @TypeOf(store.tasks) {
    const TasksList = @TypeOf(store.tasks);
    var result = TasksList{};
    for (store.tasks.items) |task| {
        if (task.status == .todo and isReady(store, task.*)) {
            result.append(store.allocator, task) catch {};
        }
    }
    return result;
}

pub fn getBlockedTasks(store: anytype) @TypeOf(store.tasks) {
    const TasksList = @TypeOf(store.tasks);
    var result = TasksList{};
    for (store.tasks.items) |task| {
        if (task.dependencies.items.len > 0 and !isReady(store, task.*)) {
            result.append(store.allocator, task) catch {};
        }
    }
    return result;
}

fn hasCycleDfs(
    comptime UuidType: type,
    store: anytype,
    task_id: UuidType,
    visited: *std.AutoHashMap(UuidType, u8),
    in_stack: *std.AutoHashMap(UuidType, u8),
) bool {
    if (in_stack.get(task_id)) |_| return true;
    if (visited.get(task_id)) |_| return false;
    visited.put(task_id, 1) catch {};
    in_stack.put(task_id, 1) catch {};

    const task = store.findByUuid(task_id) orelse {
        _ = in_stack.remove(task_id);
        return false;
    };

    for (task.dependencies.items) |dep_str| {
        const dep_id = uuid.parseUuid(dep_str[0..36]) catch continue;
        if (hasCycleDfs(UuidType, store, dep_id, visited, in_stack)) return true;
    }

    _ = in_stack.remove(task_id);
    return false;
}
