# Known Issues

## Memory Leak: formatRelativeAlloc

### Status
**RESOLVED** - Fixed in Phase 7 by implementing `formatRelativeToWriter()` function that writes directly to a writer instead of allocating strings.

### Resolution Details
Added `formatRelativeToWriter()` in `src/utils.zig` and updated `src/display.zig` to use it. This eliminates the allocation entirely, preventing the memory leak.

### Related Files
- `src/utils.zig` - Added `formatRelativeToWriter` function
- `src/display.zig` - Updated to use `formatRelativeToWriter`

