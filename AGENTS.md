# AGENTS

## Build / Lint / Test

Build + run:

```sh
zig build
zig build run -- <args>
```

Tests:

```sh
zig build test
zig test src/model.zig
zig test src/model.zig --test-filter "taskstore add and find"
```

Formatting (no dedicated lint step):

```sh
zig fmt src/*.zig src/commands/*.zig
```

## Code Style

- Module system: Zig `@import()` with `.zig` files; root module `src/root.zig`.
- Imports: `const std = @import("std");` and `const module = @import("file.zig");` at top.
- Formatting: `zig fmt` output; 4-space indent; braces on same line.
- Strings: double quotes; multiline via `\\` escape sequences when needed.
- Types: explicit structs/enums; allocator passed explicitly (`std.mem.Allocator`).
- Naming: files `lower_snake_case.zig`, types `PascalCase`, functions/vars `lowerCamelCase`, consts `UPPER_SNAKE_CASE`.
- Error handling: error unions with `try`; `catch |err|` + `switch` for mapping to user messages.
- Testing: `test "name" {}` blocks inline with source files; run via `zig build test` or `zig test` on a file.

## Existing Rules

- Cursor rules: none found (`.cursor/rules` / `.cursorrules`).
- Copilot instructions: none found (`.github/copilot-instructions.md`).

## Architecture Overview

- `src/main.zig`: executable entrypoint; sets allocator and calls CLI.
- `src/root.zig`: library module exports (`cli`, `model`, `utils`).
- `src/cli.zig`: CLI wiring, argparse command tree, error mapping.
- `src/commands/`: one file per command (`add`, `list`, `show`, `done`, etc.).
- `src/model.zig`: core domain types (Task, TaskStore, enums) and logic.
- `src/store.zig`: JSON persistence to `.tasks/tasks.json` + lock file.
- `src/display.zig`: formatting tables/details for terminal output.
- `src/graph.zig`: dependency graph helpers.
- `src/utils.zig`: shared helpers (timestamps, string ops).

## Other Helpful Info

- Dependencies: `argparse` Zig package (see `build.zig.zon`).
- Data layout: `.tasks/tasks.json` + `.tasks/tasks.lock` in working directory.
- Workflow: add new commands in `src/commands/`, export in `src/commands/mod.zig`, wire into `src/cli.zig`.
