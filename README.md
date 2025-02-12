# Copy Files To LLM

Give it a directory and some file extensions and it will copy all the file contents into clipboard. It makes sure to name each file and adds quotes for LLM to understand where each file starts and ends.

## Prerequisites

- macOS and Linux Wayland only right now
- Zig language. You can install [here](https://ziglang.org/learn/getting-started/)

## Usage

```shell
zig build run -- /absolute/path/to/dir toml rs justfile
```

This will recursively copy the contents of all files with `.rs` extension, `.toml` extension and files named `justfile` into clipboard. 
