const std = @import("std");
const types = @import("types.zig");
const Coefficients = @import("coefficients.zig").Coefficients;

pub const RunContext = struct {
    allocator: std.mem.Allocator,
    coeffs: *const Coefficients,
    writer: *std.Io.Writer,
    log: *std.Io.Writer,
};

pub fn evaluateScenario(ctx: RunContext, input: *const types.InputScenario, row_number: usize) !void {
    const precip_idx = ctx.coeffs.precipIndex(input.township, input.range, input.meridian);
    if (precip_idx >= ctx.coeffs.soil_zone_id.len or ctx.coeffs.soil_zone_id[precip_idx] == 0) {
        try ctx.log.print("Error: Legal land location is not valid for the scenario at row {d} of your input file. No output was written for this scenario.\n", .{row_number});
        return;
    }

    // These identifiers index directly into fixed-size coefficient tables further down
    // (crop_unit_conv_coef, b0ph/b1ph/b2ph, b0ec/b1ec, n_source_percent_n, b0ag/b0bg, and
    // the residue_management_multiplier constant). Rejecting out-of-range ids here, once
    // per scenario, keeps those lookups safe without adding bounds checks inside the hot
    // combinatorial loop below.
    if (!ctx.coeffs.cropValid(input.current_crop)) {
        try ctx.log.print("Error: Crop identifier {d} is not valid for the scenario at row {d} of your input file. No output was written for this scenario.\n", .{ input.current_crop, row_number });
        return;
    }
    if (!ctx.coeffs.nSourceValid(input.n_source)) {
        try ctx.log.print("Error: Nitrogen fertilizer product identifier {d} is not valid for the scenario at row {d} of your input file. No output was written for this scenario.\n", .{ input.n_source, row_number });
        return;
    }
    if (!ctx.coeffs.residueCoeffValid(input.previous_crop, input.previous_crop_yield_unit)) {
        try ctx.log.print("Error: Previous crop identifier {d} or previous crop yield unit identifier {d} is not valid for the scenario at row {d} of your input file. No output was written for this scenario.\n", .{ input.previous_crop, input.previous_crop_yield_unit, row_number });
        return;
    }
    for (input.residue_management) |residue_id| {
        if (residue_id == 0 or residue_id > types.Constants.residue_management_multiplier.len) {
            try ctx.log.print("Error: Residue management identifier {d} is not valid for the scenario at row {d} of your input file. No output was written for this scenario.\n", .{ residue_id, row_number });
            return;
        }
    }

    const soil_zone_id = ctx.coeffs.soil_zone_id[precip_idx];
    const soil_zone = ctx.coeffs.name(ctx.coeffs.soil_zone, soil_zone_id);
    const precip_set = try buildGrowingSeasonMoisture(ctx.allocator, ctx.coeffs.*, input.*, precip_idx);
    defer precip_set.deinit(ctx.allocator);

    const yield_unit_conversion_kg_ha_to_bu_ac = ctx.coeffs.crop_unit_conv_coef[input.current_crop] * 0.000405;

    for (input.soil_texture) |texture_id| for (input.spring_soil_moisture) |spring_id| {
        const spring_water = ctx.coeffs.springMoisture(spring_id, texture_id);
        for (precip_set.values, precip_set.flags) |growing_precip, moisture_flag| {
            const total_moisture = growing_precip + spring_water;
            for (input.soil_ph) |soil_ph_in| {
                const crop_id = input.current_crop;
                const soil_ph = @min(ctx.coeffs.phmax[crop_id], @max(ctx.coeffs.phmin[crop_id], soil_ph_in));
                const ph_adjust = std.math.clamp(ctx.coeffs.b0ph[crop_id] + ctx.coeffs.b1ph[crop_id] * soil_ph + ctx.coeffs.b2ph[crop_id] * soil_ph * soil_ph, 0.0, 1.0);
                if (ph_adjust < 1.0) {
                    try ctx.log.print("Warning: Crop yield is {s} affected by adverse soil pH. This warning is for the scenario at row {d} of your input file.\n", .{ if (ph_adjust >= 0.75) "moderately" else "severely", row_number });
                }
                for (input.soil_ec) |soil_ec| {
                    const ec_adjust = std.math.clamp(ctx.coeffs.b0ec[crop_id] + ctx.coeffs.b1ec[crop_id] * soil_ec, 0.0, 1.0);
                    if (ec_adjust < 1.0) {
                        try ctx.log.print("Warning: Crop yield is {s} affected by soil salinity. This warning is for the scenario at row {d} of your input file.\n", .{ if (ec_adjust >= 0.75) "moderately" else "severely", row_number });
                    }
                    for (input.som) |som| {
                        const estimated_n_release = types.roundDigits(types.ScienceFloat, (20.6 + 13.2 * som - 0.1777 * som * som) / types.Constants.kg_ha_n_lb_ac, 1);
                        for (input.previous_crop_yield) |prev_yield| {
                            for (input.residue_management) |residue_id| {
                                const residue_coeff_index = ctx.coeffs.residueIndex(input.previous_crop, input.previous_crop_yield_unit);
                                const residue_management_multiplier = types.Constants.residue_management_multiplier[residue_id - 1];
                                const residue_n_credit = types.roundDigits(types.ScienceFloat, prev_yield * (residue_management_multiplier * ctx.coeffs.b0ag[residue_coeff_index] + ctx.coeffs.b0bg[residue_coeff_index]), 0);
                                for (input.soil_test_n) |soil_test_n| {
                                    for (input.manure_n) |manure_n| {
                                        const plant_available_soil_n = types.roundDigits(types.ScienceFloat, estimated_n_release + residue_n_credit + soil_test_n + manure_n, 0);
                                        for (input.n_time) |time_id| {
                                            for (input.n_place) |place_id| {
                                                for (input.crop_price) |crop_price| {
                                                    for (input.fertilizer_price) |fert_price| {
                                                        for (input.investment_ratio) |investment_ratio| {
                                                            try evaluateNitrogenSeries(ctx, input, .{
                                                                .index = input.index,
                                                                .township = input.township,
                                                                .range = input.range,
                                                                .meridian_text = input.meridian_text,
                                                                .som = som,
                                                                .soil_ph = soil_ph_in,
                                                                .soil_ec = soil_ec,
                                                                .soil_test_n = soil_test_n,
                                                                .previous_crop_yield = prev_yield,
                                                                .manure_n = manure_n,
                                                                .crop_price = crop_price,
                                                                .fertilizer_price = fert_price,
                                                                .investment_ratio = investment_ratio,
                                                            }, soil_zone_id, soil_zone, texture_id, spring_id, moisture_flag, growing_precip, place_id, time_id, residue_id, estimated_n_release, residue_n_credit, plant_available_soil_n, total_moisture, ph_adjust, ec_adjust, yield_unit_conversion_kg_ha_to_bu_ac);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    };
}

// ln(10), used to turn 10^y into @exp(y * ln10). std.math.pow(f32, 10.0, y) recomputes
// ln(10) from scratch on every call since it can't see that the base is always the same
// literal; a comptime constant removes that redundant log() from the innermost loop.
const ln10: types.ScienceFloat = 2.302585093;

const MoistureSet = struct {
    values: []types.ScienceFloat,
    flags: []const []const u8,
    pub fn deinit(self: MoistureSet, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        allocator.free(self.flags);
    }
};

fn buildGrowingSeasonMoisture(allocator: std.mem.Allocator, coeffs: Coefficients, input: types.InputScenario, precip_idx: usize) !MoistureSet {
    var values = std.array_list.Managed(types.ScienceFloat).init(allocator);
    errdefer values.deinit();
    var flags = std.array_list.Managed([]const u8).init(allocator);
    errdefer flags.deinit();

    if (input.irrigation_flag == 1) {
        if (input.precip.len > 0) for (input.precip) |v| {
            try values.append(v);
            try flags.append("Growing season precipitation - User input");
        };
        try values.append(types.roundDigits(types.ScienceFloat, coeffs.b0precip[precip_idx] - 90.0 * coeffs.b1precip[precip_idx], 0));
        try values.append(types.roundDigits(types.ScienceFloat, coeffs.b0precip[precip_idx] - 50.0 * coeffs.b1precip[precip_idx], 0));
        try values.append(types.roundDigits(types.ScienceFloat, coeffs.b0precip[precip_idx] - 10.0 * coeffs.b1precip[precip_idx], 0));
        try flags.append("Growing season precipitation - Low moisture condition");
        try flags.append("Growing season precipitation - Intermediate moisture condition");
        try flags.append("Growing season precipitation - Optimum moisture condition");
    } else {
        if (input.irrigation_amount.len > 0) for (input.irrigation_amount) |v| {
            try values.append(v);
            try flags.append("Irrigation water amount - User input");
        };
        try values.append(types.roundDigits(types.ScienceFloat, types.Constants.b0irrig - 90.0 * types.Constants.b1irrig, 0));
        try values.append(types.roundDigits(types.ScienceFloat, types.Constants.b0irrig - 50.0 * types.Constants.b1irrig, 0));
        try values.append(types.roundDigits(types.ScienceFloat, types.Constants.b0irrig - 10.0 * types.Constants.b1irrig, 0));
        try flags.append("Irrigation water amount - Low irrigation level");
        try flags.append("Irrigation water amount - Intermediate irrigation level");
        try flags.append("Irrigation water amount - Optimum irrigation level");
    }
    return .{ .values = try values.toOwnedSlice(), .flags = try flags.toOwnedSlice() };
}

fn evaluateNitrogenSeries(ctx: RunContext, input: *const types.InputScenario, view: types.InputScenarioView, soil_zone_id: types.Id, soil_zone: []const u8, texture_id: types.Id, spring_id: types.Id, moisture_flag: []const u8, growing_precip: types.ScienceFloat, place_id: types.Id, time_id: types.Id, residue_id: types.Id, estimated_n_release: types.ScienceFloat, residue_n_credit: types.ScienceFloat, plant_available_soil_n: types.ScienceFloat, total_moisture: types.ScienceFloat, ph_adjust: types.ScienceFloat, ec_adjust: types.ScienceFloat, yield_unit_conversion: types.ScienceFloat) !void {
    const wue = ctx.coeffs.wue.get(place_id, time_id, input.n_source, soil_zone_id, input.current_crop);
    const epsilon = ctx.coeffs.epsilon.get(place_id, time_id, input.n_source, soil_zone_id, input.current_crop);
    const response_exponent = ctx.coeffs.nminus1.get(place_id, time_id, input.n_source, soil_zone_id, input.current_crop);
    if (wue == 0.0 and epsilon == 0.0 and response_exponent == 0.0) {
        try writeRow(ctx.writer, ctx.coeffs.*, input, view, soil_zone, texture_id, spring_id, moisture_flag, growing_precip, place_id, time_id, residue_id, estimated_n_release, residue_n_credit, plant_available_soil_n, 0.0, null, null, null, null, null, null, null, null, false, "Yield response information is not available for either the legal land location or the combination of fertilizer management that you have chosen for your field in this scenario; please try with a different combination");
        return;
    }

    var high_n_rate = types.Constants.ns_max - plant_available_soil_n;
    if (high_n_rate < 0.0) high_n_rate = 0.0;
    if (@mod(high_n_rate, types.Constants.n_rate_step_size) > 0.0) {
        high_n_rate = types.Constants.n_rate_step_size * (1.0 + @floor(high_n_rate / types.Constants.n_rate_step_size));
    }
    const count = @as(usize, @intFromFloat(@floor(high_n_rate / types.Constants.n_rate_step_size))) + 1;

    // Series length is normally small (ns_max/step + 1 = 36); an inline buffer avoids a
    // heap alloc/free per call in this combinatorially-hot path, falling back to the
    // allocator only for pathological inputs (e.g. a very negative plant_available_soil_n).
    const inline_capacity = 64;
    var inline_rows: [inline_capacity]SeriesRow = undefined;
    var heap_rows: []SeriesRow = &.{};
    defer if (heap_rows.len != 0) ctx.allocator.free(heap_rows);
    const rows: []SeriesRow = if (count <= inline_capacity) inline_rows[0..count] else blk: {
        heap_rows = try ctx.allocator.alloc(SeriesRow, count);
        break :blk heap_rows;
    };

    // wue/total_moisture/response_exponent are invariant across the n-rate series, so this
    // pow() is hoisted out of the loop instead of being recomputed on every row.
    const response_moisture_term = std.math.pow(types.ScienceFloat, wue * total_moisture, response_exponent);

    for (rows, 0..) |*row, i| {
        const n_rate = @as(types.ScienceFloat, @floatFromInt(i)) * types.Constants.n_rate_step_size;
        const total_plant_available_n = plant_available_soil_n + n_rate;
        const exponent = -epsilon * total_plant_available_n * types.Constants.kg_ha_n_lb_ac * response_moisture_term;
        row.* = .{
            .n_rate = n_rate,
            .predicted_crop_yield = ph_adjust * ec_adjust * yield_unit_conversion * wue * total_moisture * (1.0 - @exp(exponent * ln10)),
            .added_yield_increase = 0.0,
            .predicted_yield_increase = 0.0,
            .total_cost = n_rate * view.fertilizer_price / 1000.0 * 0.4536 / (ctx.coeffs.n_source_percent_n[input.n_source] / 100.0),
            .marginal_cost = 0.0,
            .revenue = 0.0,
            .marginal_return = 0.0,
            .investment_ratio = 0.0,
        };
    }
    for (rows[1..], 1..) |*row, i| {
        row.added_yield_increase = row.predicted_crop_yield - rows[i - 1].predicted_crop_yield;
        row.predicted_yield_increase = row.predicted_crop_yield - rows[0].predicted_crop_yield;
        row.marginal_cost = row.total_cost - rows[i - 1].total_cost;
        row.revenue = row.predicted_yield_increase * view.crop_price;
        row.marginal_return = row.added_yield_increase * view.crop_price;
        // marginal_cost is 0 when fertilizer_price is 0 (free fertilizer). Falling back to
        // 0.0 instead of dividing keeps NaN/Inf out of the recommendation comparison below
        // and out of the tab-delimited output column.
        row.investment_ratio = if (row.marginal_cost != 0.0) row.marginal_return / row.marginal_cost else 0.0;
    }
    for (rows) |*row| row.round();

    var recommended_set = false;
    if (rows.len > 1 and rows[1].added_yield_increase >= 0.5) {
        try writeRow(ctx.writer, ctx.coeffs.*, input, view, soil_zone, texture_id, spring_id, moisture_flag, growing_precip, place_id, time_id, residue_id, estimated_n_release, residue_n_credit, plant_available_soil_n, rows[0].n_rate, rows[0].predicted_crop_yield, null, null, null, null, null, null, null, false, null);
    }
    for (rows, 0..) |row, i| {
        var recommended = false;
        if (!recommended_set) {
            if (i > 1 and row.investment_ratio <= view.investment_ratio and rows[i - 1].investment_ratio > view.investment_ratio) {
                recommended = true;
                recommended_set = true;
            } else if (i == 1 and row.investment_ratio == view.investment_ratio) {
                recommended = true;
                recommended_set = true;
            }
        }
        if (row.added_yield_increase >= 0.5) {
            try writeRow(ctx.writer, ctx.coeffs.*, input, view, soil_zone, texture_id, spring_id, moisture_flag, growing_precip, place_id, time_id, residue_id, estimated_n_release, residue_n_credit, plant_available_soil_n, row.n_rate, row.predicted_crop_yield, row.predicted_yield_increase, row.added_yield_increase, row.revenue, row.marginal_return, row.total_cost, row.marginal_cost, row.investment_ratio, recommended, null);
        }
    }
}

const SeriesRow = struct {
    n_rate: types.ScienceFloat,
    predicted_crop_yield: types.ScienceFloat,
    added_yield_increase: types.ScienceFloat,
    predicted_yield_increase: types.ScienceFloat,
    total_cost: types.ScienceFloat,
    marginal_cost: types.ScienceFloat,
    revenue: types.ScienceFloat,
    marginal_return: types.ScienceFloat,
    investment_ratio: types.ScienceFloat,

    fn round(self: *SeriesRow) void {
        self.predicted_crop_yield = types.roundDigits(types.ScienceFloat, self.predicted_crop_yield, 1);
        self.added_yield_increase = types.roundDigits(types.ScienceFloat, self.added_yield_increase, 1);
        self.predicted_yield_increase = types.roundDigits(types.ScienceFloat, self.predicted_yield_increase, 1);
        self.total_cost = types.roundDigits(types.ScienceFloat, self.total_cost, 2);
        self.marginal_cost = types.roundDigits(types.ScienceFloat, self.marginal_cost, 2);
        self.revenue = types.roundDigits(types.ScienceFloat, self.revenue, 2);
        self.marginal_return = types.roundDigits(types.ScienceFloat, self.marginal_return, 2);
        self.investment_ratio = types.roundDigits(types.ScienceFloat, self.investment_ratio, 1);
    }
};

fn writeRow(writer: *std.Io.Writer, coeffs: Coefficients, input: *const types.InputScenario, view: types.InputScenarioView, soil_zone: []const u8, texture_id: types.Id, spring_id: types.Id, moisture_flag: []const u8, growing_precip: types.ScienceFloat, place_id: types.Id, time_id: types.Id, residue_id: types.Id, estimated_n_release: types.ScienceFloat, residue_n_credit: types.ScienceFloat, plant_available_soil_n: types.ScienceFloat, n_rate: types.ScienceFloat, predicted_crop_yield: ?types.ScienceFloat, predicted_yield_increase: ?types.ScienceFloat, added_yield_increase: ?types.ScienceFloat, revenue: ?types.ScienceFloat, marginal_return: ?types.ScienceFloat, total_cost: ?types.ScienceFloat, marginal_cost: ?types.ScienceFloat, investment_ratio: ?types.ScienceFloat, recommended: bool, comment: ?[]const u8) !void {
    try writer.print("{d}\t{d}\t{d}\t{s}\t{s}\t{d:.2}\t{s}\t{s}\t{d:.2}\t{d:.2}\t{s}\t{s}\t{s}\t{d:.1}\t{s}\t{s}\t{s}\t{d:.2}\t{s}\t{d:.2}\t{s}\t{s}\t{d:.2}\t{d:.2}\t{d:.2}\t{d:.2}\t{d:.1}\t{d:.0}\t{d:.0}\t{d:.1}", .{
        view.index,                                             view.township,                                            view.range,                                                                 view.meridian_text,                                 soil_zone,                                         view.som,
        coeffs.name(coeffs.soil_texture, texture_id),           coeffs.name(coeffs.spring_moisture_condition, spring_id), view.soil_ph,                                                               view.soil_ec,                                       coeffs.name(coeffs.crop_name, input.current_crop), coeffs.name(coeffs.irrigation_flag, input.irrigation_flag),
        moisture_flag,                                          growing_precip,                                           coeffs.name(coeffs.n_source, input.n_source),                               coeffs.name(coeffs.n_time, time_id),                coeffs.name(coeffs.n_place, place_id),             view.soil_test_n,
        coeffs.name(coeffs.previous_crop, input.previous_crop), view.previous_crop_yield,                                 coeffs.name(coeffs.previous_crop_yld_unit, input.previous_crop_yield_unit), coeffs.name(coeffs.residue_management, residue_id), view.manure_n,                                     view.crop_price,
        view.fertilizer_price,                                  view.investment_ratio,                                    estimated_n_release,                                                        residue_n_credit,                                   plant_available_soil_n,                            n_rate,
    });
    try writeOptional(writer, predicted_crop_yield, 1);
    try writeOptional(writer, predicted_yield_increase, 1);
    try writeOptional(writer, added_yield_increase, 1);
    try writeOptional(writer, revenue, 2);
    try writeOptional(writer, marginal_return, 2);
    try writeOptional(writer, total_cost, 2);
    try writeOptional(writer, marginal_cost, 2);
    try writeOptional(writer, investment_ratio, 1);
    if (recommended) try writer.writeAll("\tYes") else try writer.writeByte('\t');
    if (comment) |comment_text| try writer.print("\t{s}", .{comment_text}) else try writer.writeByte('\t');
    try writer.writeByte('\n');
}

fn writeOptional(writer: *std.Io.Writer, value: ?types.ScienceFloat, digits: comptime_int) !void {
    try writer.writeByte('\t');
    if (value) |v| {
        switch (digits) {
            1 => try writer.print("{d:.1}", .{v}),
            2 => try writer.print("{d:.2}", .{v}),
            else => try writer.print("{d}", .{v}),
        }
    }
}

const testing = std.testing;

fn testScenario(allocator: std.mem.Allocator) !types.InputScenario {
    return .{
        .index = 1,
        .township = 1,
        .range = 1,
        .meridian = 1,
        .meridian_text = try allocator.dupe(u8, "W1"),
        .som = try allocator.dupe(types.ScienceFloat, &.{2.0}),
        .soil_texture = try allocator.dupe(types.Id, &.{1}),
        .spring_soil_moisture = try allocator.dupe(types.Id, &.{1}),
        .soil_ph = try allocator.dupe(types.ScienceFloat, &.{6.5}),
        .soil_ec = try allocator.dupe(types.ScienceFloat, &.{0.2}),
        .current_crop = 2,
        .irrigation_flag = 1,
        .precip = try allocator.alloc(types.ScienceFloat, 0),
        .irrigation_amount = try allocator.alloc(types.ScienceFloat, 0),
        .n_source = 2,
        .n_time = try allocator.dupe(types.Id, &.{1}),
        .n_place = try allocator.dupe(types.Id, &.{1}),
        .soil_test_n = try allocator.dupe(types.ScienceFloat, &.{20.0}),
        .previous_crop = 1,
        .previous_crop_yield = try allocator.dupe(types.ScienceFloat, &.{10.0}),
        .previous_crop_yield_unit = 1,
        .residue_management = try allocator.dupe(types.Id, &.{1}),
        .manure_n = try allocator.dupe(types.ScienceFloat, &.{0.0}),
        .crop_price = try allocator.dupe(types.ScienceFloat, &.{8.0}),
        .fertilizer_price = try allocator.dupe(types.ScienceFloat, &.{700.0}),
        .investment_ratio = try allocator.dupe(types.ScienceFloat, &.{2.0}),
    };
}

fn testView() types.InputScenarioView {
    return .{
        .index = 1,
        .township = 1,
        .range = 1,
        .meridian_text = "W1",
        .som = 2.0,
        .soil_ph = 6.5,
        .soil_ec = 0.2,
        .soil_test_n = 20.0,
        .previous_crop_yield = 10.0,
        .manure_n = 0.0,
        .crop_price = 8.0,
        .fertilizer_price = 700.0,
        .investment_ratio = 2.0,
    };
}

fn columnAt(row: []const u8, index: usize) []const u8 {
    var cols = std.mem.splitScalar(u8, row, '\t');
    var i: usize = 0;
    while (cols.next()) |c| {
        if (i == index) return c;
        i += 1;
    }
    return "";
}

test "buildGrowingSeasonMoisture: irrigation flag with derived precip levels only" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    const precip_idx = coeffs.precipIndex(1, 1, 1);
    coeffs.b0precip[precip_idx] = 500.0;
    coeffs.b1precip[precip_idx] = 1.0;

    var scenario = try testScenario(allocator);
    defer scenario.deinit(allocator);

    const set = try buildGrowingSeasonMoisture(allocator, coeffs, scenario, precip_idx);
    defer set.deinit(allocator);
    try testing.expectEqual(@as(usize, 3), set.values.len);
    try testing.expectEqual(set.values.len, set.flags.len);
    try testing.expectEqual(@as(types.ScienceFloat, 500.0 - 90.0), set.values[0]);
    try testing.expectEqual(@as(types.ScienceFloat, 500.0 - 50.0), set.values[1]);
    try testing.expectEqual(@as(types.ScienceFloat, 500.0 - 10.0), set.values[2]);
    try testing.expectEqualStrings("Growing season precipitation - Low moisture condition", set.flags[0]);
    try testing.expectEqualStrings("Growing season precipitation - Intermediate moisture condition", set.flags[1]);
    try testing.expectEqualStrings("Growing season precipitation - Optimum moisture condition", set.flags[2]);
}

test "buildGrowingSeasonMoisture: irrigation flag with user-supplied precip prepended" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    const precip_idx = coeffs.precipIndex(1, 1, 1);
    coeffs.b0precip[precip_idx] = 500.0;
    coeffs.b1precip[precip_idx] = 1.0;

    var scenario = try testScenario(allocator);
    allocator.free(scenario.precip);
    scenario.precip = try allocator.dupe(types.ScienceFloat, &.{ 123.0, 456.0 });
    defer scenario.deinit(allocator);

    const set = try buildGrowingSeasonMoisture(allocator, coeffs, scenario, precip_idx);
    defer set.deinit(allocator);
    try testing.expectEqual(@as(usize, 5), set.values.len);
    try testing.expectEqual(@as(types.ScienceFloat, 123.0), set.values[0]);
    try testing.expectEqual(@as(types.ScienceFloat, 456.0), set.values[1]);
    try testing.expectEqualStrings("Growing season precipitation - User input", set.flags[0]);
    try testing.expectEqualStrings("Growing season precipitation - User input", set.flags[1]);
    try testing.expectEqualStrings("Growing season precipitation - Low moisture condition", set.flags[2]);
}

test "buildGrowingSeasonMoisture: no-irrigation flag uses irrigation constants" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    var scenario = try testScenario(allocator);
    scenario.irrigation_flag = 2;
    defer scenario.deinit(allocator);

    const set = try buildGrowingSeasonMoisture(allocator, coeffs, scenario, 0);
    defer set.deinit(allocator);
    try testing.expectEqual(@as(usize, 3), set.values.len);
    try testing.expectEqualStrings("Irrigation water amount - Low irrigation level", set.flags[0]);
    try testing.expectEqualStrings("Irrigation water amount - Intermediate irrigation level", set.flags[1]);
    try testing.expectEqualStrings("Irrigation water amount - Optimum irrigation level", set.flags[2]);
}

test "buildGrowingSeasonMoisture: no-irrigation flag with user-supplied irrigation amount prepended" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    var scenario = try testScenario(allocator);
    scenario.irrigation_flag = 2;
    allocator.free(scenario.irrigation_amount);
    scenario.irrigation_amount = try allocator.dupe(types.ScienceFloat, &.{77.0});
    defer scenario.deinit(allocator);

    const set = try buildGrowingSeasonMoisture(allocator, coeffs, scenario, 0);
    defer set.deinit(allocator);
    try testing.expectEqual(@as(usize, 4), set.values.len);
    try testing.expectEqual(@as(types.ScienceFloat, 77.0), set.values[0]);
    try testing.expectEqualStrings("Irrigation water amount - User input", set.flags[0]);
}

test "evaluateNitrogenSeries: zero response coefficients writes a single comment row" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    try coeffs.wue.set(3, 3, 3, 3, 3, 0.0);
    try coeffs.epsilon.set(3, 3, 3, 3, 3, 0.0);
    try coeffs.nminus1.set(3, 3, 3, 3, 3, 0.0);
    coeffs.n_source_percent_n[3] = 46.0;

    var scenario = try testScenario(allocator);
    scenario.current_crop = 3;
    scenario.n_source = 3;
    defer scenario.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateNitrogenSeries(ctx, &scenario, testView(), 3, "TestZone", 1, 1, "flag", 100.0, 3, 3, 1, 10.0, 5.0, 200.0, 300.0, 1.0, 1.0, 1.0);

    const written = out.written();
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, written, "\n"));
    try testing.expect(std.mem.indexOf(u8, written, "Yield response information is not available") != null);
}

test "evaluateNitrogenSeries: steps n_rate by 10 and matches the documented yield formula" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    const wue: types.ScienceFloat = 1.0;
    const total_moisture: types.ScienceFloat = 50.0;
    const response_exponent: types.ScienceFloat = 1.0;
    const epsilon: types.ScienceFloat = 0.05 / 56.0;
    const plant_available_soil_n: types.ScienceFloat = 20.0;
    const ph_adjust: types.ScienceFloat = 1.0;
    const ec_adjust: types.ScienceFloat = 1.0;
    const yield_unit_conversion: types.ScienceFloat = 1.0;

    try coeffs.wue.set(1, 1, 2, 1, 2, wue);
    try coeffs.epsilon.set(1, 1, 2, 1, 2, epsilon);
    try coeffs.nminus1.set(1, 1, 2, 1, 2, response_exponent);
    coeffs.n_source_percent_n[2] = 46.0;

    var scenario = try testScenario(allocator);
    defer scenario.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateNitrogenSeries(ctx, &scenario, testView(), 1, "TestZone", 1, 1, "flag", 100.0, 1, 1, 1, 10.0, 5.0, plant_available_soil_n, total_moisture, ph_adjust, ec_adjust, yield_unit_conversion);

    const written = out.written();
    try testing.expect(written.len > 0);

    var lines = std.mem.splitScalar(u8, written, '\n');
    const first_row = lines.next().?;
    try testing.expectEqualStrings("0.0", columnAt(first_row, 29));

    const response_moisture_term = std.math.pow(types.ScienceFloat, wue * total_moisture, response_exponent);
    const expected_yield0 = types.roundDigits(types.ScienceFloat, ph_adjust * ec_adjust * yield_unit_conversion * wue * total_moisture * (1.0 - std.math.pow(types.ScienceFloat, 10.0, -epsilon * plant_available_soil_n * types.Constants.kg_ha_n_lb_ac * response_moisture_term)), 1);
    var buf: [32]u8 = undefined;
    const expected_str = try std.fmt.bufPrint(&buf, "{d:.1}", .{expected_yield0});
    try testing.expectEqualStrings(expected_str, columnAt(first_row, 30));

    const second_row = lines.next().?;
    try testing.expectEqualStrings("10.0", columnAt(second_row, 29));

    try testing.expect(std.mem.count(u8, written, "\tYes\t") <= 1);
}

test "evaluateNitrogenSeries: zero fertilizer price yields 0.0 investment ratio instead of NaN/Inf" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    const wue: types.ScienceFloat = 1.0;
    const total_moisture: types.ScienceFloat = 50.0;
    const response_exponent: types.ScienceFloat = 1.0;
    const epsilon: types.ScienceFloat = 0.05 / 56.0;
    const plant_available_soil_n: types.ScienceFloat = 20.0;

    try coeffs.wue.set(1, 1, 2, 1, 2, wue);
    try coeffs.epsilon.set(1, 1, 2, 1, 2, epsilon);
    try coeffs.nminus1.set(1, 1, 2, 1, 2, response_exponent);
    coeffs.n_source_percent_n[2] = 46.0;

    var scenario = try testScenario(allocator);
    defer scenario.deinit(allocator);

    var view = testView();
    view.fertilizer_price = 0.0; // every row's total_cost is 0 -> marginal_cost is 0 for all but the baseline row

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateNitrogenSeries(ctx, &scenario, view, 1, "TestZone", 1, 1, "flag", 100.0, 1, 1, 1, 10.0, 5.0, plant_available_soil_n, total_moisture, 1.0, 1.0, 1.0);

    const written = out.written();
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.indexOf(u8, written, "nan") == null);
    try testing.expect(std.mem.indexOf(u8, written, "inf") == null);

    var lines = std.mem.splitScalar(u8, written, '\n');
    _ = lines.next().?; // baseline row (n_rate 0): investment_ratio column is left blank, not under test here
    const second_row = lines.next().?;
    try testing.expectEqualStrings("10.0", columnAt(second_row, 29));
    try testing.expectEqualStrings("0.0", columnAt(second_row, 37));
}

test "evaluateNitrogenSeries: falls back to heap allocation for a long series without leaking" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();
    try coeffs.wue.set(1, 1, 2, 1, 2, 0.01);
    try coeffs.epsilon.set(1, 1, 2, 1, 2, 0.0001);
    try coeffs.nminus1.set(1, 1, 2, 1, 2, 1.0);
    coeffs.n_source_percent_n[2] = 46.0;

    var scenario = try testScenario(allocator);
    defer scenario.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    // plant_available_soil_n = -1000 -> high_n_rate = 350-(-1000) = 1350, count = 136 > inline_capacity(64).
    try evaluateNitrogenSeries(ctx, &scenario, testView(), 1, "TestZone", 1, 1, "flag", 100.0, 1, 1, 1, 10.0, 5.0, -1000.0, 50.0, 1.0, 1.0, 1.0);
}

test "evaluateScenario: invalid legal land location logs an error and writes nothing" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    scenario.township = 9999; // far beyond any valid township -> precip_idx exceeds soil_zone_id.len
    defer scenario.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 2);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Legal land location is not valid") != null);
}

test "evaluateScenario: out-of-range crop identifier logs an error and writes nothing" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    scenario.current_crop = @intCast(coeffs.b0ph.len + 10); // beyond crop_unit_conv_coef/phmax/b0ph/b0ec table bounds
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 5);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Crop identifier") != null);
}

test "evaluateScenario: out-of-range nitrogen source identifier logs an error and writes nothing" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    scenario.n_source = @intCast(coeffs.n_source_percent_n.len + 5); // beyond n_source_percent_n table bounds
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 5);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Nitrogen fertilizer product identifier") != null);
}

test "evaluateScenario: previous crop yield unit of 0 logs an error and writes nothing" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    scenario.previous_crop_yield_unit = 0; // residueCoeffValid rejects a 0 yield unit
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 5);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Previous crop identifier") != null);
}

test "evaluateScenario: residue management identifier of 0 logs an error instead of underflowing an index" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    allocator.free(scenario.residue_management);
    // 0 previously underflowed `residue_id - 1` on the unsigned Id type into a huge index.
    scenario.residue_management = try allocator.dupe(types.Id, &.{0});
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 5);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Residue management identifier") != null);
}

test "evaluateScenario: residue management identifier past the multiplier table logs an error" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    var scenario = try testScenario(allocator);
    allocator.free(scenario.residue_management);
    scenario.residue_management = try allocator.dupe(types.Id, &.{100});
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 5);

    try testing.expectEqual(@as(usize, 0), out.written().len);
    try testing.expect(std.mem.indexOf(u8, log.written(), "Residue management identifier") != null);
}

test "evaluateScenario: valid scenario writes output rows and triggers pH/EC warnings" {
    const allocator = testing.allocator;
    var coeffs = try Coefficients.load(allocator);
    defer coeffs.deinit();

    // Neutralize real embedded data this test does not want influencing its deterministic setup.
    @memset(coeffs.spring_soil_moisture, 0.0);
    @memset(coeffs.b0ag, 0.0);
    @memset(coeffs.b0bg, 0.0);

    var scenario = try testScenario(allocator);
    defer scenario.deinit(allocator);

    const precip_idx = coeffs.precipIndex(scenario.township, scenario.range, scenario.meridian);
    coeffs.soil_zone_id[precip_idx] = 1;
    coeffs.soil_zone[1] = "TestZone";
    coeffs.b0precip[precip_idx] = 60.0;
    coeffs.b1precip[precip_idx] = 0.0; // all three growing-season moisture levels collapse to exactly 60.0

    coeffs.crop_unit_conv_coef[scenario.current_crop] = 1.0 / 0.000405;

    coeffs.phmin[scenario.current_crop] = 0.0;
    coeffs.phmax[scenario.current_crop] = 14.0;
    coeffs.b0ph[scenario.current_crop] = 0.8; // ph_adjust == 0.8 regardless of soil_ph -> triggers warning
    coeffs.b1ph[scenario.current_crop] = 0.0;
    coeffs.b2ph[scenario.current_crop] = 0.0;

    coeffs.b0ec[scenario.current_crop] = 0.8; // ec_adjust == 0.8 -> triggers warning
    coeffs.b1ec[scenario.current_crop] = 0.0;

    try coeffs.wue.set(1, 1, scenario.n_source, 1, scenario.current_crop, 1.0);
    try coeffs.epsilon.set(1, 1, scenario.n_source, 1, scenario.current_crop, 0.0002);
    try coeffs.nminus1.set(1, 1, scenario.n_source, 1, scenario.current_crop, 1.0);
    coeffs.n_source_percent_n[scenario.n_source] = 46.0;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var log = std.Io.Writer.Allocating.init(allocator);
    defer log.deinit();
    const ctx = RunContext{ .allocator = allocator, .coeffs = &coeffs, .writer = &out.writer, .log = &log.writer };

    try evaluateScenario(ctx, &scenario, 2);

    try testing.expect(std.mem.indexOf(u8, log.written(), "affected by adverse soil pH") != null);
    try testing.expect(std.mem.indexOf(u8, log.written(), "affected by soil salinity") != null);
    try testing.expect(out.written().len > 0);

    var lines = std.mem.splitScalar(u8, out.written(), '\n');
    const first_row = lines.next().?;
    try testing.expectEqualStrings("TestZone", columnAt(first_row, 4));
}
