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

    var input_file = try std.Io.Dir.cwd().openFile(io, opts.input_path, .{});
    defer input_file.close(io);
    // A fixed-size line buffer instead of reading the whole file into memory up front:
    // peak memory for the raw input no longer scales with file size, only with the
    // longest single row, which this comfortably bounds for any realistic scenario row.
    var input_read_buffer: [64 * 1024]u8 = undefined;
    var input_reader = input_file.reader(io, &input_read_buffer);
    const input = &input_reader.interface;

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

    var scenarios = std.array_list.Managed(types.InputScenario).init(allocator);
    defer {
        for (scenarios.items) |*scenario| scenario.deinit(allocator);
        scenarios.deinit();
    }
    var row_numbers = std.array_list.Managed(usize).init(allocator);
    defer row_numbers.deinit();

    var line_number: usize = 0;
    var is_header = true;
    while (true) {
        line_number += 1;
        const raw = input.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try log.print("Error: Could not parse the scenario at row {d} of your input file (row exceeds the maximum supported line length). No output was written for this scenario.\n", .{line_number});
                _ = input.discardDelimiterInclusive('\n') catch |discard_err| switch (discard_err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                };
                continue;
            },
            error.ReadFailed => return err,
        } orelse break;

        if (is_header) {
            is_header = false;
            continue;
        }
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        const scenario = input_parser.parseScenario(allocator, line) catch |err| {
            try log.print("Error: Could not parse the scenario at row {d} of your input file ({s}). No output was written for this scenario.\n", .{ line_number, @errorName(err) });
            continue;
        };
        try scenarios.append(scenario);
        try row_numbers.append(line_number);
    }

    const thread_count = @max(@as(usize, 1), @min(opts.threads, scenarios.items.len));
    if (thread_count == 1) {
        for (scenarios.items, row_numbers.items) |*scenario, row_number| {
            try model.evaluateScenario(.{ .allocator = allocator, .coeffs = &coeffs, .writer = writer, .log = log }, scenario, row_number);
        }
    } else {
        try runMultiThreaded(allocator, io, &coeffs, scenarios.items, row_numbers.items, thread_count, opts.output_path, writer, log);
    }
    try log.writeAll("Success: AFFIRM Spatial model run has completed successfully.\n");
    try writer.flush();
    try log.flush();
}

/// Each thread streams its rows straight to its own temp file through a small fixed
/// buffer instead of accumulating its whole share of output/log text in memory (which
/// previously scaled with total output size and was held twice: once per thread and
/// again when copied into the final writer). After the threads join, each temp file is
/// streamed into the final writer/log in thread order through a bounded copy buffer, so
/// peak memory stays flat regardless of how much output a run produces.
fn runMultiThreaded(allocator: std.mem.Allocator, io: std.Io, coeffs: *const Coefficients, scenarios: []types.InputScenario, row_numbers: []const usize, thread_count: usize, output_path: []const u8, writer: *std.Io.Writer, log: *std.Io.Writer) !void {
    const per_thread = try allocator.alloc(ThreadOutput, thread_count);
    defer allocator.free(per_thread);
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var spawned: usize = 0;
    defer {
        for (per_thread[0..spawned]) |*slot| {
            slot.output_file.close(io);
            slot.log_file.close(io);
            std.Io.Dir.cwd().deleteFile(io, slot.output_tmp_path) catch {};
            std.Io.Dir.cwd().deleteFile(io, slot.log_tmp_path) catch {};
            allocator.free(slot.output_tmp_path);
            allocator.free(slot.log_tmp_path);
        }
    }

    for (per_thread, 0..) |*slot, i| {
        const output_tmp_path = try std.fmt.allocPrint(allocator, "{s}.thread{d}.tmp", .{ output_path, i });
        errdefer allocator.free(output_tmp_path);
        const log_tmp_path = try std.fmt.allocPrint(allocator, "{s}.thread{d}.log.tmp", .{ output_path, i });
        errdefer allocator.free(log_tmp_path);
        // read = true so the same handle used to write each temp file can be reused to
        // stream it back out afterwards without a separate open-for-read syscall round trip.
        const output_file = try std.Io.Dir.cwd().createFile(io, output_tmp_path, .{ .truncate = true, .read = true });
        errdefer {
            output_file.close(io);
            std.Io.Dir.cwd().deleteFile(io, output_tmp_path) catch {};
        }
        const log_file = try std.Io.Dir.cwd().createFile(io, log_tmp_path, .{ .truncate = true, .read = true });
        errdefer {
            log_file.close(io);
            std.Io.Dir.cwd().deleteFile(io, log_tmp_path) catch {};
        }

        slot.* = .{
            .allocator = allocator,
            .coeffs = coeffs,
            .scenarios = scenarios,
            .row_numbers = row_numbers,
            .start = i * scenarios.len / thread_count,
            .end = (i + 1) * scenarios.len / thread_count,
            .io = io,
            .output_file = output_file,
            .log_file = log_file,
            .output_tmp_path = output_tmp_path,
            .log_tmp_path = log_tmp_path,
            .err = null,
        };
        spawned += 1;
        threads[i] = try std.Thread.spawn(.{}, worker, .{slot});
    }
    for (threads) |thread| thread.join();

    var copy_buffer: [64 * 1024]u8 = undefined;
    for (per_thread) |*slot| {
        if (slot.err) |err| return err;

        var output_reader = slot.output_file.reader(io, &copy_buffer);
        _ = try output_reader.interface.streamRemaining(writer);
        var log_reader = slot.log_file.reader(io, &copy_buffer);
        _ = try log_reader.interface.streamRemaining(log);
    }
}

const ThreadOutput = struct {
    allocator: std.mem.Allocator,
    coeffs: *const Coefficients,
    scenarios: []types.InputScenario,
    row_numbers: []const usize,
    start: usize,
    end: usize,
    io: std.Io,
    output_file: std.Io.File,
    log_file: std.Io.File,
    output_tmp_path: []const u8,
    log_tmp_path: []const u8,
    err: ?anyerror,
};

fn worker(slot: *ThreadOutput) void {
    var output_buffer: [64 * 1024]u8 = undefined;
    var log_buffer: [16 * 1024]u8 = undefined;
    var output_writer = slot.output_file.writer(slot.io, &output_buffer);
    var log_writer = slot.log_file.writer(slot.io, &log_buffer);
    for (slot.scenarios[slot.start..slot.end], slot.row_numbers[slot.start..slot.end]) |*scenario, row_number| {
        model.evaluateScenario(.{ .allocator = slot.allocator, .coeffs = slot.coeffs, .writer = &output_writer.interface, .log = &log_writer.interface }, scenario, row_number) catch |err| {
            slot.err = err;
            return;
        };
    }
    output_writer.interface.flush() catch |err| {
        slot.err = err;
        return;
    };
    log_writer.interface.flush() catch |err| {
        slot.err = err;
        return;
    };
}

fn writeHeader(writer: *std.Io.Writer) !void {
    try writer.writeAll("Index\tTownship\tRange\tMeridian\tSoil Zone\tSoil organic matter (0-6\") (%)\tSoil texture\tSpring soil moisture\tSoil pH (0-6\" or 0-12\")\tSoil EC (0-6\" or 0-12\") (mS/cm)\tCrop\tIrrigation\tGrowing season moisture flag\tGrowing season precipitation (May-Aug) + irrigation (if any) (mm)\tNitrogen fertilizer product\tNitrogen fertilizer application timing\tNitrogen fertilizer application placement\tSoil test nitrogen (0-24\") (lb N/ac)\tPrevious crop\tPrevious crop yield\tPrevious crop yield unit\tResidue management\tCrop available nitrogen from applied manure (lb N/ac)\tExpected crop price ($/bu)\tFertilizer price ($/tonne)\tUser chosen investment ratio\tEstimated N release from N mineralization over the growing season (lb N/ac)\tN credit from previous crop residue (lb N/ac)\tTotal plant available nitrogen from soil (lb N/ac)\tFertilizer N application rate (lb N/ac)\tPredicted crop yield (bu/ac)\tPredicted yield increase (bu/ac)\tAdded yield increase (bu/ac)\tEstimated revenue from fertilizer N ($/ac)\tMarginal return or Gross margin change ($/ac)\tTotal cost of fertilizer N ($/ac)\tMarginal cost of fertilizer N ($/ac)\tEstimated Investment Ratio\tRecommended?\tComment\n");
}

const testing = std.testing;

// A single scenario at an invalid legal land location: parses successfully and reaches
// evaluateScenario, but never matches real coefficient data, so it only ever logs an
// error and never writes an output row. That keeps this test independent of the real
// embedded coefficient tables while still exercising the full run() pipeline.
const fixture_header = "Index\tTownship\tRange\tMeridian\tSom\tTexture\tSpring\tpH\tEC\tCrop\tIrrig\tPrecip\tIrrigAmt\tSource\tTime\tPlace\tSoilTestN\tPrevCrop\tPrevYield\tPrevYieldUnit\tResidue\tManureN\tCropPrice\tFertPrice\tInvestRatio\n";
const fixture_row = "1\t9999\t1\tW1\t2\t1\t1\t6.5\t0.2\t1\t1\t\t \t1\t1\t1\t20\t1\t10\t1\t1\t0\t8\t700\t2\n";
const fixture_row_2 = "2\t9998\t1\tW1\t2\t1\t1\t6.5\t0.2\t1\t1\t\t \t1\t1\t1\t20\t1\t10\t1\t1\t0\t8\t700\t2\n";

fn writeFixtureInput(dir: std.Io.Dir, sub_path: []const u8, rows: []const u8) !void {
    var file = try dir.createFile(testing.io, sub_path, .{ .truncate = true });
    defer file.close(testing.io);
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(testing.io, &buffer);
    try writer.interface.writeAll(fixture_header);
    try writer.interface.writeAll(rows);
    try writer.interface.flush();
}

fn dirSubPath(tmp: std.testing.TmpDir, allocator: std.mem.Allocator, file_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path[0..], file_name });
}

test "run: single-threaded, single scenario writes header, error log, and success line" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFixtureInput(tmp.dir, "input.txt", fixture_row);

    const input_path = try dirSubPath(tmp, allocator, "input.txt");
    defer allocator.free(input_path);
    const output_path = try dirSubPath(tmp, allocator, "output.txt");
    defer allocator.free(output_path);
    const log_path = try dirSubPath(tmp, allocator, "log.txt");
    defer allocator.free(log_path);

    try run(allocator, testing.io, .{ .input_path = input_path, .output_path = output_path, .log_path = log_path, .threads = 1 });

    const output_bytes = try tmp.dir.readFileAlloc(testing.io, "output.txt", allocator, .limited(64 * 1024));
    defer allocator.free(output_bytes);
    const log_bytes = try tmp.dir.readFileAlloc(testing.io, "log.txt", allocator, .limited(64 * 1024));
    defer allocator.free(log_bytes);

    try testing.expect(std.mem.startsWith(u8, output_bytes, "Index\tTownship\tRange\tMeridian"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, output_bytes, "\n"));
    try testing.expect(std.mem.indexOf(u8, log_bytes, "Legal land location is not valid") != null);
    try testing.expect(std.mem.endsWith(u8, log_bytes, "Success: AFFIRM Spatial model run has completed successfully.\n"));
}

test "run: multi-threaded run preserves original scenario order in the output" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var rows = std.array_list.Managed(u8).init(allocator);
    defer rows.deinit();
    try rows.appendSlice(fixture_row);
    try rows.appendSlice(fixture_row_2);
    try writeFixtureInput(tmp.dir, "input.txt", rows.items);

    const input_path = try dirSubPath(tmp, allocator, "input.txt");
    defer allocator.free(input_path);
    const output_path = try dirSubPath(tmp, allocator, "output.txt");
    defer allocator.free(output_path);
    const log_path = try dirSubPath(tmp, allocator, "log.txt");
    defer allocator.free(log_path);

    // threads=8 with only 2 scenarios exercises the thread_count clamp to scenarios.items.len.
    try run(allocator, testing.io, .{ .input_path = input_path, .output_path = output_path, .log_path = log_path, .threads = 8 });

    const log_bytes = try tmp.dir.readFileAlloc(testing.io, "log.txt", allocator, .limited(64 * 1024));
    defer allocator.free(log_bytes);

    const first_row_at = std.mem.indexOf(u8, log_bytes, "row 2").?;
    const second_row_at = std.mem.indexOf(u8, log_bytes, "row 3").?;
    try testing.expect(first_row_at < second_row_at);
    try testing.expect(std.mem.endsWith(u8, log_bytes, "Success: AFFIRM Spatial model run has completed successfully.\n"));
}

test "run: a malformed row logs an error and does not shift row numbers for later valid rows" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const malformed_row = "1\tnotanumber\t1\tW1\t2\t1\t1\t6.5\t0.2\t1\t1\t\t \t1\t1\t1\t20\t1\t10\t1\t1\t0\t8\t700\t2\n";
    var rows = std.array_list.Managed(u8).init(allocator);
    defer rows.deinit();
    try rows.appendSlice(malformed_row);
    try rows.appendSlice(fixture_row_2);
    try writeFixtureInput(tmp.dir, "input.txt", rows.items);

    const input_path = try dirSubPath(tmp, allocator, "input.txt");
    defer allocator.free(input_path);
    const output_path = try dirSubPath(tmp, allocator, "output.txt");
    defer allocator.free(output_path);
    const log_path = try dirSubPath(tmp, allocator, "log.txt");
    defer allocator.free(log_path);

    try run(allocator, testing.io, .{ .input_path = input_path, .output_path = output_path, .log_path = log_path, .threads = 1 });

    const log_bytes = try tmp.dir.readFileAlloc(testing.io, "log.txt", allocator, .limited(64 * 1024));
    defer allocator.free(log_bytes);

    try testing.expect(std.mem.indexOf(u8, log_bytes, "Could not parse the scenario at row 2") != null);
    // fixture_row_2 is the third file line (after the header and the malformed row); it must
    // still be reported as row 3, not row 2, even though row 2 never made it into `scenarios`.
    try testing.expect(std.mem.indexOf(u8, log_bytes, "Legal land location is not valid for the scenario at row 3") != null);
    try testing.expect(std.mem.endsWith(u8, log_bytes, "Success: AFFIRM Spatial model run has completed successfully.\n"));
}

test "run: a row longer than the line buffer is logged and skipped without aborting the run" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const oversized_row = try allocator.alloc(u8, 70 * 1024);
    defer allocator.free(oversized_row);
    @memset(oversized_row, 'a');

    var rows = std.array_list.Managed(u8).init(allocator);
    defer rows.deinit();
    try rows.appendSlice(oversized_row);
    try rows.append('\n');
    try rows.appendSlice(fixture_row_2);
    try writeFixtureInput(tmp.dir, "input.txt", rows.items);

    const input_path = try dirSubPath(tmp, allocator, "input.txt");
    defer allocator.free(input_path);
    const output_path = try dirSubPath(tmp, allocator, "output.txt");
    defer allocator.free(output_path);
    const log_path = try dirSubPath(tmp, allocator, "log.txt");
    defer allocator.free(log_path);

    try run(allocator, testing.io, .{ .input_path = input_path, .output_path = output_path, .log_path = log_path, .threads = 1 });

    const log_bytes = try tmp.dir.readFileAlloc(testing.io, "log.txt", allocator, .limited(64 * 1024));
    defer allocator.free(log_bytes);

    try testing.expect(std.mem.indexOf(u8, log_bytes, "row 2 of your input file (row exceeds the maximum supported line length)") != null);
    try testing.expect(std.mem.indexOf(u8, log_bytes, "Legal land location is not valid for the scenario at row 3") != null);
    try testing.expect(std.mem.endsWith(u8, log_bytes, "Success: AFFIRM Spatial model run has completed successfully.\n"));
}

test "run: a header-only input file with no data rows still succeeds" {
    const allocator = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeFixtureInput(tmp.dir, "input.txt", "");

    const input_path = try dirSubPath(tmp, allocator, "input.txt");
    defer allocator.free(input_path);
    const output_path = try dirSubPath(tmp, allocator, "output.txt");
    defer allocator.free(output_path);
    const log_path = try dirSubPath(tmp, allocator, "log.txt");
    defer allocator.free(log_path);

    try run(allocator, testing.io, .{ .input_path = input_path, .output_path = output_path, .log_path = log_path, .threads = 1 });

    const output_bytes = try tmp.dir.readFileAlloc(testing.io, "output.txt", allocator, .limited(64 * 1024));
    defer allocator.free(output_bytes);
    const log_bytes = try tmp.dir.readFileAlloc(testing.io, "log.txt", allocator, .limited(64 * 1024));
    defer allocator.free(log_bytes);

    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, output_bytes, "\n")); // header only
    try testing.expectEqualStrings("Success: AFFIRM Spatial model run has completed successfully.\n", log_bytes);
}
