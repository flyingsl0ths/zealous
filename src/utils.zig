const std = @import("std");

pub fn copyBytes(allocator: std.mem.Allocator, value: []const u8) std.mem.Allocator.Error![]u8 {
    const len = value.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, copy, value);
    return copy;
}

pub inline fn floatEq(lhs: f64, rhs: f64) bool {
    return std.math.approxEqRel(f64, lhs, rhs, std.math.sqrt(std.math.floatEps(f64)));
}
