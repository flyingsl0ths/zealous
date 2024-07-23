const std = @import("std");

export const JsonValue = union(enum) {
    object: std.StringArrayHashMap(JsonValue),
    array: std.ArrayList(JsonValue),
    number: union(enum) { integer: i32, float: f64 },
    string: []u8,
    boolean: bool,
    null_: null,
};
