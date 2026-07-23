const std = @import("std");
const input = @import("input.zig");
const types = @import("types.zig");

test {
    _ = @import("array5.zig");
    _ = @import("types.zig");
    _ = @import("input.zig");
    _ = @import("coefficients.zig");
    _ = @import("model.zig");
    _ = @import("batch.zig");
    _ = @import("affirm_spatial.zig");
}

test "step distribution parses inclusive range" {
    const allocator = std.testing.allocator;
    var scenario = try input.parseScenario(allocator, "1,10,2,W4,2|4|1|1,3,2,6.5,0.2,1,1,, ,6,1,1,20,2,10,2,1,0,8,700,2");
    defer scenario.deinit(allocator);
    try std.testing.expectEqualSlices(types.ScienceFloat, &.{ 2.0, 3.0, 4.0 }, scenario.som);
    try std.testing.expectEqual(@as(types.Id, 4), scenario.meridian);
}
