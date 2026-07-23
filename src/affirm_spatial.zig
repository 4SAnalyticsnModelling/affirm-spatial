const std = @import("std");
const batch = @import("batch.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const opts = try parseArgs(allocator, init.minimal.args);
    defer {
        allocator.free(opts.input_path);
        allocator.free(opts.output_path);
        allocator.free(opts.log_path);
    }

    try batch.run(allocator, init.io, opts);
}

fn parseArgs(allocator: std.mem.Allocator, process_args: std.process.Args) !batch.Options {
    var input_path: ?[]const u8 = null;
    errdefer if (input_path) |p| allocator.free(p);
    var output_path: ?[]const u8 = null;
    errdefer if (output_path) |p| allocator.free(p);
    var log_path: ?[]const u8 = null;
    errdefer if (log_path) |p| allocator.free(p);
    var threads: usize = 1;

    var args = try std.process.Args.Iterator.initAllocator(process_args, allocator);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--input")) {
            input_path = try allocator.dupe(u8, args.next() orelse return error.MissingArgument);
        } else if (std.mem.eql(u8, arg, "--output")) {
            output_path = try allocator.dupe(u8, args.next() orelse return error.MissingArgument);
        } else if (std.mem.eql(u8, arg, "--log")) {
            log_path = try allocator.dupe(u8, args.next() orelse return error.MissingArgument);
        } else if (std.mem.eql(u8, arg, "--threads")) {
            const value = args.next() orelse return error.MissingArgument;
            threads = if (std.mem.eql(u8, value, "auto")) try std.Thread.getCpuCount() else try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try usage();
            std.process.exit(0);
        } else {
            return error.UnknownArgument;
        }
    }

    const out = output_path orelse return error.MissingOutput;
    if (log_path == null) {
        const dirname = std.fs.path.dirname(out) orelse ".";
        log_path = try std.fs.path.join(allocator, &.{ dirname, "AFFIRM-batch-logfile" });
    }

    return .{
        .input_path = input_path orelse return error.MissingInput,
        .output_path = out,
        .log_path = log_path.?,
        .threads = @max(threads, 1),
    };
}

fn usage() !void {
    std.debug.print(
        \\Usage:
        \\  affirm_spatial --input FILE --output FILE [--log FILE] [--threads auto|N]
        \\
    , .{});
}

const testing = std.testing;

// std.process.Args.Vector on Windows is the raw WTF-16 command line (as returned by
// GetCommandLineW), not a pre-split argv array, so a synthetic one is built the same way
// std's own Args.Iterator.Windows tests do: encode a command-line string as WTF-16.
// parseArgs always skips element 0 (the executable name), matching real process args.
fn testParseArgs(allocator: std.mem.Allocator, cmd_line: []const u8) !batch.Options {
    const wtf16 = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, cmd_line);
    defer allocator.free(wtf16);
    return parseArgs(allocator, .{ .vector = wtf16 });
}

fn freeOptions(allocator: std.mem.Allocator, opts: batch.Options) void {
    allocator.free(opts.input_path);
    allocator.free(opts.output_path);
    allocator.free(opts.log_path);
}

test "parseArgs requires --output" {
    try testing.expectError(error.MissingOutput, testParseArgs(testing.allocator, "affirm_spatial.exe --input in.txt"));
}

test "parseArgs requires --input" {
    try testing.expectError(error.MissingInput, testParseArgs(testing.allocator, "affirm_spatial.exe --output out.txt"));
}

test "parseArgs rejects an unknown flag" {
    const allocator = testing.allocator;
    try testing.expectError(error.UnknownArgument, testParseArgs(allocator, "affirm_spatial.exe --bogus"));
}

test "parseArgs requires a value after --threads" {
    try testing.expectError(error.MissingArgument, testParseArgs(testing.allocator, "affirm_spatial.exe --input in.txt --output out.txt --threads"));
}

test "parseArgs resolves --threads auto to a positive count" {
    const allocator = testing.allocator;
    const opts = try testParseArgs(allocator, "affirm_spatial.exe --input in.txt --output out.txt --threads auto");
    defer freeOptions(allocator, opts);
    try testing.expect(opts.threads >= 1);
    try testing.expectEqual(try std.Thread.getCpuCount(), opts.threads);
}

test "parseArgs parses a literal --threads value" {
    const allocator = testing.allocator;
    const opts = try testParseArgs(allocator, "affirm_spatial.exe --input in.txt --output out.txt --threads 4");
    defer freeOptions(allocator, opts);
    try testing.expectEqual(@as(usize, 4), opts.threads);
}

test "parseArgs derives a default log path next to the output file when --log is omitted" {
    const allocator = testing.allocator;
    const opts = try testParseArgs(allocator, "affirm_spatial.exe --input in.txt --output sub/out.txt");
    defer freeOptions(allocator, opts);

    const dirname = std.fs.path.dirname(opts.output_path) orelse ".";
    const expected_log_path = try std.fs.path.join(allocator, &.{ dirname, "AFFIRM-batch-logfile" });
    defer allocator.free(expected_log_path);
    try testing.expectEqualStrings(expected_log_path, opts.log_path);
}

test "parseArgs keeps an explicit --log path" {
    const allocator = testing.allocator;
    const opts = try testParseArgs(allocator, "affirm_spatial.exe --input in.txt --output out.txt --log custom.log");
    defer freeOptions(allocator, opts);
    try testing.expectEqualStrings("custom.log", opts.log_path);
}

// The --help/-h branch calls std.process.exit(0) directly, which would terminate the test
// runner process, so it is intentionally left untested here.
