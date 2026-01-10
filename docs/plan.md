# Tasks CLI - Implementation Plan

Zig 0.15-based task management CLI with dependencies, priorities, and tags.

---

## 1. Technology Stack

**Zig 0.15** - Current stable

- `std.uuid` for UUID v4 generation
- `std.json` for JSON serialization (0.15 compatible)
- `std.mem.Allocator` for memory management
- `std.process.ArgIterator` for CLI parsing
- `std.time.Instant` for timestamps
- Zero external dependencies

---

## 2. Core Data Model (Zig 0.15)

```zig
const std = @import("std");

const Status = enum { todo, in_progress, done, blocked };
const Priority = enum { low, medium, high, critical };

const Task = struct {
    id: std.uuid.Uuid,           // UUID struct from std.uuid
    title: []const u8,           // String slice (owned)
    body: ?[]const u8,           // Optional description
    status: Status,
    priority: Priority,
    tags: std.ArrayList([]const u8),
    dependencies: std.ArrayList([]const u8),  // Task IDs (as strings)
    blocked_by: std.ArrayList([]const u8),
    created_at: i64,             // Unix timestamp (seconds)
    updated_at: i64,
    completed_at: ?i64,
};

const TaskStore = struct {
    tasks: std.ArrayList(Task),
    allocator: std.mem.Allocator,

    // Create from allocator
    fn init(allocator: std.mem.Allocator) TaskStore { ... }

    // Find task by UUID
    fn findByUuid(store: *TaskStore, id: std.uuid.Uuid) ?*Task { ... }

    // Find task by string ID
    fn findById(store: *TaskStore, id_str: []const u8) ?*Task { ... }

    // Calculate blocked_by for all tasks
    fn updateBlockedBy(store: *TaskStore) !void { ... }

    // Check for cycles
    fn hasCycle(store: *TaskStore, start_id: std.uuid.Uuid) bool { ... }

    // Cleanup
    fn deinit(store: *TaskStore) void { ... }
};
```

---

## 3. Storage Format

**JSON** - Zig std has built-in JSON support

`.tasks/tasks.json` (gitignored):

```json
{
  "tasks": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "title": "Task name",
      "body": "Description",
      "status": "todo",
      "priority": "medium",
      "tags": ["frontend", "bug"],
      "dependencies": [],
      "created_at": 1736450400,
      "updated_at": 1736450400
    }
  ]
}
```

---

## 4. CLI Commands (MVP)

### Core CRUD

```
tasks add "Title" [--body DESC] [--tags TAG,TAG] [--priority PRIORITY]
tasks show <ID>
tasks edit <ID> [--title TXT] [--body TXT] [--status S] [--priority P] [--tags TAGS]
tasks delete <ID>
```

### Listing & Filtering

```
tasks list                          # All tasks
tasks list --status STATUS         # Filter
tasks list --priority PRIORITY      # Filter
tasks list --tags TAG,TAG          # Filter (any match)
tasks search QUERY                 # Search title/body
tasks list --blocked               # Only blocked tasks
tasks list --unblocked             # Only unblocked tasks
```

### Workflow

```
tasks done <ID>                    # Mark complete
tasks block <ID>                   # Mark as blocked
tasks unblock <ID>                 # Unblock (reset to todo)
tasks next                         # Show next ready task
tasks next --all                   # Show all ready tasks
```

### Dependencies

```
tasks link <CHILD> <PARENT>        # Add dependency
tasks unlink <CHILD> <PARENT>      # Remove dependency
tasks graph <ID>                   # Show dependency tree
```

### Tags

```
tasks tag <ID> <TAG>               # Add single tag
tasks untag <ID> <TAG>             # Remove single tag
tasks tags                         # List all tags (with counts)
```

### Utility

```
tasks stats                        # Summary counts
tasks init                         # Initialize in current dir
```

---

## 5. Architecture

```
src/
├── main.zig           # CLI entry point, command dispatch
├── cli.zig            # ArgIterator-based CLI parsing
├── model.zig          # Task, Status, Priority, TaskStore
├── store.zig          # JSON file I/O, persistence
├── commands/
│   ├── mod.zig        # Command registry
│   ├── add.zig
│   ├── list.zig
│   ├── show.zig
│   ├── edit.zig
│   ├── delete.zig
│   ├── done.zig
│   ├── link.zig
│   ├── unlink.zig
│   ├── block.zig
│   ├── unblock.zig
│   ├── tag.zig
│   ├── untag.zig
│   ├── tags.zig
│   ├── search.zig
│   ├── next.zig
│   ├── graph.zig
│   └── stats.zig
├── display.zig        # Table formatting, ANSI colors
├── graph.zig          # Dependency graph algorithms
└── utils.zig          # Timestamp formatting, string helpers
```

---

## 6. build.zig (Zig 0.15 Compatible)

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "tasks",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
```

---

## 7. CLI Parsing (Zig 0.15 ArgIterator)

```zig
// src/cli.zig
const std = @import("std");

const Command = enum {
    add,
    list,
    show,
    edit,
    delete,
    done,
    block,
    unblock,
    link,
    unlink,
    tag,
    untag,
    tags,
    search,
    next,
    graph,
    stats,
    help,
    init,
};

const Args = struct {
    command: Command,
    positional: std.ArrayList([]const u8),
    flags: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn getFlag(self: *Args, name: []const u8) ?[]const u8 {
        return self.flags.get(name);
    }

    fn hasFlag(self: *Args, name: []const u8) bool {
        return self.flags.get(name) != null;
    }

    fn deinit(self: *Args) void {
        self.positional.deinit();
        self.flags.deinit();
    }
};

pub fn parse(allocator: std.mem.Allocator) !Args {
    var args = Args{
        .command = .help,
        .positional = std.ArrayList([]const u8).init(allocator),
        .flags = std.StringHashMap([]const u8).init(allocator),
        .allocator = allocator,
    };
    errdefer args.deinit();

    var iter = std.process.args();
    _ = iter.skip(); // Skip executable name

    const cmd_str = iter.next() orelse return args;
    args.command = std.meta.stringToEnum(Command, cmd_str) orelse return error.UnknownCommand;

    // Parse remaining args
    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            // Flag: --flag or --flag=value
            const eq = std.mem.indexOfScalar(u8, arg, '=');
            if (eq) |idx| {
                const key = arg[2..idx];
                const val = arg[idx+1..];
                try args.flags.put(key, val);
            } else {
                try args.flags.put(arg[2..], "");
            }
        } else {
            try args.positional.append(arg);
        }
    }

    return args;
}
```

---

## 8. UUID Handling (Zig 0.15 std.uuid)

```zig
// src/model.zig - UUID helpers
pub fn generateUuid() std.uuid.Uuid {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    // Set version bits (UUID v4)
    random_bytes[6] = (random_bytes[6] & 0x0F) | 0x40;
    random_bytes[8] = (random_bytes[8] & 0x3F) | 0x80;

    return std.uuid.Uuid{ .data = random_bytes };
}

pub fn uuidToString(uuid: std.uuid.Uuid) [36]u8 {
    return std.uuid.formatUuid(uuid);
}

pub fn parseUuid(str: []const u8) !std.uuid.Uuid {
    return std.uuid.parse(str[0..36].*);
}
```

---

## 9. JSON Storage (Zig 0.15 std.json)

```zig
// src/store.zig
const std = @import("std");
const Task = @import("model.zig").Task;

const TASKS_DIR = ".tasks";
const TASKS_FILE = ".tasks/tasks.json";

pub fn ensureDir() !void {
    std.fs.cwd().makePath(TASKS_DIR) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
}

pub fn saveTasks(allocator: std.mem.Allocator, tasks: []const Task) !void {
    try ensureDir();

    var stringified = std.ArrayList(u8).init(allocator);
    defer stringified.deinit();

    const writer = stringified.writer();

    try writer.writeAll("{\"tasks\":[");

    for (tasks, 0..) |task, i| {
        if (i > 0) try writer.writeAll(",");
        try writeTask(writer, task);
    }

    try writer.writeAll("]}");

    try std.fs.cwd().writeFile(.{ .sub_path = TASKS_FILE, .data = stringified.items });
}

pub fn loadTasks(allocator: std.mem.Allocator) !std.ArrayList(Task) {
    const file = std.fs.cwd().openFile(TASKS_FILE, .{}) catch |e| {
        if (e == error.FileNotFound) return std.ArrayList(Task).init(allocator);
        return e;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const tasks_array = parsed.value.object.get("tasks").?.array;
    var tasks = std.ArrayList(Task).init(allocator);

    for (tasks_array.items) |task_val| {
        const task = try parseTask(allocator, task_val.object);
        try tasks.append(task);
    }

    return tasks;
}

fn writeTask(writer: anytype, task: Task) !void {
    try writer.print(
        \{{"id":"{}","title":"{s}","body":"{}","status":"{s}","priority":"{s}","tags":[
    , .{
        std.uuid.formatUuid(task.id),
        task.title,
        if (task.body) |b| b else "",
        @tagName(task.status),
        @tagName(task.priority),
    });

    for (task.tags.items, 0..) |tag, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{tag});
    }

    try writer.writeAll("],\"dependencies\":[");

    for (task.dependencies.items, 0..) |dep, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{dep});
    }

    try writer.print(
        \],"created_at":{},"updated_at":{}}}
    , .{ task.created_at, task.updated_at });
}

fn parseTask(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Task {
    var task = Task{
        .id = try parseUuid(obj.get("id").?.string),
        .title = try allocator.dupe(u8, obj.get("title").?.string),
        .body = if (obj.get("body")) |b|
            try allocator.dupe(u8, b.string)
        else
            null,
        .status = std.meta.stringToEnum(Status, obj.get("status").?.string).?,
        .priority = std.meta.stringToEnum(Priority, obj.get("priority").?.string).?,
        .tags = std.ArrayList([]const u8).init(allocator),
        .dependencies = std.ArrayList([]const u8).init(allocator),
        .blocked_by = std.ArrayList([]const u8).init(allocator),
        .created_at = obj.get("created_at").?.integer,
        .updated_at = obj.get("updated_at").?.integer,
        .completed_at = if (obj.get("completed_at")) |t| t.integer else null,
    };

    const tags_arr = obj.get("tags").?.array;
    for (tags_arr.items) |tag| {
        try task.tags.append(try allocator.dupe(u8, tag.string));
    }

    const deps_arr = obj.get("dependencies").?.array;
    for (deps_arr.items) |dep| {
        try task.dependencies.append(try allocator.dupe(u8, dep.string));
    }

    return task;
}
```

---

## 10. Display & Colors

```zig
// src/display.zig
const std = @import("std");

pub const Color = enum {
    reset,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_white,
};

pub fn color(allocator: std.mem.Allocator, comptime c: Color, comptime fmt: []const u8, args: anytype) ![]const u8 {
    const ansi = switch (c) {
        .reset => "\x1b[0m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .magenta => "\x1b[35m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .bright_black => "\x1b[90m",
        .bright_white => "\x1b[97m",
    };

    const content = try std.fmt.allocPrint(allocator, fmt, args);
    return try std.fmt.allocPrint(allocator, "{s}{s}\x1b[0m", .{ ansi, content });
}

pub fn renderTaskTable(allocator: std.mem.Allocator, tasks: []const Task) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    // Header
    try writer.writeAll("ID      Status    Priority  Title              Tags\n");
    try writer.writeAll("─────────────────────────────────────────────────────\n");

    for (tasks) |task| {
        const status_sym = switch (task.status) {
            .todo => "●",
            .in_progress => "◉",
            .done => "✓",
            .blocked => "⊘",
        };
        const priority_sym = switch (task.priority) {
            .low => "○",
            .medium => "◐",
            .high => "●",
            .critical => "⚠️",
        };

        const id_str = std.uuid.formatUuid(task.id)[0..5];
        try writer.print("{s}  {s} {s} {s:<18} [{s}]\n", .{
            id_str,
            status_sym,
            priority_sym,
            task.title,
            if (task.tags.items.len > 0) task.tags.items[0] else "",
        });
    }

    return buffer.toOwnedSlice();
}

pub fn renderTaskDetail(allocator: std.mem.Allocator, task: Task) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();

    try writer.print("ID:          {s}\n", .{std.uuid.formatUuid(task.id)});
    try writer.print("Title:       {s}\n", .{task.title});
    try writer.print("Status:      {s}\n", .{@tagName(task.status)});
    try writer.print("Priority:    {s}\n", .{@tagName(task.priority)});

    if (task.tags.items.len > 0) {
        try writer.write("Tags:        ");
        for (task.tags.items, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(tag);
        }
        try writer.writeAll("\n");
    }

    if (task.dependencies.items.len > 0) {
        try writer.write("Depends on:  ");
        for (task.dependencies.items, 0..) |dep, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(dep[0..8]);
        }
        try writer.writeAll("\n");
    } else {
        try writer.writeAll("Depends on:  (none)\n");
    }

    try writer.print("Created:     {}\n", .{formatTimestamp(task.created_at)});

    if (task.body) |body| {
        try writer.writeAll("\nDescription:\n");
        try writer.print("  {s}\n", .{body});
    }

    return buffer.toOwnedSlice();
}
```

---

## 11. Dependency Graph Logic

```zig
// src/graph.zig
const std = @import("std");
const Task = @import("model.zig").Task;
const TaskStore = @import("model.zig").TaskStore;

// DFS-based cycle detection
pub fn hasCycle(store: *TaskStore, start_id: std.uuid.Uuid) bool {
    var visited = std.StringHashMap(void).init(store.tasks.allocator);
    defer visited.deinit();
    return hasCycleDfs(store, start_id, &visited);
}

fn hasCycleDfs(store: *TaskStore, task_id: std.uuid.Uuid, visited: *std.StringHashMap(void)) bool {
    const id_str = std.uuid.formatUuid(task_id);
    if (visited.get(id_str)) |_| return true;

    visited.put(id_str, {}) catch {};

    const task = store.findByUuid(task_id) orelse return false;

    for (task.dependencies.items) |dep_str| {
        const dep_id = parseUuid(dep_str) catch continue;
        if (hasCycleDfs(store, dep_id, visited)) return true;
    }

    return false;
}

// Check if task is ready to work on
pub fn isReady(task: Task, store: TaskStore) bool {
    for (task.dependencies.items) |dep_str| {
        const dep_id = parseUuid(dep_str) catch continue;
        const dep = store.findByUuid(dep_id) orelse continue;
        if (dep.status != .done) return false;
    }
    return true;
}

// ASCII tree rendering
pub fn renderTree(allocator: std.mem.Allocator, store: *TaskStore, task_id: std.uuid.Uuid, prefix: []const u8, is_last: bool) !std.ArrayList(u8) {
    var lines = std.ArrayList(u8).init(allocator);
    const writer = lines.writer();

    const task = store.findByUuid(task_id) orelse return lines;
    const id_str = std.uuid.formatUuid(task_id);

    const connector = if (is_last) "└── " else "├── ";
    try writer.print("{s}{s}{s} {s}\n", .{ prefix, connector, id_str[0..5], task.title });

    const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}", .{
        prefix,
        if (is_last) "    " else "│   ",
    });

    for (task.blocked_by.items, 0..) |dep_str, i| {
        const dep_id = parseUuid(dep_str) catch continue;
        const last = i == task.blocked_by.items.len - 1;
        const subtree = try renderTree(allocator, store, dep_id, new_prefix, last);
        defer subtree.deinit();
        try writer.writeAll(subtree.items);
    }

    return lines;
}

// Update blocked_by for all tasks
pub fn updateBlockedBy(store: *TaskStore) !void {
    for (store.tasks.items) |*task| {
        task.blocked_by.clearRetainingCapacity();
    }

    for (store.tasks.items) |task| {
        for (task.dependencies.items) |dep_str| {
            const dep_id = parseUuid(dep_str) catch continue;
            const dep = store.findByUuid(dep_id) orelse continue;
            const id_str = std.uuid.formatUuid(task.id);
            try dep.blocked_by.append(try dep.allocator.dupe(u8, id_str));
        }
    }
}
```

---

## 12. Implementation Phases

### Phase 1: Foundation (Zig 0.15 setup)

- [x] `build.zig` with proper 0.15 API
- [x] `model.zig` - Task struct, UUID helpers, TaskStore
- [x] `cli.zig` - ArgIterator-based parsing
- [x] Basic project structure
- [x] `utils.zig` - Timestamp formatting

### Phase 2: Storage

- [x] `store.zig` - JSON read/write with 0.15 std.json API
- [x] `.tasks/tasks.json` handling
- [x] `init` command
- [x] Error handling for missing files

### Phase 3: Core Commands

- [x] `add.zig` - Create with UUID generation
- [x] `list.zig` - List with table output
- [x] `show.zig` - Detail view
- [x] `delete.zig` - Remove task
- [x] `display.zig` - Table and detail rendering

### Phase 4: Status & Edit

- [x] `edit.zig` - Update fields
- [x] `done.zig`, `block.zig`, `unblock.zig`
- [x] Status transitions
- [x] Timestamp updates on edits

### Phase 5: Dependencies

- [x] `link.zig`, `unlink.zig`
- [x] `graph.zig` - Cycle detection + tree rendering
- [x] `next.zig` - Ready tasks
- [x] `graph` command for visualization

### Phase 6: Tags & Search

- [x] `tag.zig`, `untag.zig`, `tags.zig`
- [x] `search.zig` - Text search
- [x] Filter improvements for `list`
- [x] Tag statistics

### Phase 7: Polish

- [x] `stats.zig` - Summary command
- [x] Better display (colors, formatting)
- [x] Error messages
- [x] Help text
- [x] Tests for core functions

### Phase 8: ANSI Color Enhancement

- [ ] Enhance `display.zig` with color-coded output
- [ ] Color status symbols (todo=yellow, in_progress=blue, done=green, blocked=red)
- [ ] Color priority indicators (low=dim, medium=normal, high=yellow, critical=red)
- [ ] Color stats output sections
- [ ] Add `--no-color` flag to disable colors for non-TTY output
- [ ] Color tag output in `tags` command
- [ ] Enhanced table formatting with borders/lines

---

## 13. Zig 0.15 Specific Notes

**std.uuid**: Use `std.uuid.Uuid{ .data = [16]u8 }` format, `std.uuid.formatUuid()`, `std.uuid.parse()`

**std.json**: API stabilized in 0.15, use `parseFromSlice()` and `Value` type

**std.process.ArgIterator**: Use `iter.skip()` and `iter.next()` - no changes needed

**std.crypto.random**: Use `std.crypto.random.bytes(&buf)` for random data

**File I/O**: `std.fs.cwd().writeFile(.{ .sub_path = path, .data = data })` - new format

**Allocators**: Standard `std.heap.GeneralPurposeAllocator` and `std.mem.Allocator`

**build.zig**: Use `b.path()` for source files, `b.addExecutable()` with proper struct init

---

## 14. Key Design Decisions

**Storage**: JSON (std.json built-in) - simpler than adding TOML dependency

**UUID**: Use `std.uuid` from Zig 0.15

**Allocators**:

- GPA in main.zig for app lifetime
- ArenaAllocator for command-scoped allocations

**CLI parsing**: Hand-roll with `std.process.ArgIterator` - keep it simple

**Error handling**: Zig error union + `try` - idiomatic

**Testing**: Zig's built-in test framework (`zig test`)

**File locations**: `.tasks/tasks.json` in project root, added to .gitignore

**Timestamps**: Unix timestamps (i64 seconds) stored as JSON integers

---

## 15. Justfile (Convenience)

```makefile
build:
    zig build

run:
    zig build run

test:
    zig test src/*.zig

install:
    zig build && cp zig-out/bin/tasks ~/.local/bin/

clean:
    rm -rf zig-cache zig-out .tasks
```

---

## 16. Usage Examples

```bash
# Initialize
tasks init

# Add tasks
tasks add "Implement authentication" --tags "feature,security" --priority high
tasks add "Write tests" --tags "testing" --body "Unit tests for auth module"

# Link dependencies
tasks link <tests-id> <auth-id>

# List
tasks list
tasks list --status todo
tasks list --tags feature

# Work on tasks
tasks next                    # Show next ready task
tasks done <auth-id>          # Mark complete
tasks next                    # Now tests are ready

# Search
tasks search "auth"

# Show details
tasks show <id>

# Tag management
tasks tags                   # List all tags with counts
tasks tag <id> "urgent"
tasks untag <id> "urgent"

# Stats
tasks stats

# Dependency graph
tasks graph <id>

# Delete
tasks delete <id>
```
