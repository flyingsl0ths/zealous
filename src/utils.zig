const std = @import("std");

pub fn copyBytes(allocator: std.mem.Allocator, value: []const u8) std.mem.Allocator.Error![]u8 {
    const len = value.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, copy, value);
    return copy;
}
