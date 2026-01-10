# Known Issues

## Memory Leak: formatRelativeAlloc

### Severity
Medium - Causes memory to leak on each command execution that displays task details.

### Description
The `formatRelativeAlloc` function in `src/utils.zig` allocates memory to format relative timestamps (e.g., "just now", "5m ago"). However, when called from `renderTaskDetail` in `src/display.zig`, the allocated strings are never freed.

### Affected Code
**File: `src/display.zig`**
```zig
try writer.print("Created:     {s}\n", .{utils.formatRelativeAlloc(allocator, task.created_at) catch "?"});
try writer.print("Updated:     {s}\n", .{utils.formatRelativeAlloc(allocator, task.updated_at) catch "?"});
try writer.print("Completed:   {s}\n", .{utils.formatRelativeAlloc(allocator, completed) catch "?"});
```

**Root Cause:**
The allocated string is passed directly to `print` which only reads it. The memory is never freed because the call pattern doesn't allow for cleanup.

### Stack Trace Example
```
error(gpa): memory address 0x100640000 leaked:
/Users/gmurray/.local/share/mise/installs/zig/0.15.2/lib/std/mem/Allocator.zig:436:40: 0x1002fdf57 in dupe__anon_5767 (tasks)
    const new_buf = try allocator.alloc(T, m.len);
                                       ^
/Users/gmurray/Developer/tasks/src/utils.zig:102:30: 0x10038ad87 in formatRelativeAlloc (tasks)
        return allocator.dupe(u8, "just now");
                             ^
/Users/gmurray/Developer/tasks/src/display.zig:94:71: 0x10038c643 in renderTaskDetail (tasks)
    try writer.print("Created:     {s}\n", .{utils.formatRelativeAlloc(allocator, task.created_at) catch "?"});
```

### Impact
- Every command that displays task details (`show`, `edit`, `done`, `block`, `unblock`, etc.) leaks memory
- Memory is freed when the program exits (GPA cleanup)
- No functional impact, but shows leak detection errors

### Workaround
None currently. The leak is harmless for CLI usage but should be fixed for correctness.

### Proposed Fix

**Option 1: Use Stack Buffer**
Change `renderTaskDetail` to use stack buffers instead of allocating:

```zig
const created_buf = std.fmt.allocPrint(allocator, "{s}", .{utils.formatRelativeAlloc(allocator, task.created_at) catch "?"}) catch unreachable;
defer allocator.free(created_buf);
try writer.print("Created:     {s}\n", .{created_buf});
```

This still leaks but makes the pattern explicit - actually not a fix.

**Option 2: Refactor formatRelativeAlloc to accept writer**
Pass the writer directly and avoid intermediate allocation:

```zig
fn formatRelativeToWriter(writer: anytype, timestamp: i64) !void {
    const now = std.time.timestamp();
    const diff = now - timestamp;

    if (diff < 60) {
        try writer.writeAll("just now");
    } else if (diff < 3600) {
        const mins = @divTrunc(diff, 60);
        try writer.print("{d}m ago", .{mins});
    } else if (diff < 86400) {
        const hours = @divTrunc(diff, 3600);
        try writer.print("{d}h ago", .{hours});
    } else if (diff < 604800) {
        const days = @divTrunc(diff, 86400);
        try writer.print("{d}d ago", .{days});
    } else {
        const weeks = @divTrunc(diff, 604800);
        try writer.print("{d}w ago", .{weeks});
    }
}
```

Then in `renderTaskDetail`:
```zig
try writer.writeAll("Created:     ");
try utils.formatRelativeToWriter(writer, task.created_at);
try writer.writeAll("\n");
```

This is the recommended fix as it eliminates the allocation entirely.

### Status
Open - Fix pending. Workaround is to ignore the leak detection errors (memory is freed on program exit).

### Related Files
- `src/utils.zig` - Contains `formatRelativeAlloc` function
- `src/display.zig` - Calls `formatRelativeAlloc` without freeing
- `src/commands/*.zig` - Commands that call `renderTaskDetail`

### Resolution Target
Phase 7: Polish - Will be addressed when refactoring display utilities for better error handling.
