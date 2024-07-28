const std = @import("std");

const lexer = @import("lexer.zig");
const object = @import("object.zig");
const ParserResult = union(enum) {
    err: lexer.TokenError,
    value: object.Value,
};

pub fn parse(source: lexer.str) ParserResult {
    const lexr = lexer.Lexer.init(source);
    switch (lexer.scan(&lexr)) {
        .tokenError => |err| {
            return ParserResult{ .err = err };
        },
        .token => |tk| {
            switch (tk.type_) {
                .Int => {
                    const str = source[tk.start..tk.length];
                    const num = std.fmt.parseInt(i32, str, 10);
                    return object.Value{ .number = object.Number{ .integer = num } };
                },
                .Float => {
                    const str = source[tk.start..tk.length];
                    const num = std.fmt.parseFloat(f64, str);
                    return object.Value{ .number = object.Number{ .float = num } };
                },
                .String => {
                    const str = source[tk.start..tk.length];
                    return object.Value{ .string = str };
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
