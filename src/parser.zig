const std = @import("std");

const lexer = @import("lexer.zig");
const object = @import("object.zig");
const token = @import("token.zig");

const ParserResult = union(enum) {
    err: lexer.TokenError,
    val: object.JsonValue,
};

const ParserError = std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error;

pub fn parse(source: lexer.str) ParserError!ParserResult {
    const lexr = lexer.init(source);

    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer allocator.deinit();

    // TODO: Handle errors
    return try parseValue(allocator, lexr);
}

fn parseArray(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    var array = std.ArrayList(object.JsonValue).init(allocator);

    errdefer array.deinit();

    var foundRightBracket = false;
    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                array.deinit();
                return ParserResult{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .Eof => {
                        if (!foundRightBracket) {
                            const message = if (comma != null) "Value expected." else "Expected comma or closing bracket.";

                            const tk_ = comma orelse tk;

                            return .{ .err = .{ .type_ = token.TokenType.Error, .line = tk_.line, .column = tk_.start, .cause = message } };
                        } else {
                            const message = if (comma != null and array.items.len > 0) "Trailing comma." else "Value expected.";

                            const tk_ = comma orelse tk;

                            return .{ .err = .{ .type_ = token.TokenType.Error, .line = tk_.line, .column = tk_.start, .cause = message } };
                        }

                        return .{.{ .array = array }};
                    },
                    .RightBracket => {
                        foundRightBracket = true;
                    },
                    .Comma => {
                        comma = tk;
                    },
                    else => {
                        const value = try parseValue(allocator, lexr);
                        array.append(value);
                    },
                }
            },
        }
    }
}

fn parseObject(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    var obj = std.StringArrayHashMap(object.JsonValue).init(allocator);

    errdefer obj.deinit();

    var foundRightBrace = false;
    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                obj.deinit();
                return ParserResult{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .Eof => {
                        if (!foundRightBrace) {
                            obj.deinit();

                            const message = if (comma != null)
                                "Property expected."
                            else
                                "Expected comma or closing brace.";

                            const tk_ = comma orelse tk;

                            return .{ .err = .{ .line = tk_.line, .column = tk_.start, .cause = message } };
                        } else {
                            const message = if (comma != null and obj.count() > 0) "Trailing comma." else "Property expected.";

                            obj.deinit();

                            const tk_ = comma orelse tk;

                            return .{ .err = .{ .line = tk_.line, .column = tk_.start, .cause = message } };
                        }

                        return object.JsonValue{ .object = obj };
                    },
                    .String => {
                        const key = copyString(allocator, lexr.lexeme[tk.start..tk.length]);
                        switch (lexer.scan(lexr)) {
                            .tokenError => |err| {
                                obj.deinit();
                                return .{ .err = err };
                            },
                            .token => |tk_| {
                                if (tk_.type_ != .Colon) {
                                    obj.deinit();
                                    return .{ .err = .{ .line = tk_.line, .column = tk_.start, .cause = "Expected colon." } };
                                }
                                const value = try parseValue(allocator, lexr);
                                obj.put(key, value);
                            },
                        }
                    },
                    .RightBrace => {
                        foundRightBrace = true;
                    },
                    .Comma => {
                        comma = tk;
                    },
                }
            },
        }
    }

    return .{ .val = .{ .object = obj } };
}

fn parseValue(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    switch (lexer.scan(lexr)) {
        .tokenError => |err| {
            return .{ .err = err };
        },
        .token => |tk| {
            switch (tk.type_) {
                .LeftBracket => {
                    const arr = try parseArray(allocator, lexr);
                    return arr;
                },
                .LeftBrace => {
                    const obj = try parseObject(allocator, lexr);
                    return obj;
                },
                .Int => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    const num = try std.fmt.parseInt(i32, str, 10);
                    return .{ .val = .{ .number = .{ .integer = num } } };
                },
                .Float => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    const num = try std.fmt.parseFloat(f64, str);
                    return .{ .val = .{ .number = .{ .float = num } } };
                },
                .String => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    return .{ .val = .{ .string = copyString(allocator, str) } };
                },
                .True => {
                    return .{ .val = .{ .boolean = true } };
                },
                .False => {
                    return .{.{ .boolean = false }};
                },
                .Null => {
                    return .{.{ .null_ = null }};
                },
                .RightBrace, .RightBracket, .Comma, .Colon => {
                    return .{ .err = .{ .line = tk.line, .column = tk.start, .cause = "Expected colon." } };
                },
                .Eof => {
                    return .{.{ .null_ = null }};
                },
                .Error => {
                    unreachable;
                },
            }
        },
    }
}

fn copyString(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const len = str.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, copy, str);
    return copy;
}

test "Parse literals" {
    var lxr = lexer.init("10");
    const res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(compareObjects(val_, object.JsonValue{ .number = .{ .integer = 10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseIntError.Overflow, std.fmt.ParseIntError.InvalidCharacter => {
                std.debug.print("Expected an integer", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error", .{});
                try std.testing.expect(false);
            },
        }
    }
}

fn compareObjects(expected: object.JsonValue, actual: object.JsonValue) bool {
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

fn objectsEqual(expected: std.StringArrayHashMap(object.JsonValue), actual: std.StringArrayHashMap(object.JsonValue)) bool {
    if (expected.count() != actual.count()) {
        return false;
    }

    var equal = false;

    for (expected.items) |pair| {
        if (actual.get(pair.key)) |actualValue| {
            equal = valuesEqual(pair.value, actualValue.value);
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

fn arraysEqual(expected: std.ArrayList(object.JsonValue), actual: std.ArrayList(object.JsonValue)) bool {
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

fn valuesEqual(expected: object.JsonValue, actual: object.JsonValue) bool {
    return switch (expected) {
        .number => |num| {
            switch (actual) {
                .number => |num2| num.integer == num2.integer,
                else => false,
            }
        },
        .string => |str| {
            switch (actual) {
                .string => |str2| str == str2,
                else => false,
            }
        },
        .boolean => |b| {
            switch (actual) {
                .boolean => |b2| b == b2,
                else => false,
            }
        },
        .null_ => {
            switch (actual) {
                .null_ => true,
                else => false,
            }
        },
        .object => |obj| objectsEqual(obj, actual),
        else => false,
    };
}
