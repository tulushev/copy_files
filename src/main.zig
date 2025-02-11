const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) return error.ExpectedArgument;

    const allowed_patterns = args[2..];

    const folder = args[1];

    var dir = try std.fs.openDirAbsoluteZ(folder, .{ .access_sub_paths = true, .iterate = true });
    defer dir.close();

    var output_string = std.ArrayList(u8).init(allocator);
    defer output_string.deinit();

    try copy_file_contents_in_dir(&allocator, &dir, allowed_patterns, &output_string);

    try write(output_string.items);
}

fn copy_file_contents_in_dir(allocator: *std.mem.Allocator, dir: *const std.fs.Dir, allowed_patterns: [][:0]u8, output_string: *std.ArrayList(u8)) !void {
    var walker = try dir.walk(allocator.*);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            var should_read = false;
            for (allowed_patterns) |pattern| {
                const real_file_extension = std.fs.path.extension(entry.path);
                const real_file_stem = std.fs.path.stem(entry.path);
                const extension_with_dot = try std.fmt.allocPrint(allocator.*, ".{s}", .{pattern});
                const full_file_name = try std.fmt.allocPrint(allocator.*, "{s}{s}", .{ real_file_stem, real_file_extension });
                if (std.mem.eql(u8, pattern, "any")) {
                    should_read = true;
                } else if (std.mem.eql(u8, pattern, full_file_name)) {
                    should_read = true;
                } else if (real_file_extension.len != 0 and std.mem.eql(u8, real_file_extension, extension_with_dot)) {
                    should_read = true;
                }
            }
            if (should_read) {
                var file = try dir.openFile(entry.path, .{});
                defer file.close();

                const file_contents = try file.readToEndAlloc(allocator.*, 1024 * 1024 * 1024);
                defer allocator.free(file_contents);

                const header = try std.fmt.allocPrint(allocator.*, "{s}\n```\n", .{entry.path});
                try output_string.appendSlice(header);
                try output_string.appendSlice(file_contents);
                try output_string.appendSlice("\n````\n\n");
            }
        }
    }
}

fn write(text: []const u8) !void {
    var proc = std.process.Child.init(
        &[_][]const u8{"pbcopy"},
        std.heap.page_allocator,
    );
    proc.stdin_behavior = .Pipe;
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;

    try proc.spawn();
    try proc.stdin.?.writeAll(text);
    proc.stdin.?.close();
    proc.stdin = null;
    const term = proc.wait() catch unreachable;
    if (term != .Exited or term.Exited != 0) unreachable;
}
