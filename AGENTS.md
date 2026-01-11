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
zig test packages/tasks-core/src/model.zig
zig test packages/tasks-core/src/model.zig --test-filter "taskstore add and find"
```

Formatting (no dedicated lint step):

```sh
zig fmt packages/tasks-cli/src/*.zig packages/tasks-cli/src/commands/*.zig
```

## Code Style

- Module system: Zig `@import()` with `.zig` files; CLI root module `packages/tasks-cli/src/root.zig`.
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

- `packages/tasks-cli/src/main.zig`: executable entrypoint; sets allocator and calls CLI.
- `packages/tasks-cli/src/root.zig`: library module exports (`cli`, `json`, `utils`).
- `packages/tasks-cli/src/cli.zig`: CLI wiring, argparse command tree, error mapping.
- `packages/tasks-cli/src/commands/`: one file per command (`add`, `list`, `show`, `done`, etc.).
- `packages/tasks-core/src/model.zig`: core domain types (Task, TaskStore, enums) and logic.
- `packages/tasks-store-json/src/store.zig`: JSON persistence to `.tasks/tasks.json` + lock file.
- `packages/tasks-render/src/display.zig`: formatting tables/details for terminal output.
- `packages/tasks-core/src/graph.zig`: dependency graph helpers.
- `packages/tasks-cli/src/utils.zig`: shared helpers (timestamps, string ops).

## Other Helpful Info

- Dependencies: `argparse` Zig package (see `build.zig.zon`).
- Data layout: `.tasks/tasks.json` + `.tasks/tasks.lock` in working directory.
- Workflow: add new commands in `packages/tasks-cli/src/commands/`, export in `packages/tasks-cli/src/commands/mod.zig`, wire into `packages/tasks-cli/src/cli.zig`.
