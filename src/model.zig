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
    var rows = try ctx.allocator.alloc(SeriesRow, count);
    defer ctx.allocator.free(rows);

    for (rows, 0..) |*row, i| {
        const n_rate = @as(types.ScienceFloat, @floatFromInt(i)) * types.Constants.n_rate_step_size;
        const total_plant_available_n = plant_available_soil_n + n_rate;
        row.* = .{
            .n_rate = n_rate,
            .predicted_crop_yield = ph_adjust * ec_adjust * yield_unit_conversion * wue * total_moisture * (1.0 - std.math.pow(types.ScienceFloat, 10.0, -epsilon * total_plant_available_n * types.Constants.kg_ha_n_lb_ac * std.math.pow(types.ScienceFloat, wue * total_moisture, response_exponent))),
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
        row.investment_ratio = row.marginal_return / row.marginal_cost;
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
