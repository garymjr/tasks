# argparse usage

## Builder API

```zig
const argparse = @import("argparse");

var builder = argparse.Builder.init(allocator);
defer builder.deinit();

try builder
    .addFlag("verbose", 'v', "verbose", "Enable verbose output")
    .addOptionWith("count", 'c', "count", .int, "Number of items", .{ .required = true })
    .addPositional("input", .string, "Input file");

var parser = try builder.build();
defer parser.deinit();
try parser.parse(argv);
```

## Error formatting

```zig
const err = parser.parse(argv) catch |e| e;
const message = try parser.formatError(allocator, err, .{ .color = .auto });
defer allocator.free(message);
std.debug.print("{s}\n", .{message});
```

## Comptime validation

```zig
const args = [_]argparse.Arg{
    .{ .name = "count", .short = 'c', .long = "count", .kind = .option },
};

argparse.validateArgsComptime(&args);
```

## Benchmarks

```
zig build bench
```
