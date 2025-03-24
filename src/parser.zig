const std = @import("std");

const utils = @import("utils.zig");
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
    var arr = std.ArrayList(object.JsonValue).init(allocator);

    errdefer arr.deinit();

    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                arr.deinit();
                return .{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .RightBracket => {
                        return if (comma) |comma_| .{ .err = .{ .type_ = token.TokenType.Error, .line = comma_.line, .column = comma_.start, .cause = "Trailing comma" } } else .{ .val = .{ .array = arr } };
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
                        switch (try toValue(allocator, tk, lexr)) {
                            .err => |err| {
                                return .{ .err = err };
                            },
                            .val => |value| {
                                try arr.append(value);
                                comma = null;
                            },
                        }
                    },
                }
            },
        }
    }
}

fn parseObject(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    var obj: object.JsonValue = .{ .object = std.StringArrayHashMap(object.JsonValue).init(allocator) };

    errdefer object.deinit(obj);

    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(lexr)) {
            .tokenError => |err| {
                object.deinit(obj);
                return .{ .err = err };
            },
            .token => |tk| {
                switch (tk.type_) {
                    .RightBrace => {
                        return .{ .val = obj };
                    },

                    .String => {
                        const key = lexr.lexeme[tk.start..(tk.start + tk.length)];

                        switch (lexer.scan(lexr)) {
                            .tokenError => |err| {
                                object.deinit(obj);
                                return .{ .err = err };
                            },
                            .token => |tk_| {
                                if (tk_.type_ != .Colon) {
                                    object.deinit(obj);
                                    return .{ .err = .{ .type_ = .Error, .line = tk_.line, .column = tk_.start, .cause = "Colon expected." } };
                                }

                                const val = try parseValue(allocator, lexr);

                                switch (val) {
                                    .err => {
                                        object.deinit(obj);
                                        return val;
                                    },
                                    .val => |value| {
                                        const key_: []u8 = try utils.copyBytes(allocator, key);
                                        try obj.object.put(key_, value);
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

                        const has_keys = obj.object.count() != 0;

                        if ((comma != null and has_keys) or (comma == null and !has_keys)) {
                            message = "Property expected.";
                        } else {
                            message = "Expected comma or closing brace";
                        }

                        object.deinit(obj);

                        const tk_ = comma orelse tk;

                        return if (message) |message_| .{ .err = .{ .type_ = .Error, .line = tk_.line, .column = tk_.start, .cause = message_ } } else .{ .val = obj };
                    },

                    else => {
                        return .{ .err = .{ .type_ = .Error, .line = tk.line, .column = tk.start, .cause = "Property expected." } };
                    },
                }
            },
        }
    }

    return .{ .val = obj };
}

fn parseValue(allocator: std.mem.Allocator, lexr: *lexer.Lexer) ParserError!ParserResult {
    switch (lexer.scan(lexr)) {
        .tokenError => |err| {
            return .{ .err = err };
        },
        .token => |tk| {
            return toValue(allocator, tk, lexr);
        },
    }
}

fn toValue(allocator: std.mem.Allocator, tk: token.Token, lexr: *lexer.Lexer) ParserError!ParserResult {
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
            const str = lexr.lexeme[tk.start .. tk.start + tk.length];

            const num = try std.fmt.parseInt(i32, str, 10);
            return .{ .val = .{ .number = .{ .integer = num } } };
        },
        .Float => {
            const str = lexr.lexeme[tk.start..tk.length];
            const num = try std.fmt.parseFloat(f64, str);
            return .{ .val = .{ .number = .{ .float = num } } };
        },
        .String => {
            return .{ .val = try object.mkString(allocator, lexr.lexeme[tk.start..(tk.start + tk.length)]) };
        },
        .True => {
            return .{ .val = .{ .boolean = true } };
        },
        .False => {
            return .{ .val = .{ .boolean = false } };
        },
        .Null => {
            return .{ .val = object.mkNull() };
        },
        .Eof => {
            return .{ .val = object.mkNull() };
        },
        else => unreachable,
    }
}

test "Numbers" {
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
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("-10");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .integer = -10 } }));
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

    lxr = lexer.init("-10.1");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = -10.1 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("1e10");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = 1e10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("1E10");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = 1E10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("-1e10");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = -1e10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("1e+10");
    res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = 1e+10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }

    lxr = lexer.init("1e-10");
    res = parseValue(std.testing.allocator, &lxr);
    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.JsonValue{ .number = .{ .float = 1e-10 } }));
            },
        }
    } else |err| {
        switch (err) {
            std.fmt.ParseFloatError.InvalidCharacter => {
                std.debug.print("Expected an floating point number", .{});
                try std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error, expected float parsing error", .{});
                try std.testing.expect(false);
            },
        }
    }
}

test "Bool" {
    inline for (.{ "true", "false" }) |source| {
        var lxr = lexer.init(source);
        const res = parseValue(std.testing.allocator, &lxr);

        if (res) |val| {
            switch (val) {
                .err => |err| {
                    std.debug.print("Error: {}\n", .{err});
                    try std.testing.expect(false);
                },
                .val => |val_| {
                    try std.testing.expect(object.eq(val_, object.JsonValue{ .boolean = if (std.mem.eql(u8, source, "true")) true else false }));
                },
            }
        } else |err| {
            switch (err) {
                std.mem.Allocator.Error.OutOfMemory => {
                    std.debug.print("Out of memory!", .{});
                    try std.testing.expect(false);
                },
                else => unreachable,
            }
        }
    }
}

test "Null" {
    var lxr = lexer.init("null");
    const res = parseValue(std.testing.allocator, &lxr);

    if (res) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                try std.testing.expect(object.eq(val_, object.mkNull()));
            },
        }
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => {
                std.debug.print("Out of memory!", .{});
                try std.testing.expect(false);
            },
            else => unreachable,
        }
    }
}

test "Strings" {
    var lxr = lexer.init("\"hello\"");

    if (parseValue(std.testing.allocator, &lxr)) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                const str = try object.mkString(std.testing.allocator, "\"hello\"");

                defer object.deinit(str);
                errdefer object.deinit(str);
                defer object.deinit(val_);

                try std.testing.expect(object.eq(val_, str));
            },
        }
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => {
                std.debug.print("Out of memory!", .{});
                try std.testing.expect(false);
            },
            else => unreachable,
        }
    }
}

test "Arrays" {
    var lxr = lexer.init("[1, true, \"hello\"]");
    if (parseValue(std.testing.allocator, &lxr)) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                var js = std.ArrayList(object.JsonValue).init(std.testing.allocator);

                defer object.deinit(val_);
                defer object.deinit(.{ .array = js });
                errdefer object.deinit(.{ .array = js });

                try js.append(.{ .number = .{ .integer = 1 } });
                try js.append(.{ .boolean = true });
                try js.append(try object.mkString(std.testing.allocator, "\"hello\""));

                try std.testing.expect(object.eq(val_, .{ .array = js }));
            },
        }
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => {
                std.debug.print("Out of memory!", .{});
                try std.testing.expect(false);
            },
            else => unreachable,
        }
    }
}

test "Objects" {
    var lxr = lexer.init("{\"hello\":\n\"world\", \"foo\": 1}");

    const t_alloc = std.testing.allocator;
    if (parseValue(t_alloc, &lxr)) |val| {
        switch (val) {
            .err => |err| {
                std.debug.print("Error: {}\n", .{err});
                try std.testing.expect(false);
            },
            .val => |val_| {
                var obj = std.StringArrayHashMap(object.JsonValue).init(t_alloc);

                defer object.deinit(val_);
                defer object.deinit(.{ .object = obj });
                errdefer object.deinit(.{ .object = obj });

                try obj.put(try utils.copyBytes(t_alloc, "\"hello\""), try object.mkString(t_alloc, "\"world\""));
                try obj.put(try utils.copyBytes(t_alloc, "\"foo\""), .{ .number = .{ .integer = 1 } });

                try std.testing.expect(object.eq(val_, .{ .object = obj }));
            },
        }
    } else |err| {
        switch (err) {
            std.mem.Allocator.Error.OutOfMemory => {
                std.debug.print("Out of memory!", .{});
                try std.testing.expect(false);
            },
            else => unreachable,
        }
    }
}
