const tk = @import("./token.zig");

export const Lexer = struct {
    current: usize,
    lexeme: []u8,
    line: usize,
    start: usize,
};

export const TokenError = struct {
    cause: []u8,
    column: usize,
    line: usize,
    type_: tk.TokenType,
};

pub fn scan(lexer: *Lexer) void {
    // TODO: Finish implementing remaining tokens
    // Literals
    // True,
    // False,
    // Null,
    // String,
    // Number,

    const c: u8 = advance(lexer);

    switch (c) {
        '{' => makeToken(lexer, tk.TokenType.LeftBrace),
        '}' => makeToken(lexer, tk.TokenType.RightBrace),
        '[' => makeToken(lexer, tk.TokenType.LeftBracket),
        ']' => makeToken(lexer, tk.TokenType.RightBracket),
        ',' => makeToken(lexer, tk.TokenType.Comma),
        ':' => makeToken(lexer, tk.TokenType.Colon),
        else => makeError(lexer),
    }
}

fn advance(lexer: *Lexer) u8 {
    lexer.current += 1;
    return lexer.lexeme[lexer.current - 1];
}

fn advance_(lexer: *Lexer) void {
    lexer.current += 1;
}

fn makeToken(lexer: *Lexer, type_: tk.TokenType) tk.Token {
    return .{
        .column = lexer.current,
        .length = lexer.current - lexer.start,
        .line = lexer.line,
        .start = lexer.start,
        .type_ = type_,
    };
}

fn makeError(lexer: *Lexer, cause: []u8) TokenError {
    return .{
        .cause = cause,
        .column = lexer.start,
        .line = lexer.line,
        .type_ = tk.TokenType.Error,
    };
}
