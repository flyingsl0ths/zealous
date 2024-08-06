const std = @import("std");

const lexer = @import("lexer.zig");
const object = @import("object.zig");
const token = @import("token.zig");

const ParserResult = union(enum) {
    err: lexer.TokenError,
    val: object.Value,
};

const ParserError = std.fmt.ParseIntError || std.fmt.ParseFloatError || std.heap.Allocator.Error;

pub fn parse(source: lexer.str) ParserError!object.Value {
    const lexr = lexer.Lexer.init(source);

    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer allocator.deinit();

    // TODO: Handle errors
    return try parseValue(allocator, lexr);
}

fn parseArray(allocator: *std.heap.Allocator, lexr: lexer.Lexer) ParserError!ParserResult {
    var array = std.ArrayList(object.Value).init(allocator);

    errdefer array.deinit();

    var foundRightBracket = false;
    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(&lexr)) {
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

                        return object.Value{ .array = array };
                    },
                    .RightBracket => {
                        foundRightBracket = true;
                    },
                    .Comma => {
                        comma = tk;
                    },
                    _ => {
                        const value = try parseValue(allocator, lexr);
                        array.append(value);
                    },
                }
            },
        }
    }
}

fn parseObject(allocator: *std.heap.Allocator, lexr: lexer.Lexer) ParserError!ParserResult {
    const obj = std.StringArrayHashMap(object.Value).init(allocator);

    errdefer obj.deinit();

    var foundRightBrace = false;
    var comma: ?token.Token = undefined;

    while (true) {
        switch (lexer.scan(&lexr)) {
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

                        return object.Value{ .object = obj };
                    },
                    .String => {
                        const key = copyString(allocator, lexr.lexeme[tk.start..tk.length]);
                        switch (lexer.scan(&lexr)) {
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

    return ParserResult{ .val = object.Value{ .object = obj } };
}

fn parseValue(allocator: *std.heap.Allocator, lexr: lexer.Lexer) ParserError!ParserResult {
    switch (lexer.scan(&lexr)) {
        .tokenError => |err| {
            return ParserResult{ .err = err };
        },
        .token => |tk| {
            switch (tk.type_) {
                .LeftBracket => {
                    const arr = try parseArray(allocator, lexr);
                    return object.Value{ .array = arr };
                },
                .LeftBrace => {
                    const obj = try parseObject(allocator, lexr);
                    return object.Value{ .object = obj };
                },
                .Int => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    const num = std.fmt.parseInt(i32, str, 10);
                    return object.Value{ .number = object.Number{ .integer = num } };
                },
                .Float => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    const num = std.fmt.parseFloat(f64, str);
                    return object.Value{ .number = object.Number{ .float = num } };
                },
                .String => {
                    const str = lexr.lexeme[tk.start..tk.length];
                    return object.Value{ .string = copyString(allocator, str) };
                },
                .True => {
                    return object.Value{ .boolean = true };
                },
                .False => {
                    return object.Value{ .boolean = false };
                },
                .Null => {
                    return object.Value{ .null_ = null };
                },
            }
        },
    }
}

fn copyString(allocator: *std.heap.Allocator, str: lexer.str) !lexer.str {
    const len = str.len;
    const copy = try allocator.alloc(u8, len);
    std.mem.copyForwards(copy, str.ptr, len);
    return copy;
}
