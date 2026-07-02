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
    var output_path: ?[]const u8 = null;
    var log_path: ?[]const u8 = null;
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
