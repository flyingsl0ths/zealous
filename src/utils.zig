const std = @import("std");

pub fn copyBytes(allocator: std.mem.Allocator, value: []const u8) std.mem.Allocator.Error![]u8 {
    const len = value.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, copy, value);
    return copy;
}

pub fn floatEq(comptime T: type, lhs: T, rhs: T) bool {
    return switch (@typeInfo(T)) {
        .Float => std.math.approxEqRel(T, lhs, rhs, std.math.sqrt(std.math.floatEps(T))),
        else => false,
    };
}
