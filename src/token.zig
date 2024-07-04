pub const TokenType = enum {
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
    Eof,
};

pub const Token = struct {
    length: usize,
    line: usize,
    start: usize,
    type_: TokenType,
};
