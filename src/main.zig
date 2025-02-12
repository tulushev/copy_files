const builtin = @import("builtin");
const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const parsed = try parse_arguments(allocator);

    const output_string = try copy_files_in_dir(allocator, parsed.folder_path, parsed.allowed_patterns);

    try copy_to_clipboard(allocator, output_string);
}

fn parse_arguments(allocator: std.mem.Allocator) !struct { allowed_patterns: [][:0]u8, folder_path: [:0]u8 } {
    const args = try std.process.argsAlloc(allocator);

    if (args.len < 3) return error.ExpectedArgument;

    const folder_path: [:0]u8 = try std.mem.Allocator.dupeZ(allocator, u8, args[1]);

    var allowed_patterns = try allocator.alloc([:0]u8, args.len - 2);
    for (args[2..], 0..) |pattern, i| {
        allowed_patterns[i] = try std.mem.Allocator.dupeZ(allocator, u8, pattern);
    }

    return .{ .allowed_patterns = allowed_patterns, .folder_path = folder_path };
}

fn copy_files_in_dir(allocator: std.mem.Allocator, folder_path: [:0]u8, allowed_patterns: [][:0]u8) ![]u8 {
    var output_string = std.ArrayList(u8).init(allocator);

    var dir = try std.fs.openDirAbsoluteZ(folder_path, .{ .access_sub_paths = true, .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    file_loop: while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const real_file_extension = std.fs.path.extension(entry.path);
            const real_file_stem = std.fs.path.stem(entry.path);
            const full_file_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ real_file_stem, real_file_extension });

            for (allowed_patterns) |pattern| {
                const extension_with_dot = try std.fmt.allocPrint(allocator, ".{s}", .{pattern});
                const is_any_file_name_allowed = std.mem.eql(u8, pattern, "any");
                const file_name_pattern_matches = std.mem.eql(u8, pattern, full_file_name);
                const extension_pattern_matches = real_file_extension.len != 0 and std.mem.eql(u8, real_file_extension, extension_with_dot);

                if (is_any_file_name_allowed or file_name_pattern_matches or extension_pattern_matches) {
                    var file = try dir.openFile(entry.path, .{});
                    defer file.close();

                    const file_contents = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);

                    const header = try std.fmt.allocPrint(allocator, "{s}\n```\n", .{entry.path});
                    try output_string.appendSlice(header);
                    try output_string.appendSlice(file_contents);
                    try output_string.appendSlice("\n````\n\n");

                    continue :file_loop;
                }
            }
        }
    }

    return output_string.items;
}

fn copy_to_clipboard(allocator: std.mem.Allocator, text: []const u8) !void {
    const cmd_and_args = switch (builtin.target.os.tag) {
        .macos => &[_][]const u8{"pbcopy"},
        .linux => &[_][]const u8{"wl-copy"},
        else => return error.UnsupportedPlatform,
    };

    var proc = std.process.Child.init(
        cmd_and_args,
        allocator,
    );
    proc.stdin_behavior = .Pipe;
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;

    try proc.spawn();
    if (proc.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
        proc.stdin = null;
        const term = try proc.wait();
        if (term != .Exited or term.Exited != 0) {
            return error.ClipboardCommandFailed;
        }
    } else {
        return error.NoStdinForClipboard;
    }
}
