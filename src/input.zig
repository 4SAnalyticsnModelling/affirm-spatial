const std = @import("std");
const types = @import("types.zig");

pub fn parseScenario(allocator: std.mem.Allocator, line: []const u8) !types.InputScenario {
    var cols = std.array_list.Managed([]const u8).init(allocator);
    defer cols.deinit();
    const delimiter: u8 = if (std.mem.indexOfScalar(u8, line, '\t') != null) '\t' else ',';
    var it = std.mem.splitScalar(u8, line, delimiter);
    while (it.next()) |col| try cols.append(std.mem.trim(u8, col, " \t\r\""));
    if (cols.items.len < 25) return error.InvalidInput;
    const columns = cols.items;

    const index = try std.fmt.parseInt(i64, columns[0], 10);
    const township = try std.fmt.parseInt(types.Id, columns[1], 10);
    const range = try std.fmt.parseInt(types.Id, columns[2], 10);
    const meridian = try parseMeridian(columns[3]);

    // Each allocation below gets its own errdefer immediately after it succeeds. A single
    // `try`'d struct literal would leak every field allocated before the one that fails,
    // since nothing owns those slices yet at the point the literal's evaluation aborts.
    const meridian_text = try allocator.dupe(u8, columns[3]);
    errdefer allocator.free(meridian_text);
    const som = try parseRealList(allocator, columns[4], true);
    errdefer allocator.free(som);
    const soil_texture = try parseIdList(allocator, columns[5]);
    errdefer allocator.free(soil_texture);
    const spring_soil_moisture = try parseIdList(allocator, columns[6]);
    errdefer allocator.free(spring_soil_moisture);
    const soil_ph = try parseRealList(allocator, columns[7], true);
    errdefer allocator.free(soil_ph);
    const soil_ec = try parseRealList(allocator, columns[8], true);
    errdefer allocator.free(soil_ec);
    const current_crop = try std.fmt.parseInt(types.Id, columns[9], 10);
    const irrigation_flag = try std.fmt.parseInt(types.Id, columns[10], 10);
    const precip = try parseOptionalRealList(allocator, columns[11]);
    errdefer allocator.free(precip);
    const irrigation_amount = try parseOptionalRealList(allocator, columns[12]);
    errdefer allocator.free(irrigation_amount);
    const n_source = try std.fmt.parseInt(types.Id, columns[13], 10);
    const n_time = try parseIdList(allocator, columns[14]);
    errdefer allocator.free(n_time);
    const n_place = try parseIdList(allocator, columns[15]);
    errdefer allocator.free(n_place);
    const soil_test_n = try parseRealList(allocator, columns[16], true);
    errdefer allocator.free(soil_test_n);
    const previous_crop = try std.fmt.parseInt(types.Id, columns[17], 10);
    const previous_crop_yield = try parseRealList(allocator, columns[18], true);
    errdefer allocator.free(previous_crop_yield);
    const previous_crop_yield_unit = try std.fmt.parseInt(types.Id, columns[19], 10);
    const residue_management = try parseIdList(allocator, columns[20]);
    errdefer allocator.free(residue_management);
    const manure_n = try parseRealList(allocator, columns[21], true);
    errdefer allocator.free(manure_n);
    const crop_price = try parseRealList(allocator, columns[22], true);
    errdefer allocator.free(crop_price);
    const fertilizer_price = try parseRealList(allocator, columns[23], true);
    errdefer allocator.free(fertilizer_price);
    const investment_ratio = try parseRealList(allocator, columns[24], true);
    errdefer allocator.free(investment_ratio);

    return .{
        .index = index,
        .township = township,
        .range = range,
        .meridian = meridian,
        .meridian_text = meridian_text,
        .som = som,
        .soil_texture = soil_texture,
        .spring_soil_moisture = spring_soil_moisture,
        .soil_ph = soil_ph,
        .soil_ec = soil_ec,
        .current_crop = current_crop,
        .irrigation_flag = irrigation_flag,
        .precip = precip,
        .irrigation_amount = irrigation_amount,
        .n_source = n_source,
        .n_time = n_time,
        .n_place = n_place,
        .soil_test_n = soil_test_n,
        .previous_crop = previous_crop,
        .previous_crop_yield = previous_crop_yield,
        .previous_crop_yield_unit = previous_crop_yield_unit,
        .residue_management = residue_management,
        .manure_n = manure_n,
        .crop_price = crop_price,
        .fertilizer_price = fertilizer_price,
        .investment_ratio = investment_ratio,
    };
}

fn parseMeridian(text: []const u8) !types.Id {
    if (text.len >= 2 and (text[0] == 'W' or text[0] == 'w')) {
        return try std.fmt.parseInt(types.Id, text[1..], 10);
    }
    return try std.fmt.parseInt(types.Id, text, 10);
}

fn parseOptionalRealList(allocator: std.mem.Allocator, text: []const u8) ![]types.ScienceFloat {
    if (text.len == 0 or std.mem.eql(u8, text, "-") or std.ascii.eqlIgnoreCase(text, "na")) {
        return allocator.alloc(types.ScienceFloat, 0);
    }
    return parseRealList(allocator, text, true);
}

fn parseIdList(allocator: std.mem.Allocator, text: []const u8) ![]types.Id {
    var out = std.array_list.Managed(types.Id).init(allocator);
    errdefer out.deinit();
    var it = std.mem.splitScalar(u8, text, '|');
    while (it.next()) |part| try out.append(try std.fmt.parseInt(types.Id, std.mem.trim(u8, part, " \t\r"), 10));
    return out.toOwnedSlice();
}

fn parseRealList(allocator: std.mem.Allocator, text: []const u8, round: bool) ![]types.ScienceFloat {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();
    var it = std.mem.splitScalar(u8, text, '|');
    while (it.next()) |part| try parts.append(std.mem.trim(u8, part, " \t\r"));

    var out = std.array_list.Managed(types.ScienceFloat).init(allocator);
    errdefer out.deinit();

    if (parts.items.len == 4) {
        const mode = try std.fmt.parseInt(u8, parts.items[2], 10);
        if (mode == 1) {
            const low = try std.fmt.parseFloat(types.ScienceFloat, parts.items[0]);
            const high = try std.fmt.parseFloat(types.ScienceFloat, parts.items[1]);
            const step = try std.fmt.parseFloat(types.ScienceFloat, parts.items[3]);
            var value = low;
            while (value <= high + step * 0.001) : (value += step) try out.append(if (round) types.roundDigits(types.ScienceFloat, value, 2) else value);
        } else if (mode == 2 or mode == 3) {
            const count = try std.fmt.parseInt(usize, parts.items[3], 10);
            var prng = std.Random.DefaultPrng.init(0xAFF1_0001);
            const random = prng.random();
            if (mode == 2) {
                const low = try std.fmt.parseFloat(types.ScienceFloat, parts.items[0]);
                const high = try std.fmt.parseFloat(types.ScienceFloat, parts.items[1]);
                for (0..count) |_| try out.append(types.roundDigits(types.ScienceFloat, low + random.float(types.ScienceFloat) * (high - low), 2));
            } else {
                const mean = try std.fmt.parseFloat(types.ScienceFloat, parts.items[0]);
                const stdev = try std.fmt.parseFloat(types.ScienceFloat, parts.items[1]);
                for (0..count) |_| try out.append(types.roundDigits(types.ScienceFloat, mean + stdev * normal(random), 2));
            }
        } else return error.InvalidDistribution;
    } else if (parts.items.len == 1) {
        const value = try std.fmt.parseFloat(types.ScienceFloat, parts.items[0]);
        try out.append(if (round) types.roundDigits(types.ScienceFloat, value, 2) else value);
    } else {
        return error.InvalidDistribution;
    }
    return out.toOwnedSlice();
}

fn normal(random: std.Random) types.ScienceFloat {
    const r1 = @max(random.float(types.ScienceFloat), 0.000001);
    const r2 = random.float(types.ScienceFloat);
    return @sqrt(-2.0 * @log(r1)) * @cos(2.0 * std.math.pi * r2);
}

const testing = std.testing;

test "parseScenario accepts tab-delimited lines" {
    const allocator = testing.allocator;
    var scenario = try parseScenario(allocator, "1\t10\t2\tW4\t2\t3\t2\t6.5\t0.2\t1\t1\t\t \t6\t1\t1\t20\t2\t10\t2\t1\t0\t8\t700\t2");
    defer scenario.deinit(allocator);
    try testing.expectEqual(@as(i64, 1), scenario.index);
    try testing.expectEqual(@as(types.Id, 4), scenario.meridian);
    try testing.expectEqualSlices(types.ScienceFloat, &.{2.0}, scenario.som);
}

test "parseScenario accepts comma-delimited lines" {
    const allocator = testing.allocator;
    var scenario = try parseScenario(allocator, "1,10,2,W4,2,3,2,6.5,0.2,1,1,, ,6,1,1,20,2,10,2,1,0,8,700,2");
    defer scenario.deinit(allocator);
    try testing.expectEqual(@as(i64, 1), scenario.index);
    try testing.expectEqualSlices(types.ScienceFloat, &.{2.0}, scenario.som);
}

test "parseScenario rejects lines with too few columns" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidInput, parseScenario(allocator, "1,10,2,W4"));
}

test "parseScenario propagates invalid numeric text as a parse error" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidCharacter, parseScenario(allocator, "1,ten,2,W4,2,3,2,6.5,0.2,1,1,, ,6,1,1,20,2,10,2,1,0,8,700,2"));
}

test "parseScenario frees earlier fields' allocations when a later field fails to parse" {
    const allocator = testing.allocator;
    // som, soil_texture, spring_soil_moisture, soil_ph, and soil_ec (columns 4-8) all
    // succeed and allocate slices before current_crop (column 9) fails to parse. Without
    // an errdefer on every earlier allocation, those slices would leak instead of being
    // freed when the function returns the error below (testing.allocator asserts no
    // leaks at the end of this test).
    try testing.expectError(error.InvalidCharacter, parseScenario(allocator, "1,10,2,W4,2,3,2,6.5,0.2,notacrop,1,, ,6,1,1,20,2,10,2,1,0,8,700,2"));
}

test "parseMeridian handles W-prefixed and plain numeric text" {
    try testing.expectEqual(@as(types.Id, 4), try parseMeridian("W4"));
    try testing.expectEqual(@as(types.Id, 4), try parseMeridian("w4"));
    try testing.expectEqual(@as(types.Id, 4), try parseMeridian("4"));
}

test "parseOptionalRealList treats empty, dash, and na as zero-length" {
    const allocator = testing.allocator;
    for ([_][]const u8{ "", "-", "na", "NA", "Na" }) |text| {
        const list = try parseOptionalRealList(allocator, text);
        defer allocator.free(list);
        try testing.expectEqual(@as(usize, 0), list.len);
    }
    const populated = try parseOptionalRealList(allocator, "12.5");
    defer allocator.free(populated);
    try testing.expectEqualSlices(types.ScienceFloat, &.{12.5}, populated);
}

test "parseIdList parses multiple pipe-separated ids with surrounding whitespace" {
    const allocator = testing.allocator;
    const ids = try parseIdList(allocator, " 1 | 2| 3 ");
    defer allocator.free(ids);
    try testing.expectEqualSlices(types.Id, &.{ 1, 2, 3 }, ids);
}

test "parseRealList parses a single value" {
    const allocator = testing.allocator;
    const values = try parseRealList(allocator, "6.5", true);
    defer allocator.free(values);
    try testing.expectEqualSlices(types.ScienceFloat, &.{6.5}, values);
}

test "parseRealList mode 1 step distribution is inclusive of the high bound" {
    const allocator = testing.allocator;
    const values = try parseRealList(allocator, "2|4|1|1", true);
    defer allocator.free(values);
    try testing.expectEqualSlices(types.ScienceFloat, &.{ 2.0, 3.0, 4.0 }, values);
}

test "parseRealList mode 2 uniform Monte Carlo respects count and bounds" {
    const allocator = testing.allocator;
    const values = try parseRealList(allocator, "10|20|2|5", true);
    defer allocator.free(values);
    try testing.expectEqual(@as(usize, 5), values.len);
    for (values) |v| {
        try testing.expect(v >= 10.0 and v <= 20.0);
    }
}

test "parseRealList mode 3 normal Monte Carlo produces finite values" {
    const allocator = testing.allocator;
    const values = try parseRealList(allocator, "100|10|3|5", true);
    defer allocator.free(values);
    try testing.expectEqual(@as(usize, 5), values.len);
    for (values) |v| {
        try testing.expect(std.math.isFinite(v));
    }
}

test "parseRealList rejects an unknown distribution mode" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidDistribution, parseRealList(allocator, "10|20|9|5", true));
}

test "parseRealList rejects a malformed field shape" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidDistribution, parseRealList(allocator, "10|20", true));
}

test "normal distribution helper returns finite values across many draws" {
    var prng = std.Random.DefaultPrng.init(1234);
    const random = prng.random();
    for (0..100) |_| {
        try testing.expect(std.math.isFinite(normal(random)));
    }
}
