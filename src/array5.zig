const std = @import("std");
const types = @import("types.zig");

pub const Array5 = struct {
    values: []types.ScienceFloat,
    place_count: usize,
    timing_count: usize,
    source_count: usize,
    soil_zone_count: usize,
    crop_count: usize,

    pub fn init(allocator: std.mem.Allocator, place_count: usize, timing_count: usize, source_count: usize, soil_zone_count: usize, crop_count: usize) !Array5 {
        const len = place_count * timing_count * source_count * soil_zone_count * crop_count;
        const values = try allocator.alloc(types.ScienceFloat, len);
        @memset(values, 0.0);
        return .{ .values = values, .place_count = place_count, .timing_count = timing_count, .source_count = source_count, .soil_zone_count = soil_zone_count, .crop_count = crop_count };
    }

    pub fn deinit(self: *Array5, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
    }

    pub fn set(self: *Array5, place_id: usize, timing_id: usize, source_id: usize, soil_zone_id: usize, crop_id: usize, value: types.ScienceFloat) !void {
        self.values[try self.index(place_id, timing_id, source_id, soil_zone_id, crop_id)] = value;
    }

    pub fn get(self: Array5, place_id: usize, timing_id: usize, source_id: usize, soil_zone_id: usize, crop_id: usize) types.ScienceFloat {
        return self.values[self.index(place_id, timing_id, source_id, soil_zone_id, crop_id) catch return 0.0];
    }

    fn index(self: Array5, place_id: usize, timing_id: usize, source_id: usize, soil_zone_id: usize, crop_id: usize) !usize {
        if (place_id == 0 or timing_id == 0 or source_id == 0 or soil_zone_id == 0 or crop_id == 0) return error.OutOfRange;
        if (place_id > self.place_count or timing_id > self.timing_count or source_id > self.source_count or soil_zone_id > self.soil_zone_count or crop_id > self.crop_count) return error.OutOfRange;
        const place_index = place_id - 1;
        const timing_index = timing_id - 1;
        const source_index = source_id - 1;
        const soil_zone_index = soil_zone_id - 1;
        const crop_index = crop_id - 1;
        return (((place_index * self.timing_count + timing_index) * self.source_count + source_index) * self.soil_zone_count + soil_zone_index) * self.crop_count + crop_index;
    }
};

const testing = @import("std").testing;

test "init/deinit round trip and default zero values" {
    var arr = try Array5.init(testing.allocator, 2, 2, 2, 2, 2);
    defer arr.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 32), arr.values.len);
    try testing.expectEqual(@as(types.ScienceFloat, 0.0), arr.get(1, 1, 1, 1, 1));
}

test "set then get round-trips a value at a given coordinate" {
    var arr = try Array5.init(testing.allocator, 3, 3, 3, 3, 3);
    defer arr.deinit(testing.allocator);
    try arr.set(2, 3, 1, 2, 3, 42.5);
    try testing.expectEqual(@as(types.ScienceFloat, 42.5), arr.get(2, 3, 1, 2, 3));
}

test "distinct coordinates do not alias each other" {
    var arr = try Array5.init(testing.allocator, 2, 2, 2, 2, 2);
    defer arr.deinit(testing.allocator);
    try arr.set(1, 1, 1, 1, 1, 1.0);
    try arr.set(1, 1, 1, 1, 2, 2.0);
    try arr.set(1, 1, 1, 2, 1, 3.0);
    try arr.set(1, 1, 2, 1, 1, 4.0);
    try arr.set(1, 2, 1, 1, 1, 5.0);
    try arr.set(2, 1, 1, 1, 1, 6.0);
    try testing.expectEqual(@as(types.ScienceFloat, 1.0), arr.get(1, 1, 1, 1, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 2.0), arr.get(1, 1, 1, 1, 2));
    try testing.expectEqual(@as(types.ScienceFloat, 3.0), arr.get(1, 1, 1, 2, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 4.0), arr.get(1, 1, 2, 1, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 5.0), arr.get(1, 2, 1, 1, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 6.0), arr.get(2, 1, 1, 1, 1));
}

test "get on an out-of-range coordinate returns 0.0 instead of erroring" {
    var arr = try Array5.init(testing.allocator, 2, 2, 2, 2, 2);
    defer arr.deinit(testing.allocator);
    try arr.set(1, 1, 1, 1, 1, 9.0);
    try testing.expectEqual(@as(types.ScienceFloat, 0.0), arr.get(0, 1, 1, 1, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 0.0), arr.get(3, 1, 1, 1, 1));
    try testing.expectEqual(@as(types.ScienceFloat, 0.0), arr.get(1, 1, 1, 1, 3));
}

test "set on an out-of-range coordinate returns error.OutOfRange" {
    var arr = try Array5.init(testing.allocator, 2, 2, 2, 2, 2);
    defer arr.deinit(testing.allocator);
    try testing.expectError(error.OutOfRange, arr.set(0, 1, 1, 1, 1, 1.0));
    try testing.expectError(error.OutOfRange, arr.set(3, 1, 1, 1, 1, 1.0));
    try testing.expectError(error.OutOfRange, arr.set(1, 1, 1, 1, 3, 1.0));
}
