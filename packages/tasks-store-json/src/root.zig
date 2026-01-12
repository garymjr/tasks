const std = @import("std");
const model = @import("tasks-core").model;
const Task = model.Task;
const TaskStore = model.TaskStore;
const Uuid = model.Uuid;
const Status = model.Status;
const Priority = model.Priority;
const parseUuid = model.parseUuid;
const formatUuid = model.formatUuid;

const TASKS_DIR = ".tasks";
const TASKS_FILE = ".tasks/tasks.json";
const LOCK_FILE = ".tasks/tasks.lock";

pub const StorageError = error{
    FileNotFound,
    InvalidJson,
    WriteFailed,
    ReadFailed,
    LockFailed,
} || std.fs.File.WriteError || std.fs.File.OpenError || std.json.ParseError || std.json.StringifyError || std.mem.Allocator.Error;

pub fn ensureDir() !void {
    std.fs.cwd().makePath(TASKS_DIR) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
}

pub fn exists() bool {
    const file = std.fs.cwd().openFile(TASKS_FILE, .{}) catch |e| {
        if (e == error.FileNotFound) return false;
        return false;
    };
    file.close();
    return true;
}

pub fn createLock() !std.fs.File {
    try ensureDir();
    return std.fs.cwd().openFile(LOCK_FILE, .{ .mode = .read_write }) catch |e| {
        if (e == error.FileNotFound) {
            return std.fs.cwd().createFile(LOCK_FILE, .{ .exclusive = true });
        }
        return e;
    };
}

pub fn saveTasks(allocator: std.mem.Allocator, store: *TaskStore) !void {
    try ensureDir();

    const lock_file = try createLock();
    defer lock_file.close();

    var stringified = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer stringified.deinit(allocator);

    const writer = stringified.writer(allocator);

    try writer.writeAll("{\"tasks\":[");

    for (store.tasks.items, 0..) |task, i| {
        if (i > 0) try writer.writeAll(",");
        try writeTask(writer, task);
    }

    try writer.writeAll("]}");

    const temp_path = ".tasks/tasks.json.tmp";
    try std.fs.cwd().writeFile(.{ .sub_path = temp_path, .data = stringified.items });

    std.fs.cwd().rename(temp_path, TASKS_FILE) catch |e| {
        _ = std.fs.cwd().deleteFile(temp_path) catch {};
        return e;
    };
}

pub fn loadTasks(allocator: std.mem.Allocator) !TaskStore {
    var store = TaskStore.init(allocator);
    errdefer store.deinit();

    const file = std.fs.cwd().openFile(TASKS_FILE, .{}) catch |e| {
        if (e == error.FileNotFound) return error.FileNotFound;
        return e;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |e| {
        return e;
    };
    defer allocator.free(content);

    if (content.len == 0) return error.InvalidJson;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();

    const obj = parsed.value.object;

    const tasks_array = obj.get("tasks") orelse return error.InvalidJson;
    const tasks_arr = tasks_array.array;

    for (tasks_arr.items) |task_val| {
        const task_obj = task_val.object;
        const task = try parseTask(allocator, task_obj);
        const task_ptr = try allocator.create(Task);
        task_ptr.* = task;
        try store.tasks.append(allocator, task_ptr);
    }

    try store.updateBlockedBy();

    return store;
}

pub fn initStore(_: std.mem.Allocator) !void {
    if (exists()) {
        return error.AlreadyInitialized;
    }

    try ensureDir();

    const initial_content = "{\"tasks\":[]}";
    try std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = initial_content });
}

pub fn deinitStore() !void {
    if (exists()) {
        _ = std.fs.cwd().deleteFile(TASKS_FILE) catch {};
    }
}

fn writeTask(writer: anytype, task: *const Task) !void {
    const id_str = formatUuid(task.id);
    const body_str = if (task.body) |b| b else "";

    try writer.writeAll("{\"id\":");
    try writeJsonString(writer, &id_str);
    try writer.writeAll(",\"title\":");
    try writeJsonString(writer, task.title);
    try writer.writeAll(",\"body\":");
    try writeJsonString(writer, body_str);
    try writer.writeAll(",\"status\":");
    try writeJsonString(writer, @tagName(task.status));
    try writer.writeAll(",\"priority\":");
    try writeJsonString(writer, @tagName(task.priority));
    try writer.writeAll(",\"tags\":[");

    for (task.tags.items, 0..) |tag, i| {
        if (i > 0) try writer.writeAll(",");
        try writeJsonString(writer, tag);
    }

    try writer.writeAll("],\"dependencies\":[");

    for (task.dependencies.items, 0..) |dep, i| {
        if (i > 0) try writer.writeAll(",");
        try writeJsonString(writer, dep);
    }

    try writer.print("],\"created_at\":{},\"updated_at\":{},\"completed_at\":", .{
        task.created_at,
        task.updated_at,
    });
    try writeOptionalTimestamp(writer, task.completed_at);
    try writer.writeAll("}");
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            else => {
                if (byte < 0x20) {
                    const hex = "0123456789abcdef";
                    var esc: [6]u8 = .{ '\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0x0F] };
                    try writer.writeAll(&esc);
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeOptionalTimestamp(writer: anytype, timestamp: ?i64) !void {
    if (timestamp) |value| {
        try writer.print("{}", .{value});
    } else {
        try writer.writeAll("null");
    }
}

fn parseTask(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Task {
    const id_val = obj.get("id") orelse return error.InvalidJson;
    const title_val = obj.get("title") orelse return error.InvalidJson;
    const status_val = obj.get("status") orelse return error.InvalidJson;
    const priority_val = obj.get("priority") orelse return error.InvalidJson;
    const created_val = obj.get("created_at") orelse return error.InvalidJson;
    const updated_val = obj.get("updated_at") orelse return error.InvalidJson;

    const id_str = id_val.string;
    const id = try parseUuid(id_str);

    var task = Task{
        .id = id,
        .title = try allocator.dupe(u8, title_val.string),
        .body = null,
        .status = std.meta.stringToEnum(Status, status_val.string) orelse return error.InvalidJson,
        .priority = std.meta.stringToEnum(Priority, priority_val.string) orelse return error.InvalidJson,
        .tags = .{},
        .dependencies = .{},
        .blocked_by = .{},
        .created_at = created_val.integer,
        .updated_at = updated_val.integer,
        .completed_at = null,
    };

    if (obj.get("body")) |b| {
        task.body = try allocator.dupe(u8, b.string);
    }

    if (obj.get("completed_at")) |t| {
        switch (t) {
            .integer => |value| task.completed_at = value,
            .null => {},
            else => return error.InvalidJson,
        }
    }

    if (obj.get("tags")) |tags_val| {
        const tags_arr = tags_val.array;
        for (tags_arr.items) |tag| {
            try task.tags.append(allocator, try allocator.dupe(u8, tag.string));
        }
    }

    if (obj.get("dependencies")) |deps_val| {
        const deps_arr = deps_val.array;
        for (deps_arr.items) |dep| {
            try task.dependencies.append(allocator, try allocator.dupe(u8, dep.string));
        }
    }

    return task;
}

test "init and load empty store" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var store = try loadTasks(allocator);
    defer store.deinit();
}

test "save and load tasks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var store1 = TaskStore.init(allocator);
    defer store1.deinit();

    const task1 = try store1.create("Test task 1");
    try task1.tags.append(allocator, try allocator.dupe(u8, "bug"));
    const task2 = try store1.create("Test task 2");
    task2.priority = .high;
    task2.markDone();
    const expected_completed_at = task2.completed_at.?;

    try saveTasks(allocator, &store1);

    var store2 = try loadTasks(allocator);
    defer store2.deinit();

    try testing.expectEqual(@as(usize, 2), store2.tasks.items.len);

    const loaded1 = store2.findByUuid(task1.id).?;
    try testing.expectEqualStrings("Test task 1", loaded1.title);
    try testing.expectEqual(@as(usize, 1), loaded1.tags.items.len);

    const loaded2 = store2.findByUuid(task2.id).?;
    try testing.expectEqualStrings("Test task 2", loaded2.title);
    try testing.expectEqual(Priority.high, loaded2.priority);
    try testing.expectEqual(expected_completed_at, loaded2.completed_at.?);
}

test "save and load tasks with escaped strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var store1 = TaskStore.init(allocator);
    defer store1.deinit();

    const task = try store1.create("Quote \"test\"\nLine");
    task.body = try allocator.dupe(u8, "Body line\r\nSecond \"row\"");
    try task.tags.append(allocator, try allocator.dupe(u8, "tag\"1"));
    try task.tags.append(allocator, try allocator.dupe(u8, "tag\n2"));

    try saveTasks(allocator, &store1);

    var store2 = try loadTasks(allocator);
    defer store2.deinit();

    const loaded = store2.findByUuid(task.id).?;
    try testing.expectEqualStrings("Quote \"test\"\nLine", loaded.title);
    try testing.expectEqualStrings("Body line\r\nSecond \"row\"", loaded.body.?);
    try testing.expectEqual(@as(usize, 2), loaded.tags.items.len);
    try testing.expectEqualStrings("tag\"1", loaded.tags.items[0]);
    try testing.expectEqualStrings("tag\n2", loaded.tags.items[1]);
}
