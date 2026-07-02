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

    const meridian_text = try allocator.dupe(u8, columns[3]);
    errdefer allocator.free(meridian_text);

    return .{
        .index = try std.fmt.parseInt(i64, columns[0], 10),
        .township = try std.fmt.parseInt(types.Id, columns[1], 10),
        .range = try std.fmt.parseInt(types.Id, columns[2], 10),
        .meridian = try parseMeridian(columns[3]),
        .meridian_text = meridian_text,
        .som = try parseRealList(allocator, columns[4], true),
        .soil_texture = try parseIdList(allocator, columns[5]),
        .spring_soil_moisture = try parseIdList(allocator, columns[6]),
        .soil_ph = try parseRealList(allocator, columns[7], true),
        .soil_ec = try parseRealList(allocator, columns[8], true),
        .current_crop = try std.fmt.parseInt(types.Id, columns[9], 10),
        .irrigation_flag = try std.fmt.parseInt(types.Id, columns[10], 10),
        .precip = try parseOptionalRealList(allocator, columns[11]),
        .irrigation_amount = try parseOptionalRealList(allocator, columns[12]),
        .n_source = try std.fmt.parseInt(types.Id, columns[13], 10),
        .n_time = try parseIdList(allocator, columns[14]),
        .n_place = try parseIdList(allocator, columns[15]),
        .soil_test_n = try parseRealList(allocator, columns[16], true),
        .previous_crop = try std.fmt.parseInt(types.Id, columns[17], 10),
        .previous_crop_yield = try parseRealList(allocator, columns[18], true),
        .previous_crop_yield_unit = try std.fmt.parseInt(types.Id, columns[19], 10),
        .residue_management = try parseIdList(allocator, columns[20]),
        .manure_n = try parseRealList(allocator, columns[21], true),
        .crop_price = try parseRealList(allocator, columns[22], true),
        .fertilizer_price = try parseRealList(allocator, columns[23], true),
        .investment_ratio = try parseRealList(allocator, columns[24], true),
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
