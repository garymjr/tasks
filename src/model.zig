const std = @import("std");
const deps = @import("deps.zig");
const uuid = @import("uuid.zig");

const ArrayListUnmanaged = std.array_list.Aligned;

pub const Status = enum { todo, in_progress, done, blocked };
pub const Priority = enum { low, medium, high, critical };

pub const Uuid = uuid.Uuid;
pub const formatUuid = uuid.formatUuid;
pub const uuidToString = uuid.uuidToString;
pub const generateUuid = uuid.generateUuid;
pub const parseUuid = uuid.parseUuid;

pub const Task = struct {
    id: Uuid,
    title: []const u8,
    body: ?[]const u8,
    status: Status,
    priority: Priority,
    tags: ArrayListUnmanaged([]const u8, null),
    dependencies: ArrayListUnmanaged([]const u8, null),
    blocked_by: ArrayListUnmanaged([]const u8, null),
    created_at: i64,
    updated_at: i64,
    completed_at: ?i64,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) !Task {
        return Task{
            .id = generateUuid(),
            .title = try allocator.dupe(u8, title),
            .body = null,
            .status = .todo,
            .priority = .medium,
            .tags = ArrayListUnmanaged([]const u8, null){},
            .dependencies = ArrayListUnmanaged([]const u8, null){},
            .blocked_by = ArrayListUnmanaged([]const u8, null){},
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
            .completed_at = null,
        };
    }

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        if (self.body) |b| allocator.free(b);
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
        for (self.dependencies.items) |dep| allocator.free(dep);
        self.dependencies.deinit(allocator);
        for (self.blocked_by.items) |blocked| allocator.free(blocked);
        self.blocked_by.deinit(allocator);
    }

    pub fn updateTimestamp(self: *Task) void {
        self.updated_at = std.time.timestamp();
    }

    pub fn markDone(self: *Task) void {
        self.status = .done;
        self.completed_at = std.time.timestamp();
        self.updateTimestamp();
    }

    pub fn setStatus(self: *Task, new_status: Status) void {
        if (new_status == .done) {
            self.completed_at = std.time.timestamp();
        } else if (self.status == .done and new_status != .done) {
            self.completed_at = null;
        }
        self.status = new_status;
        self.updateTimestamp();
    }
};

pub const TaskStore = struct {
    tasks: ArrayListUnmanaged(*Task, null),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TaskStore {
        return TaskStore{
            .tasks = ArrayListUnmanaged(*Task, null){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TaskStore) void {
        for (self.tasks.items) |task| {
            task.deinit(self.allocator);
            self.allocator.destroy(task);
        }
        self.tasks.deinit(self.allocator);
    }

    pub fn create(self: *TaskStore, title: []const u8) !*Task {
        const task_ptr = try self.allocator.create(Task);
        task_ptr.* = try Task.init(self.allocator, title);
        try self.tasks.append(self.allocator, task_ptr);
        return task_ptr;
    }

    pub fn findByUuid(self: *TaskStore, id: Uuid) ?*Task {
        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, &task.id.data, &id.data)) {
                return task;
            }
        }
        return null;
    }

    pub fn findByIdString(self: *TaskStore, id_str: []const u8) !?*Task {
        const trimmed = if (id_str.len >= 36) id_str[0..36] else id_str;
        const id = try parseUuid(trimmed);
        return self.findByUuid(id);
    }

    pub fn findByShortId(self: *TaskStore, short_id: []const u8) ?*Task {
        const target_len = @min(short_id.len, 8);
        for (self.tasks.items) |task| {
            const full_id = formatUuid(task.id);
            if (std.mem.eql(u8, full_id[0..target_len], short_id[0..target_len])) {
                return task;
            }
        }
        return null;
    }

    pub fn removeByUuid(self: *TaskStore, id: Uuid) !void {
        for (self.tasks.items, 0..) |task, i| {
            if (std.mem.eql(u8, &task.id.data, &id.data)) {
                task.deinit(self.allocator);
                self.allocator.destroy(task);
                _ = self.tasks.orderedRemove(i);
                return;
            }
        }
        return error.TaskNotFound;
    }

    pub fn filterByStatus(self: *TaskStore, status: Status) ArrayListUnmanaged(*Task, null) {
        var result = ArrayListUnmanaged(*Task, null){};
        for (self.tasks.items) |task| {
            if (task.status == status) {
                result.append(self.allocator, task) catch {};
            }
        }
        return result;
    }

    pub fn filterByPriority(self: *TaskStore, priority: Priority) ArrayListUnmanaged(*Task, null) {
        var result = ArrayListUnmanaged(*Task, null){};
        for (self.tasks.items) |task| {
            if (task.priority == priority) {
                result.append(self.allocator, task) catch {};
            }
        }
        return result;
    }

    pub fn filterByTag(self: *TaskStore, tag: []const u8) ArrayListUnmanaged(*Task, null) {
        var result = ArrayListUnmanaged(*Task, null){};
        for (self.tasks.items) |task| {
            for (task.tags.items) |t| {
                if (std.mem.eql(u8, t, tag)) {
                    result.append(self.allocator, task) catch {};
                    break;
                }
            }
        }
        return result;
    }

    pub fn search(self: *TaskStore, query: []const u8) ArrayListUnmanaged(*Task, null) {
        var result = ArrayListUnmanaged(*Task, null){};
        const query_lower = toLower(self.allocator, query) catch return result;
        defer self.allocator.free(query_lower);

        for (self.tasks.items) |task| {
            const title_lower = toLower(self.allocator, task.title) catch continue;
            defer self.allocator.free(title_lower);

            if (std.mem.indexOf(u8, title_lower, query_lower) != null) {
                result.append(self.allocator, task) catch {};
                continue;
            }

            if (task.body) |body| {
                const body_lower = toLower(self.allocator, body) catch continue;
                defer self.allocator.free(body_lower);
                if (std.mem.indexOf(u8, body_lower, query_lower) != null) {
                    result.append(self.allocator, task) catch {};
                }
            }
        }
        return result;
    }

    pub fn updateBlockedBy(self: *TaskStore) !void {
        return deps.updateBlockedBy(self);
    }

    pub fn hasCycle(self: *TaskStore, start_id: Uuid) bool {
        return deps.hasCycle(self, start_id);
    }

    pub fn isReady(self: *TaskStore, task: Task) bool {
        return deps.isReady(self, task);
    }

    pub fn getReadyTasks(self: *TaskStore) ArrayListUnmanaged(*Task, null) {
        return deps.getReadyTasks(self);
    }

    pub fn getBlockedTasks(self: *TaskStore) ArrayListUnmanaged(*Task, null) {
        return deps.getBlockedTasks(self);
    }
};

fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    return result;
}

test "task init and deinit" {
    const allocator = std.testing.allocator;
    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    try std.testing.expectEqual(Status.todo, task.status);
    try std.testing.expectEqual(Priority.medium, task.priority);
    try std.testing.expect(task.completed_at == null);
    try std.testing.expect(task.created_at > 0);
}

test "task mark done" {
    const allocator = std.testing.allocator;
    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    try std.testing.expect(task.completed_at == null);
    task.markDone();
    try std.testing.expectEqual(Status.done, task.status);
    try std.testing.expect(task.completed_at != null);
}

test "task set status" {
    const allocator = std.testing.allocator;
    var task = try Task.init(allocator, "Test task");
    defer task.deinit(allocator);

    task.setStatus(.in_progress);
    try std.testing.expectEqual(Status.in_progress, task.status);
    try std.testing.expect(task.completed_at == null);

    task.setStatus(.done);
    try std.testing.expectEqual(Status.done, task.status);
    try std.testing.expect(task.completed_at != null);

    task.setStatus(.todo);
    try std.testing.expectEqual(Status.todo, task.status);
    try std.testing.expect(task.completed_at == null);
}

test "taskstore add and find" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task = try store.create("First task");
    const id = task.id;

    const found = store.findByUuid(id);
    try std.testing.expect(found != null);
    try std.testing.expect(std.mem.eql(u8, found.?.title, "First task"));

    try std.testing.expect(store.findByUuid(generateUuid()) == null);
}

test "taskstore find by short id" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task = try store.create("Test task");
    const full_id = uuidToString(task.id);
    const short_id = full_id[0..8];

    const found = store.findByShortId(short_id);
    try std.testing.expect(found != null);
    try std.testing.expect(std.mem.eql(u8, found.?.title, "Test task"));
}

test "taskstore remove" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task = try store.create("To delete");
    const id = task.id;

    try store.removeByUuid(id);
    try std.testing.expect(store.findByUuid(id) == null);
}

test "taskstore filter by status" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    _ = try store.create("Task 1");
    const task2 = try store.create("Task 2");
    task2.setStatus(.in_progress);
    const task3 = try store.create("Task 3");
    task3.setStatus(.done);

    var in_progress = store.filterByStatus(.in_progress);
    defer in_progress.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), in_progress.items.len);
    try std.testing.expect(std.mem.eql(u8, in_progress.items[0].title, "Task 2"));
}

test "taskstore filter by priority" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    _ = try store.create("Task 1");
    const task2 = try store.create("Task 2");
    task2.priority = .high;
    _ = try store.create("Task 3");

    var high = store.filterByPriority(.high);
    defer high.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), high.items.len);
    try std.testing.expect(std.mem.eql(u8, high.items[0].title, "Task 2"));
}

test "taskstore filter by tag" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task1 = try store.create("Task 1");
    try task1.tags.append(allocator, allocator.dupe(u8, "bug") catch unreachable);
    const task2 = try store.create("Task 2");
    try task2.tags.append(allocator, allocator.dupe(u8, "feature") catch unreachable);

    var bugs = store.filterByTag("bug");
    defer bugs.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), bugs.items.len);
    try std.testing.expect(std.mem.eql(u8, bugs.items[0].title, "Task 1"));
}

test "taskstore search" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    _ = try store.create("Fix authentication bug");
    const task2 = try store.create("Write tests");
    task2.body = allocator.dupe(u8, "Add unit tests for auth module") catch unreachable;

    var results = store.search("auth");
    defer results.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), results.items.len);
}

test "taskstore is ready" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task1 = try store.create("First task");
    const task2 = try store.create("Second task");

    const uuid_arr = uuidToString(task1.id);
    const id_str = try allocator.dupe(u8, &uuid_arr);
    try task2.dependencies.append(allocator, id_str);

    try std.testing.expect(!store.isReady(task2.*));
    task1.markDone();
    try std.testing.expect(store.isReady(task2.*));
}

test "taskstore get ready tasks" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    _ = try store.create("Ready task 1");
    _ = try store.create("Ready task 2");

    var ready = store.getReadyTasks();
    defer ready.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), ready.items.len);
}

test "taskstore get blocked tasks" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const blocker = try store.create("Blocker");
    const blocked = try store.create("Blocked task");
    const uuid_arr = uuidToString(blocker.id);
    const id_str = try allocator.dupe(u8, &uuid_arr);
    try blocked.dependencies.append(allocator, id_str);

    var blocked_tasks = store.getBlockedTasks();
    defer blocked_tasks.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), blocked_tasks.items.len);
}

test "taskstore has cycle" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task1 = try store.create("Task 1");
    const task2 = try store.create("Task 2");

    const uuid1 = uuidToString(task1.id);
    const uuid2 = uuidToString(task2.id);
    const id1 = try allocator.dupe(u8, &uuid1);
    const id2 = try allocator.dupe(u8, &uuid2);
    try task1.dependencies.append(allocator, id1);
    try task2.dependencies.append(allocator, id2);

    try std.testing.expect(store.hasCycle(task1.id));
}

test "taskstore has no cycle in diamond" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const root = try store.create("Root");
    const left = try store.create("Left");
    const right = try store.create("Right");
    const join = try store.create("Join");

    const root_uuid = uuidToString(root.id);
    const left_uuid = uuidToString(left.id);
    const right_uuid = uuidToString(right.id);

    const root_id = try allocator.dupe(u8, &root_uuid);
    const left_id = try allocator.dupe(u8, &left_uuid);
    const right_id = try allocator.dupe(u8, &right_uuid);

    try left.dependencies.append(allocator, root_id);
    try right.dependencies.append(allocator, try allocator.dupe(u8, &root_uuid));
    try join.dependencies.append(allocator, left_id);
    try join.dependencies.append(allocator, right_id);

    try std.testing.expect(!store.hasCycle(join.id));
}

test "taskstore update blocked by" {
    const allocator = std.testing.allocator;
    var store = TaskStore.init(allocator);
    defer store.deinit();

    const task1 = try store.create("Task 1");
    const task2 = try store.create("Task 2");

    const uuid_arr = uuidToString(task1.id);
    const id_str = try allocator.dupe(u8, &uuid_arr);
    try task2.dependencies.append(allocator, id_str);

    try store.updateBlockedBy();
    try std.testing.expectEqual(@as(usize, 1), task1.blocked_by.items.len);
}
