# Known Issues

## Memory Leak: formatRelativeAlloc

### Status
**RESOLVED** - Fixed in Phase 7 by implementing `formatRelativeToWriter()` function that writes directly to a writer instead of allocating strings.

### Resolution Details
Added `formatRelativeToWriter()` in `src/utils.zig` and updated `src/display.zig` to use it. This eliminates the allocation entirely, preventing the memory leak.

### Related Files
- `src/utils.zig` - Added `formatRelativeToWriter` function
- `src/display.zig` - Updated to use `formatRelativeToWriter`

## Title Truncation Lacks Ellipsis

### Status
**OPEN** - `truncateWithEllipsis()` truncates without adding `...`, so shortened titles in tables lack visual indication.

### Impact
Long titles in the task list are cut to fit the column width, but users cannot tell the title was truncated.

### Related Files
- `src/utils.zig` - `truncateWithEllipsis()`
- `src/display.zig` - Uses `truncateWithEllipsis()` in table output

