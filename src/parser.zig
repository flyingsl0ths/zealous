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
                            array.deinit();
                            const message = if (comma != null) "Value expected." else "Expected comma or closing bracket.";

                            const tk_ = comma orelse tk;

                            return ParserResult{ .err = lexer.TokenError{ .line = tk_.line, .column = tk_.start, .message = message } };
                        } else {
                            const message = if (comma != null and array.items.len > 0) "Trailing comma." else "Value expected.";
                            array.deinit();

                            const tk_ = comma orelse tk;

                            return ParserResult{ .err = lexer.TokenError{ .line = tk_.line, .column = tk_.start, .message = message } };
                        }

                        return object.JsonValue{ .array = array };
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

                            return ParserResult{ .err = lexer.TokenError{ .line = tk_.line, .column = tk_.start, .message = message } };
                        } else {
                            const message = if (comma != null and obj.count() > 0) "Trailing comma." else "Property expected.";

                            obj.deinit();

                            const tk_ = comma orelse tk;

                            return ParserResult{ .err = lexer.TokenError{ .line = tk_.line, .column = tk_.start, .message = message } };
                        }

                        return object.JsonValue{ .object = obj };
                    },
                    .String => {
                        const key = copyString(allocator, lexr.lexeme[tk.start..tk.length]);
                        switch (lexer.scan(lexr)) {
                            .tokenError => |err| {
                                obj.deinit();
                                return ParserResult{ .err = err };
                            },
                            .token => |tk_| {
                                if (tk_.type_ != .Colon) {
                                    obj.deinit();
                                    return ParserResult{ .err = lexer.TokenError{ .line = tk_.line, .column = tk_.start, .message = "Expected colon." } };
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

    return ParserResult{ .val = object.JsonValue{ .object = obj } };
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
                    const num = std.fmt.parseInt(i32, str, 10);
                    return object.JsonValue{ .number = .{ .integer = num } };
                },
                .Float => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    const num = std.fmt.parseFloat(f64, str);
                    return object.JsonValue{ .number = .{ .float = num } };
                },
                .String => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    return object.JsonValue{ .string = copyString(allocator, str) };
                },
                .True => {
                    return object.JsonValue{ .boolean = true };
                },
                .False => {
                    return object.JsonValue{ .boolean = false };
                },
                .Null => {
                    return object.JsonValue{ .null_ = null };
                },
                .RightBrace, .RightBracket, .Comma, .Colon => {
                    return ParserResult{ .err = lexer.makeError(lexr, lexer.DEFAULT_ERROR) };
                },
                .Eof => {
                    return object.JsonValue{ .null_ = null };
                },
                .Error => {
                    unreachable;
                },
            }
        },
    }
}

fn copyString(allocator: std.mem.Allocator, str: lexer.str) !lexer.str {
    const len = str.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(copy, str.ptr, len);
    return copy;
}

test "Parse literals" {
    var lxr = lexer.init("10");
    const res = parseValue(std.testing.allocator, &lxr) catch |err| {
        switch (err) {
            .ParseIntError => {
                std.debug.print("Expected an integer", .{});
                std.testing.expect(false);
            },
            else => {
                std.debug.print("Wrong kind of error", .{});
                std.testing.expect(false);
            },
        }
    };

    switch (res) {
        .err => |err| {
            std.debug.print("Error: {}\n", .{err});
            std.testing.expect(false);
        },
        .val => |val| {
            std.testing.expect(val, object.JsonValue{ .number = .{ .integer = 10 } });
        },
    }
}
