const std = @import("std");

const JsonNil = .{};

const JsonString = struct {
    value: []u8,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, value: []const u8) std.mem.Allocator.Error!JsonString {
        const len = value.len;
        const copy = try allocator.alloc(u8, len);
        std.mem.copyForwards(u8, copy, value);

        return JsonString{ .value = copy, .allocator = allocator };
    }

    fn deinit(self: *JsonString) void {
        self.allocator.free(self.value);
    }
};

pub const JsonValue = union(enum) {
    object: std.StringArrayHashMap(JsonValue),
    array: std.ArrayList(JsonValue),
    number: union(enum) { integer: i32, float: f64 },
    string: JsonString,
    boolean: bool,
    null: @TypeOf(JsonNil),

    fn deinit(self: *JsonValue) void {
        switch (self.value) {
            .string => self.value.string.deinit(),
            .object => self.value.object.deinit(),
            .array => self.value.array.deinit(),
            else => unreachable,
        }
    }
};

pub fn mkNull() JsonValue {
    return .{ .null = JsonNil };
}

pub fn mkString(allocator: std.mem.Allocator, str: []const u8) !JsonString {
    return JsonString.init(allocator, str);
}

pub fn eq(lhs: JsonValue, rhs: JsonValue) bool {
    switch (lhs) {
        .object => switch (rhs) {
            .object => return objectsEq(lhs.object, rhs.object),
            else => return false,
        },

        .array => switch (rhs) {
            .array => return arraysEq(lhs.array, rhs.array),
            else => return false,
        },
        else => return valuesEq(lhs, rhs),
    }
}

pub fn objectsEq(lhs: std.StringArrayHashMap(JsonValue), rhs: std.StringArrayHashMap(JsonValue)) bool {
    if (lhs.count() != rhs.count()) {
        return false;
    }

    var equal = false;

    for (lhs.keys(), lhs.values()) |expectedKey, expectedValue| {
        if (rhs.get(expectedKey)) |actualValue| {
            equal = valuesEq(expectedValue, actualValue);
            if (!equal) {
                break;
            }
        } else {
            equal = false;
            break;
        }
    }

    return equal;
}

pub fn arraysEq(lhs: std.ArrayList(JsonValue), rhs: std.ArrayList(JsonValue)) bool {
    if (lhs.items.len != rhs.items.len) {
        return false;
    }

    var equal = false;

    for (lhs.items, 0..) |left, i| {
        const right = rhs.items[i];
        equal = valuesEq(left, right);
        if (!equal) {
            break;
        }
    }

    return equal;
}

pub fn valuesEq(lhs: JsonValue, rhs: JsonValue) bool {
    switch (lhs) {
        .number => {
            switch (rhs) {
                .number => switch (lhs.number) {
                    .integer => switch (rhs.number) {
                        .integer => return lhs.number.integer == rhs.number.integer,
                        else => return false,
                    },
                    .float => switch (rhs.number) {
                        .float => return std.math.approxEqRel(f64, lhs.number.float, rhs.number.float, std.math.sqrt(std.math.floatEps(f64))),
                        else => return false,
                    },
                },
                else => return false,
            }
        },

        .string => switch (rhs) {
            .string => return std.mem.eql(u8, lhs.string.value, rhs.string.value),
            else => return false,
        },

        .boolean => switch (rhs) {
            .boolean => return lhs.boolean == rhs.boolean,
            else => return false,
        },

        .null => switch (rhs) {
            .null => return true,
            else => return false,
        },

        else => unreachable,
    }
}
