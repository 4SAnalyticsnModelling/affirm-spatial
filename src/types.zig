const std = @import("std");

pub const ScienceFloat = f32;
pub const Id = u16;

pub const Constants = struct {
    pub const residue_management_multiplier = [_]ScienceFloat{ 1.0, 0.0, 0.0 };
    pub const b0irrig: ScienceFloat = 519.83;
    pub const b1irrig: ScienceFloat = 1.56;
    pub const low_n_rate: ScienceFloat = 0.0;
    pub const n_rate_step_size: ScienceFloat = 10.0;
    pub const ns_max: ScienceFloat = 350.0;
    pub const kg_ha_n_lb_ac: ScienceFloat = 1.12;
};

pub const InputScenario = struct {
    index: i64,
    township: Id,
    range: Id,
    meridian: Id,
    meridian_text: []const u8,
    som: []ScienceFloat,
    soil_texture: []Id,
    spring_soil_moisture: []Id,
    soil_ph: []ScienceFloat,
    soil_ec: []ScienceFloat,
    current_crop: Id,
    irrigation_flag: Id,
    precip: []ScienceFloat,
    irrigation_amount: []ScienceFloat,
    n_source: Id,
    n_time: []Id,
    n_place: []Id,
    soil_test_n: []ScienceFloat,
    previous_crop: Id,
    previous_crop_yield: []ScienceFloat,
    previous_crop_yield_unit: Id,
    residue_management: []Id,
    manure_n: []ScienceFloat,
    crop_price: []ScienceFloat,
    fertilizer_price: []ScienceFloat,
    investment_ratio: []ScienceFloat,

    pub fn deinit(self: *InputScenario, allocator: std.mem.Allocator) void {
        allocator.free(self.meridian_text);
        allocator.free(self.som);
        allocator.free(self.soil_texture);
        allocator.free(self.spring_soil_moisture);
        allocator.free(self.soil_ph);
        allocator.free(self.soil_ec);
        allocator.free(self.precip);
        allocator.free(self.irrigation_amount);
        allocator.free(self.n_time);
        allocator.free(self.n_place);
        allocator.free(self.soil_test_n);
        allocator.free(self.previous_crop_yield);
        allocator.free(self.residue_management);
        allocator.free(self.manure_n);
        allocator.free(self.crop_price);
        allocator.free(self.fertilizer_price);
        allocator.free(self.investment_ratio);
    }
};

pub const OutputRow = struct {
    scenario: InputScenarioView,
    soil_zone: []const u8,
    soil_texture: []const u8,
    spring_moisture: []const u8,
    crop_name: []const u8,
    irrigation_name: []const u8,
    moisture_flag: []const u8,
    growing_precip: ScienceFloat,
    n_source_name: []const u8,
    n_time_name: []const u8,
    n_place_name: []const u8,
    previous_crop_name: []const u8,
    previous_crop_unit_name: []const u8,
    residue_name: []const u8,
    enr: ScienceFloat,
    residue_n_credit: ScienceFloat,
    plant_available_soil_n: ScienceFloat,
    n_rate: ScienceFloat,
    predicted_crop_yield: ?ScienceFloat = null,
    predicted_yield_increase: ?ScienceFloat = null,
    added_yield_increase: ?ScienceFloat = null,
    revenue: ?ScienceFloat = null,
    marginal_return: ?ScienceFloat = null,
    total_cost: ?ScienceFloat = null,
    marginal_cost: ?ScienceFloat = null,
    estimated_investment_ratio: ?ScienceFloat = null,
    recommended: bool = false,
    comment: ?[]const u8 = null,
};

pub const InputScenarioView = struct {
    index: i64,
    township: Id,
    range: Id,
    meridian_text: []const u8,
    som: ScienceFloat,
    soil_ph: ScienceFloat,
    soil_ec: ScienceFloat,
    soil_test_n: ScienceFloat,
    previous_crop_yield: ScienceFloat,
    manure_n: ScienceFloat,
    crop_price: ScienceFloat,
    fertilizer_price: ScienceFloat,
    investment_ratio: ScienceFloat,
};

pub fn roundDigits(comptime T: type, value: T, digits: comptime_int) T {
    const factor = std.math.pow(T, 10, @as(T, @floatFromInt(digits)));
    return @round(value * factor) / factor;
}

const testing = std.testing;

test "roundDigits rounds to the requested number of decimal digits" {
    try testing.expectEqual(@as(ScienceFloat, 3.0), roundDigits(ScienceFloat, 3.14159, 0));
    try testing.expectEqual(@as(ScienceFloat, 3.1), roundDigits(ScienceFloat, 3.14159, 1));
    try testing.expectEqual(@as(ScienceFloat, 3.14), roundDigits(ScienceFloat, 3.14159, 2));
}

test "roundDigits handles negative values and half-way rounding" {
    try testing.expectEqual(@as(ScienceFloat, -3.14), roundDigits(ScienceFloat, -3.14159, 2));
    try testing.expectEqual(@as(ScienceFloat, 2.0), roundDigits(ScienceFloat, 1.5, 0));
    try testing.expectEqual(@as(ScienceFloat, 1.0), roundDigits(ScienceFloat, 1.4999, 0));
}

test "InputScenario.deinit frees all owned slices without leaking" {
    const allocator = testing.allocator;
    var scenario = InputScenario{
        .index = 1,
        .township = 1,
        .range = 1,
        .meridian = 4,
        .meridian_text = try allocator.dupe(u8, "W4"),
        .som = try allocator.dupe(ScienceFloat, &.{2.0}),
        .soil_texture = try allocator.dupe(Id, &.{1}),
        .spring_soil_moisture = try allocator.dupe(Id, &.{1}),
        .soil_ph = try allocator.dupe(ScienceFloat, &.{6.5}),
        .soil_ec = try allocator.dupe(ScienceFloat, &.{0.2}),
        .current_crop = 1,
        .irrigation_flag = 1,
        .precip = try allocator.dupe(ScienceFloat, &.{200.0}),
        .irrigation_amount = try allocator.dupe(ScienceFloat, &.{0.0}),
        .n_source = 6,
        .n_time = try allocator.dupe(Id, &.{1}),
        .n_place = try allocator.dupe(Id, &.{1}),
        .soil_test_n = try allocator.dupe(ScienceFloat, &.{20.0}),
        .previous_crop = 2,
        .previous_crop_yield = try allocator.dupe(ScienceFloat, &.{10.0}),
        .previous_crop_yield_unit = 2,
        .residue_management = try allocator.dupe(Id, &.{1}),
        .manure_n = try allocator.dupe(ScienceFloat, &.{0.0}),
        .crop_price = try allocator.dupe(ScienceFloat, &.{8.0}),
        .fertilizer_price = try allocator.dupe(ScienceFloat, &.{700.0}),
        .investment_ratio = try allocator.dupe(ScienceFloat, &.{2.0}),
    };
    scenario.deinit(allocator);
}

test "InputScenarioView can be constructed with the expected shape" {
    const view = InputScenarioView{
        .index = 1,
        .township = 1,
        .range = 1,
        .meridian_text = "W4",
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
    try testing.expectEqual(@as(i64, 1), view.index);
    try testing.expectEqualStrings("W4", view.meridian_text);
}
