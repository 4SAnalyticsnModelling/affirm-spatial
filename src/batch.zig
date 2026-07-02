const std = @import("std");
const Coefficients = @import("coefficients.zig").Coefficients;
const input_parser = @import("input.zig");
const model = @import("model.zig");
const types = @import("types.zig");

pub const Options = struct {
    input_path: []const u8,
    output_path: []const u8,
    log_path: []const u8,
    threads: usize,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    const input_bytes = try std.Io.Dir.cwd().readFileAlloc(io, opts.input_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(input_bytes);

    var scenarios = std.array_list.Managed(types.InputScenario).init(allocator);
    defer {
        for (scenarios.items) |*scenario| scenario.deinit(allocator);
        scenarios.deinit();
    }

    var lines = std.mem.splitScalar(u8, input_bytes, '\n');
    _ = lines.next();
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        try scenarios.append(try input_parser.parseScenario(allocator, line));
    }

    var output_file = try std.Io.Dir.cwd().createFile(io, opts.output_path, .{ .truncate = true });
    defer output_file.close(io);
    var log_file = try std.Io.Dir.cwd().createFile(io, opts.log_path, .{ .truncate = true });
    defer log_file.close(io);

    var output_buffer: [64 * 1024]u8 = undefined;
    var log_buffer: [16 * 1024]u8 = undefined;
    var output_writer = output_file.writer(io, &output_buffer);
    var log_writer = log_file.writer(io, &log_buffer);
    const writer = &output_writer.interface;
    const log = &log_writer.interface;

    try writeHeader(writer);

    const thread_count = @max(@as(usize, 1), @min(opts.threads, scenarios.items.len));
    if (thread_count == 1) {
        for (scenarios.items, 0..) |*scenario, i| {
            try model.evaluateScenario(.{ .allocator = allocator, .coeffs = &coeffs, .writer = writer, .log = log }, scenario, i + 2);
        }
    } else {
        const per_thread = try allocator.alloc(ThreadOutput, thread_count);
        defer allocator.free(per_thread);
        var threads = try allocator.alloc(std.Thread, thread_count);
        defer allocator.free(threads);

        for (per_thread, 0..) |*slot, i| {
            slot.* = .{ .allocator = allocator, .coeffs = &coeffs, .scenarios = scenarios.items, .start = i * scenarios.items.len / thread_count, .end = (i + 1) * scenarios.items.len / thread_count, .output = std.Io.Writer.Allocating.init(allocator), .log = std.Io.Writer.Allocating.init(allocator), .err = null };
            threads[i] = try std.Thread.spawn(.{}, worker, .{slot});
        }
        for (threads) |thread| thread.join();
        for (per_thread) |*slot| {
            defer slot.output.deinit();
            defer slot.log.deinit();
            if (slot.err) |err| return err;
            try writer.writeAll(slot.output.written());
            try log.writeAll(slot.log.written());
        }
    }
    try log.writeAll("Success: AFFIRM Spatial model run has completed successfully.\n");
    try writer.flush();
    try log.flush();
}

const ThreadOutput = struct {
    allocator: std.mem.Allocator,
    coeffs: *const Coefficients,
    scenarios: []types.InputScenario,
    start: usize,
    end: usize,
    output: std.Io.Writer.Allocating,
    log: std.Io.Writer.Allocating,
    err: ?anyerror,
};

fn worker(slot: *ThreadOutput) void {
    const out_writer = &slot.output.writer;
    const log_writer = &slot.log.writer;
    for (slot.scenarios[slot.start..slot.end], slot.start..) |*scenario, i| {
        model.evaluateScenario(.{ .allocator = slot.allocator, .coeffs = slot.coeffs, .writer = out_writer, .log = log_writer }, scenario, i + 2) catch |err| {
            slot.err = err;
            return;
        };
    }
}

fn writeHeader(writer: *std.Io.Writer) !void {
    try writer.writeAll("Index\tTownship\tRange\tMeridian\tSoil Zone\tSoil organic matter (0-6\") (%)\tSoil texture\tSpring soil moisture\tSoil pH (0-6\" or 0-12\")\tSoil EC (0-6\" or 0-12\") (mS/cm)\tCrop\tIrrigation\tGrowing season moisture flag\tGrowing season precipitation (May-Aug) + irrigation (if any) (mm)\tNitrogen fertilizer product\tNitrogen fertilizer application timing\tNitrogen fertilizer application placement\tSoil test nitrogen (0-24\") (lb N/ac)\tPrevious crop\tPrevious crop yield\tPrevious crop yield unit\tResidue management\tCrop available nitrogen from applied manure (lb N/ac)\tExpected crop price ($/bu)\tFertilizer price ($/tonne)\tUser chosen investment ratio\tEstimated N release from N mineralization over the growing season (lb N/ac)\tN credit from previous crop residue (lb N/ac)\tTotal plant available nitrogen from soil (lb N/ac)\tFertilizer N application rate (lb N/ac)\tPredicted crop yield (bu/ac)\tPredicted yield increase (bu/ac)\tAdded yield increase (bu/ac)\tEstimated revenue from fertilizer N ($/ac)\tMarginal return or Gross margin change ($/ac)\tTotal cost of fertilizer N ($/ac)\tMarginal cost of fertilizer N ($/ac)\tEstimated Investment Ratio\tRecommended?\tComment\n");
}
