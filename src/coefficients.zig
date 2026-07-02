const std = @import("std");
const Array5 = @import("array5.zig").Array5;
const types = @import("types.zig");

const max_township = 126;
const max_range = 30;
const max_meridian = 6;
const max_crop = 64;
const max_prev_crop = 80;
const max_yield_unit = 4;
const max_texture = 16;
const max_moisture = 4;
const max_source = 16;
const max_time = 4;
const max_place = 8;
const max_soil_zone = 16;
const max_irrigation = 3;
const max_residue = 4;

pub const Coefficients = struct {
    allocator: std.mem.Allocator,
    crop_name: []?[]const u8,
    previous_crop: []?[]const u8,
    previous_crop_yld_unit: []?[]const u8,
    residue_management: []?[]const u8,
    soil_zone: []?[]const u8,
    n_source: []?[]const u8,
    n_time: []?[]const u8,
    n_place: []?[]const u8,
    soil_texture: []?[]const u8,
    spring_moisture_condition: []?[]const u8,
    irrigation_flag: []?[]const u8,
    n_source_percent_n: []types.ScienceFloat,
    crop_unit_conv_coef: []types.ScienceFloat,
    spring_soil_moisture: []types.ScienceFloat,
    b0ph: []types.ScienceFloat,
    b1ph: []types.ScienceFloat,
    b2ph: []types.ScienceFloat,
    phmax: []types.ScienceFloat,
    phmin: []types.ScienceFloat,
    b0ec: []types.ScienceFloat,
    b1ec: []types.ScienceFloat,
    b0precip: []types.ScienceFloat,
    b1precip: []types.ScienceFloat,
    soil_zone_id: []types.Id,
    b0ag: []types.ScienceFloat,
    b0bg: []types.ScienceFloat,
    wue: Array5,
    epsilon: Array5,
    nminus1: Array5,
    owned_strings: std.array_list.Managed([]const u8),

    pub fn load(allocator: std.mem.Allocator) !Coefficients {
        var coeff = Coefficients{
            .allocator = allocator,
            .crop_name = try allocOpt(allocator, max_crop + 1),
            .previous_crop = try allocOpt(allocator, max_prev_crop + 1),
            .previous_crop_yld_unit = try allocOpt(allocator, max_yield_unit + 1),
            .residue_management = try allocOpt(allocator, max_residue + 1),
            .soil_zone = try allocOpt(allocator, max_soil_zone + 1),
            .n_source = try allocOpt(allocator, max_source + 1),
            .n_time = try allocOpt(allocator, max_time + 1),
            .n_place = try allocOpt(allocator, max_place + 1),
            .soil_texture = try allocOpt(allocator, max_texture + 1),
            .spring_moisture_condition = try allocOpt(allocator, max_moisture + 1),
            .irrigation_flag = try allocOpt(allocator, max_irrigation + 1),
            .n_source_percent_n = try allocReal(allocator, max_source + 1),
            .crop_unit_conv_coef = try allocReal(allocator, max_crop + 1),
            .spring_soil_moisture = try allocReal(allocator, (max_moisture + 1) * (max_texture + 1)),
            .b0ph = try allocReal(allocator, max_crop + 1),
            .b1ph = try allocReal(allocator, max_crop + 1),
            .b2ph = try allocReal(allocator, max_crop + 1),
            .phmax = try allocReal(allocator, max_crop + 1),
            .phmin = try allocReal(allocator, max_crop + 1),
            .b0ec = try allocReal(allocator, max_crop + 1),
            .b1ec = try allocReal(allocator, max_crop + 1),
            .b0precip = try allocReal(allocator, (max_township + 1) * (max_range + 1) * (max_meridian + 1)),
            .b1precip = try allocReal(allocator, (max_township + 1) * (max_range + 1) * (max_meridian + 1)),
            .soil_zone_id = try allocator.alloc(types.Id, (max_township + 1) * (max_range + 1) * (max_meridian + 1)),
            .b0ag = try allocReal(allocator, (max_prev_crop + 1) * (max_yield_unit + 1)),
            .b0bg = try allocReal(allocator, (max_prev_crop + 1) * (max_yield_unit + 1)),
            .wue = try Array5.init(allocator, max_place, max_time, max_source, max_soil_zone, max_crop),
            .epsilon = try Array5.init(allocator, max_place, max_time, max_source, max_soil_zone, max_crop),
            .nminus1 = try Array5.init(allocator, max_place, max_time, max_source, max_soil_zone, max_crop),
            .owned_strings = std.array_list.Managed([]const u8).init(allocator),
        };
        @memset(coeff.soil_zone_id, 0);
        errdefer coeff.deinit();

        try coeff.loadNames();
        try loadOneValue("n_source_percent_n.bin", coeff.n_source_percent_n);
        try loadOneValue("crop_unit_conv_coef.bin", coeff.crop_unit_conv_coef);
        try coeff.loadSpringMoisture();
        try coeff.loadPh();
        try coeff.loadEc();
        try coeff.loadPrecip();
        try coeff.loadResponse();
        try coeff.loadResidue();
        return coeff;
    }

    pub fn deinit(self: *Coefficients) void {
        for (self.owned_strings.items) |value| self.allocator.free(value);
        self.owned_strings.deinit();
        self.wue.deinit(self.allocator);
        self.epsilon.deinit(self.allocator);
        self.nminus1.deinit(self.allocator);
        inline for (.{ "crop_name", "previous_crop", "previous_crop_yld_unit", "residue_management", "soil_zone", "n_source", "n_time", "n_place", "soil_texture", "spring_moisture_condition", "irrigation_flag", "n_source_percent_n", "crop_unit_conv_coef", "spring_soil_moisture", "b0ph", "b1ph", "b2ph", "phmax", "phmin", "b0ec", "b1ec", "b0precip", "b1precip", "soil_zone_id", "b0ag", "b0bg" }) |field| {
            self.allocator.free(@field(self, field));
        }
    }

    pub fn name(self: Coefficients, table: []?[]const u8, id: usize) []const u8 {
        _ = self;
        if (id < table.len) return table[id] orelse "";
        return "";
    }

    pub fn precipIndex(_: Coefficients, township: usize, range: usize, meridian: usize) usize {
        return (township * (max_range + 1) + range) * (max_meridian + 1) + meridian;
    }

    pub fn springMoisture(self: Coefficients, moisture_id: usize, texture_id: usize) types.ScienceFloat {
        const idx = moisture_id * (max_texture + 1) + texture_id;
        return if (idx < self.spring_soil_moisture.len) self.spring_soil_moisture[idx] else 0.0;
    }

    pub fn residueIndex(_: Coefficients, previous_crop_id: usize, yield_unit_id: usize) usize {
        return previous_crop_id * (max_yield_unit + 1) + yield_unit_id;
    }

    fn loadNames(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("names.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const kind = try reader.stringView();
            const id = try reader.readU16();
            const label = try self.allocator.dupe(u8, try reader.stringView());
            errdefer self.allocator.free(label);
            try self.owned_strings.append(label);
            if (std.mem.eql(u8, kind, "crop_name") and id < self.crop_name.len) self.crop_name[id] = label else if (std.mem.eql(u8, kind, "previous_crop") and id < self.previous_crop.len) self.previous_crop[id] = label else if (std.mem.eql(u8, kind, "previous_crop_yld_unit") and id < self.previous_crop_yld_unit.len) self.previous_crop_yld_unit[id] = label else if (std.mem.eql(u8, kind, "residue_management") and id < self.residue_management.len) self.residue_management[id] = label else if (std.mem.eql(u8, kind, "soil_zone") and id < self.soil_zone.len) self.soil_zone[id] = label else if (std.mem.eql(u8, kind, "n_source") and id < self.n_source.len) self.n_source[id] = label else if (std.mem.eql(u8, kind, "n_time") and id < self.n_time.len) self.n_time[id] = label else if (std.mem.eql(u8, kind, "n_place") and id < self.n_place.len) self.n_place[id] = label else if (std.mem.eql(u8, kind, "soil_texture") and id < self.soil_texture.len) self.soil_texture[id] = label else if (std.mem.eql(u8, kind, "spring_moisture_condition") and id < self.spring_moisture_condition.len) self.spring_moisture_condition[id] = label else if (std.mem.eql(u8, kind, "irrigation_flag") and id < self.irrigation_flag.len) self.irrigation_flag[id] = label;
        }
    }

    fn loadOneValue(file_name: []const u8, values: []types.ScienceFloat) !void {
        var reader = BinReader{ .data = embeddedData(file_name) };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const id = try reader.readU16();
            const value = try reader.readF32();
            if (id < values.len) values[id] = value;
        }
    }

    fn loadSpringMoisture(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("spring_soil_moisture.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const moisture_id = try reader.readU16();
            const texture_id = try reader.readU16();
            const idx = moisture_id * (max_texture + 1) + texture_id;
            if (idx < self.spring_soil_moisture.len) self.spring_soil_moisture[idx] = try reader.readF32() else _ = try reader.readF32();
        }
    }

    fn loadPh(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("ph.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const crop = try reader.readU16();
            const b0 = try reader.readF32();
            const b1 = try reader.readF32();
            const b2 = try reader.readF32();
            const min = try reader.readF32();
            const max = try reader.readF32();
            if (crop < self.b0ph.len) {
                self.b0ph[crop] = b0;
                self.b1ph[crop] = b1;
                self.b2ph[crop] = b2;
                self.phmin[crop] = min;
                self.phmax[crop] = max;
            }
        }
    }

    fn loadEc(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("ec.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const crop = try reader.readU16();
            const b0 = try reader.readF32();
            const b1 = try reader.readF32();
            if (crop < self.b0ec.len) {
                self.b0ec[crop] = b0;
                self.b1ec[crop] = b1;
            }
        }
    }

    fn loadPrecip(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("precip.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const idx = self.precipIndex(try reader.readU16(), try reader.readU16(), try reader.readU16());
            const b0 = try reader.readF32();
            const b1 = try reader.readF32();
            const soil_zone = try reader.readU16();
            if (idx < self.b0precip.len) {
                self.b0precip[idx] = b0;
                self.b1precip[idx] = b1;
                self.soil_zone_id[idx] = soil_zone;
            }
        }
    }

    fn loadResponse(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("response.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const place_id = try reader.readU16();
            const timing_id = try reader.readU16();
            const source_id = try reader.readU16();
            const soil_zone_id = try reader.readU16();
            const crop_id = try reader.readU16();
            try self.wue.set(place_id, timing_id, source_id, soil_zone_id, crop_id, try reader.readF32());
            try self.epsilon.set(place_id, timing_id, source_id, soil_zone_id, crop_id, try reader.readF32());
            try self.nminus1.set(place_id, timing_id, source_id, soil_zone_id, crop_id, try reader.readF32());
        }
    }

    fn loadResidue(self: *Coefficients) !void {
        var reader = BinReader{ .data = embeddedData("residue.bin") };
        const count = try reader.readU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const idx = self.residueIndex(try reader.readU16(), try reader.readU16());
            const b0ag = try reader.readF32();
            const b0bg = try reader.readF32();
            if (idx < self.b0ag.len) {
                self.b0ag[idx] = b0ag;
                self.b0bg[idx] = b0bg;
            }
        }
    }
};

const BinReader = struct {
    data: []const u8,
    pos: usize = 0,

    fn bytes(self: *BinReader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.InvalidCoefficientBinary;
        const out = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return out;
    }

    fn readU16(self: *BinReader) !u16 {
        return std.mem.readInt(u16, (try self.bytes(2))[0..2], .little);
    }

    fn readU32(self: *BinReader) !u32 {
        return std.mem.readInt(u32, (try self.bytes(4))[0..4], .little);
    }

    fn readF32(self: *BinReader) !f32 {
        return @bitCast(try self.readU32());
    }

    fn stringView(self: *BinReader) ![]const u8 {
        return try self.bytes(try self.readU16());
    }
};

fn embeddedData(file: []const u8) []const u8 {
    if (std.mem.eql(u8, file, "names.bin")) return @embedFile("embedded_data/names.bin");
    if (std.mem.eql(u8, file, "n_source_percent_n.bin")) return @embedFile("embedded_data/n_source_percent_n.bin");
    if (std.mem.eql(u8, file, "crop_unit_conv_coef.bin")) return @embedFile("embedded_data/crop_unit_conv_coef.bin");
    if (std.mem.eql(u8, file, "spring_soil_moisture.bin")) return @embedFile("embedded_data/spring_soil_moisture.bin");
    if (std.mem.eql(u8, file, "ph.bin")) return @embedFile("embedded_data/ph.bin");
    if (std.mem.eql(u8, file, "ec.bin")) return @embedFile("embedded_data/ec.bin");
    if (std.mem.eql(u8, file, "precip.bin")) return @embedFile("embedded_data/precip.bin");
    if (std.mem.eql(u8, file, "response.bin")) return @embedFile("embedded_data/response.bin");
    if (std.mem.eql(u8, file, "residue.bin")) return @embedFile("embedded_data/residue.bin");
    unreachable;
}

fn allocReal(allocator: std.mem.Allocator, len: usize) ![]types.ScienceFloat {
    const values = try allocator.alloc(types.ScienceFloat, len);
    @memset(values, 0.0);
    return values;
}

fn allocOpt(allocator: std.mem.Allocator, len: usize) ![]?[]const u8 {
    const values = try allocator.alloc(?[]const u8, len);
    @memset(values, null);
    return values;
}
