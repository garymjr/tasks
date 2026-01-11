# tasks

Local-first task CLI. Dependencies, tags, priorities. Single JSON file per directory.

## Highlights

- Task lifecycle: todo, in_progress, done, blocked.
- Priorities: low, medium, high, critical.
- Dependencies with cycle checks and graph view.
- Search, tags, status filters, ready/blocked views.
- Short IDs (prefix) supported for most commands.
- Colored output, optional.

## Requirements

- Zig 0.15

## Install

Build:

```sh
zig build
```

Run from build:

```sh
zig build run -- <args>
```

Install to prefix:

```sh
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

Then run:

```sh
tasks <command>
```

## Quick start

```sh
# initialize storage in the current directory
$ tasks init

# add tasks
$ tasks add "Ship v1" --priority high --tags release,ops
$ tasks add "Write changelog" --tags docs

# link dependencies (child depends on parent)
$ tasks link <child-id> <parent-id>

# see what's ready
$ tasks next

# complete a task
$ tasks done <id>

# list everything
$ tasks list
```

## Command map

General:

- `tasks help` or `tasks help <command>` for full usage.
- `--no-color` disables ANSI color output on supported commands.
- `--json` outputs machine-readable JSON on output commands.

Core:

- `tasks init` - create `.tasks/` storage in current dir.
- `tasks add <title> [--body text] [--priority p] [--tags a,b]`
- `tasks list [--status s] [--priority p] [--tags tag] [--blocked|--unblocked]`
- `tasks show <id>`
- `tasks edit <id> [--title t] [--body b] [--status s] [--priority p] [--tags a,b]`
- `tasks delete <id>`
- `tasks done <id>`

Workflow:

- `tasks block <id>` / `tasks unblock <id>`
- `tasks next [--all]`
- `tasks search <query>`
- `tasks stats`

Dependencies:

- `tasks link <child> <parent>`
- `tasks unlink <child> <parent>`
- `tasks graph <id> [--reverse]`

Tags:

- `tasks tag <id> <tag>`
- `tasks untag <id> <tag>`
- `tasks tags`

## Status and priority

- Status: `todo`, `in_progress`, `done`, `blocked`.
- Priority: `low`, `medium`, `high`, `critical`.
- `tasks block` sets status to `blocked`.
- `tasks list --blocked` is dependency-based (not status-based). It shows tasks that are blocked by unmet dependencies.

## Dependencies and blocking

- `tasks link child parent` means child depends on parent.
- Cycles are rejected.
- `tasks graph <id>` shows dependency tree.
- `tasks graph <id> --reverse` shows tasks blocked by the given task.
- A task is "ready" when all dependencies are `done` and status is `todo`.

## IDs and matching

- Commands accept full UUIDs or short prefixes.
- Short IDs match the first 1-8 characters of the UUID.
- If a prefix is ambiguous, the first match wins. Prefer 8 chars.

## Data storage

- Stored in the current directory at `.tasks/tasks.json`.
- File lock at `.tasks/tasks.lock` during writes.
- Safe to delete `.tasks/` to reset; data is gone.

## Development

Run tests:

```sh
zig build test
```

Build/run with args:

```sh
zig build run -- list --status todo
```

## Known issues

See `KNOWN_ISSUES.md`.
