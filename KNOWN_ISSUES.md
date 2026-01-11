# Known Issues

## Memory Leak: formatRelativeAlloc

### Status
**RESOLVED** - Fixed in Phase 7 by implementing `formatRelativeToWriter()` function that writes directly to a writer instead of allocating strings.

### Resolution Details
Added `formatRelativeToWriter()` in `packages/tasks-cli/src/utils.zig` and updated `packages/tasks-cli/src/display.zig` to use it. This eliminates the allocation entirely, preventing the memory leak.

### Related Files
- `packages/tasks-cli/src/utils.zig` - Added `formatRelativeToWriter` function
- `packages/tasks-cli/src/display.zig` - Updated to use `formatRelativeToWriter`

## Title Truncation Lacks Ellipsis

### Status
**RESOLVED** - `truncateWithEllipsis()` now appends `...` when titles are shortened.

### Impact
Long titles in the task list are cut to fit the column width, but users cannot tell the title was truncated.

### Related Files
- `packages/tasks-cli/src/utils.zig` - `truncateWithEllipsis()` now writes ellipsis into a buffer
- `packages/tasks-cli/src/display.zig` - Uses buffered `truncateWithEllipsis()` for table output
