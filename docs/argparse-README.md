# argparse

Type-safe command-line argument parsing for Zig, zero allocation by default.

## Features

- Flags, options, counts, positionals, multi-values
- Comptime validation for argument definitions
- Builder API for fluent setup
- Subcommands with per-command help
- Colorized help and error formatting

## Install

```sh
zig fetch --save https://github.com/garymjr/argparse
```

```zig
const argparse_dep = b.dependency("argparse", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("argparse", argparse_dep.module("argparse"));
```

## Quick Start

```zig
const std = @import("std");
const argparse = @import("argparse");

const args = [_]argparse.Arg{
    .{ .name = "verbose", .short = 'v', .long = "verbose", .kind = .flag },
    .{ .name = "count", .short = 'c', .long = "count", .kind = .option, .value_type = .int },
    .{ .name = "input", .kind = .positional, .position = 0 },
};

var parser = try argparse.Parser.init(allocator, &args);
try parser.parse(argv);

const verbose = parser.getFlag("verbose");
const count = try parser.getInt("count");
const input = parser.getPositional("input") orelse "-";
```

## Builder API

```zig
var builder = argparse.Builder.init(allocator);
defer builder.deinit();

try builder
    .addFlag("verbose", 'v', "verbose", "Enable verbose output")
    .addOptionWith("count", 'c', "count", .int, "Number of items", .{ .required = true })
    .addPositional("input", .string, "Input file");

var parser = try builder.build();
```

## Subcommands

```zig
const app = argparse.Command{
    .name = "tool",
    .subcommands = &[_]argparse.Command{
        .{
            .name = "run",
            .help = "Run the task",
            .args = &[_]argparse.Arg{
                .{ .name = "mode", .short = 'm', .long = "mode", .kind = .option, .value_type = .string },
            },
        },
    },
};

try app.run(allocator, argv);
```

## Errors and Help

```zig
parser.parse(argv) catch |err| {
    if (err == argparse.Error.ShowHelp) {
        const help = try parser.help();
        defer allocator.free(help);
        std.debug.print("{s}", .{help});
        return;
    }

    const message = try parser.formatError(allocator, err, .{});
    defer allocator.free(message);
    std.debug.print("{s}\n", .{message});
    return err;
};
```

## API Overview

- `Arg`: argument definition (`name`, `short`, `long`, `kind`, `value_type`, `required`).
- `Parser`: `init`, `initWithConfig`, `parse`, `get*` accessors, `help`, `formatError`.
- `Builder`: `addFlag`, `addOption`, `addPositional`, `build`.
- `Command`: `run`, `helpFor`, `helpText`, `formatError`.
- `HelpConfig`: customize usage, widths, description, color mode.
- `Error`: parse error set (`UnknownArgument`, `MissingValue`, `MissingRequired`, `InvalidValue`, `UnknownCommand`, `ShowHelp`).

## Examples

- `examples/simple.zig`
- `examples/builder.zig`
- `examples/subcommands.zig`

## More Docs

- `docs/usage.md`
