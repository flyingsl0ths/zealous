export const TokenType = enum {
    // Structural
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Comma,
    Colon,
    // Literals
    True,
    False,
    Null,
    String,
    Number,
    Error,
};

export const Token = struct {
    column: usize,
    length: usize,
    line: usize,
    start: usize,
    type_: TokenType,
};
