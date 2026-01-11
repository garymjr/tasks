prefix := "~/.local"

default: build

build:
    zig build

run *args:
    zig build run -- {{args}}

install PREFIX=prefix:
    zig build -Doptimize=ReleaseSafe --prefix {{PREFIX}}

test:
    zig build test
