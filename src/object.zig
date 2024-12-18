const std = @import("std");

const JsonNil = .{};

pub fn mkNull() @TypeOf(JsonNil) {
    return JsonNil;
}

pub const JsonValue = union(enum) {
    object: std.StringArrayHashMap(JsonValue),
    array: std.ArrayList(JsonValue),
    number: union(enum) { integer: i32, float: f64 },
    string: []u8,
    boolean: bool,
    null_: @TypeOf(mkNull()),
};

pub fn compareObjects(expected: JsonValue, actual: JsonValue) bool {
    return switch (expected) {
        .object => |obj| switch (actual) {
            .object => |obj2| objectsEqual(obj, obj2),
            else => false,
        },
        .array => |arr| switch (actual) {
            .array => |arr2| arraysEqual(arr, arr2),
            else => false,
        },
        else => valuesEqual(expected, actual),
    };
}

pub fn objectsEqual(expected: std.StringArrayHashMap(JsonValue), actual: std.StringArrayHashMap(JsonValue)) bool {
    if (expected.count() != actual.count()) {
        return false;
    }

    var equal = false;

    for (expected.keys(), expected.values()) |expectedKey, expectedValue| {
        if (actual.get(expectedKey)) |actualValue| {
            equal = valuesEqual(expectedValue, actualValue);
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

pub fn arraysEqual(expected: std.ArrayList(JsonValue), actual: std.ArrayList(JsonValue)) bool {
    if (expected.items.len != actual.items.len) {
        return false;
    }

    var equal = false;

    for (expected.items, 0..) |expectedValue, i| {
        const actualValue = actual.items[i];
        equal = valuesEqual(expectedValue, actualValue);
        if (!equal) {
            break;
        }
    }

    return equal;
}

pub fn valuesEqual(expected: JsonValue, actual: JsonValue) bool {
    switch (expected) {
        .number => |num| {
            switch (actual) {
                .number => |num2| return num.integer == num2.integer,
                else => return false,
            }
        },
        .string => |str| {
            switch (actual) {
                .string => |str2| return std.mem.eql(u8, str, str2),
                else => return false,
            }
        },
        .boolean => |b| {
            switch (actual) {
                .boolean => |b2| return b == b2,
                else => return false,
            }
        },
        .null_ => {
            switch (actual) {
                .null_ => return true,
                else => return false,
            }
        },
        .object => |obj| switch (actual) {
            .object => |obj2| return objectsEqual(obj, obj2),
            else => return false,
        },
        else => return false,
    }
}
