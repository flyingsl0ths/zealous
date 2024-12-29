const std = @import("std");

const lexer = @import("lexer.zig");
const object = @import("object.zig");
const token = @import("token.zig");

const ParserResult = union(enum) {
    val: object.JsonValue,
    err: lexer.TokenError,
};

const ParserError = std.fmt.ParseIntError || std.fmt.ParseFloatError || std.mem.Allocator.Error;

pub fn parse(source: lexer.str) ParserError!ParserResult {
    const lexr = lexer.init(source);

    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    return try parseValue(allocator, lexr);
}

fn parseArray(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    var array = std.ArrayList(object.JsonValue).init(allocator);

    errdefer array.deinit();

    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                array.deinit();
                return .{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .RightBracket => {
                        return if (comma != null) .{ .err = .{ .type_ = token.TokenType.Error, .line = tk.line, .column = tk.start, .cause = "Trailing comma" } } else .{ .val = .{ .array = array } };
                    },
                    .Comma => {
                        comma = tk;
                    },
                    .Eof => {
                        const message = if (comma != null) "Value expected." else "Expected comma or closing bracket.";

                        const tk_ = comma orelse tk;

                        return .{ .err = .{ .type_ = token.TokenType.Error, .line = tk_.line, .column = tk_.start, .cause = message } };
                    },
                    else => {
                        switch (try parseValue(allocator, lexr)) {
                            .err => |err| {
                                array.deinit();
                                return .{ .err = err };
                            },
                            .val => |value| {
                                try array.append(value);
                            },
                        }
                    },
                }
            },
        }
    }
}

fn parseObject(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    var obj = std.StringArrayHashMap(object.JsonValue).init(allocator);

    errdefer obj.deinit();

    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                obj.deinit();
                return .{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .RightBrace => {
                        return .{ .val = .{ .object = obj } };
                    },

                    .String => {
                        const key = lexr.lexeme[tk.start..tk.length];

                        switch (lexer.scan(lexr)) {
                            .tokenError => |err| {
                                obj.deinit();
                                return .{ .err = err };
                            },
                            .token => |tk_| {
                                if (tk_.type_ != .Colon) {
                                    obj.deinit();
                                    return .{ .err = .{ .type_ = .Error, .line = tk_.line, .column = tk_.start, .cause = "Colon expected." } };
                                }

                                const val = try parseValue(allocator, lexr);
                                switch (val) {
                                    .err => {
                                        obj.deinit();
                                        return val;
                                    },
                                    .val => |value| {
                                        try obj.put(key, value);
                                    },
                                }
                            },
                        }
                    },

                    .Comma => {
                        comma = tk;
                    },

                    .Eof => {
                        var message: ?[:0]const u8 = null;
                        const has_keys = obj.count() != 0;
                        if ((comma != null and has_keys) or (comma == null and !has_keys)) {
                            message = "Property expected.";
                        } else {
                            message = "Expected comma or closing brace";
                        }

                        obj.deinit();

                        const tk_ = comma orelse tk;

                        return if (message) |message_| .{ .err = .{ .type_ = .Error, .line = tk_.line, .column = tk_.start, .cause = message_ } } else .{ .val = .{ .object = obj } };
                    },

                    else => {
                        return .{ .err = .{ .type_ = .Error, .line = tk.line, .column = tk.start, .cause = "Property expected." } };
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
                    return .{ .val = .{ .string = try object.mkString(allocator, lexr.lexeme[tk.start..tk.length]) } };
                },
                .True => {
                    return .{ .val = .{ .boolean = true } };
                },
                .False => {
                    return .{ .val = .{ .boolean = false } };
                },
                .Null => {
                    return .{ .val = .{ .null = object.mkNull() } };
                },
                .RightBrace, .RightBracket, .Comma, .Colon => {
                    return .{ .err = .{ .line = tk.line, .column = tk.start, .cause = "Expected colon.", .type_ = tk.type_ } };
                },
                .Eof => {
                    return .{ .val = .{ .null = object.mkNull() } };
                },
                .Error => {
                    unreachable;
                },
            }
        },
    }
}

test "Parse literals" {
    var lxr = lexer.init("10");
    var res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .integer = 10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseIntError.Overflow, std.fmt.ParseIntError.InvalidCharacter => {
                std.debug.print("Expected an integer", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected int parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("10.1");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = 10.1 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected int parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }
}
