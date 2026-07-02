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
