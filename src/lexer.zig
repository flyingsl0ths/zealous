const std = @import("std");

const tk = @import("./token.zig");

pub const char = u8;
pub const str = [:0]const char;

const Lexer = struct {
    current: usize,
    lexeme: str,
    line: usize,
    start: usize,
};

const TokenError = struct {
    cause: str,
    column: usize,
    line: usize,
    type_: tk.TokenType,
};

pub const LexerResult = union(enum) {
    tokenError: TokenError,
    token: tk.Token,
};

pub fn init(source: str) Lexer {
    return .{
        .current = 0,
        .lexeme = source,
        .line = 1,
        .start = 0,
    };
}

pub fn scan(lexer: *Lexer) LexerResult {
    skipWhitespace(lexer);

    lexer.start = lexer.current;

    if (isAtEnd(lexer)) return makeToken(lexer, tk.TokenType.Eof);

    const c: char = advance(lexer);

    if (isDigit(c)) return number(lexer);

    switch (c) {
        '{' => return makeToken(lexer, tk.TokenType.LeftBrace),
        '}' => return makeToken(lexer, tk.TokenType.RightBrace),
        '[' => return makeToken(lexer, tk.TokenType.LeftBracket),
        ']' => return makeToken(lexer, tk.TokenType.RightBracket),
        ',' => return makeToken(lexer, tk.TokenType.Comma),
        ':' => return makeToken(lexer, tk.TokenType.Colon),
        'f' => return if (match(lexer, "alse")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.TokenType.False),
        't' => return if (match(lexer, "rue")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.TokenType.False),
        'n' => return if (match(lexer, "null")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.TokenType.False),
        '"' => return string(lexer),
        else => return makeError(lexer, "Unexpected character."),
    }
}

fn skipWhitespace(lexer: *Lexer) void {
    while (true) {
        switch (peek(lexer)) {
            ' ', '\r', '\t' => {
                advance_(lexer);
                break;
            },
            '\n' => {
                lexer.line += 1;
                advance_(lexer);
            },
            '/' => {
                if (peekNext(lexer) == '/') {
                    return;
                }
            },
            else => break,
        }
    }
}

fn advance(lexer: *Lexer) char {
    lexer.current += 1;
    return lexer.lexeme[lexer.current - 1];
}

fn isDigit(ch: char) bool {
    return ch >= '0' and ch <= '9';
}

fn number(lexer: *Lexer) LexerResult {
    while (isDigit(peek(lexer))) advance_(lexer);

    if (peek(lexer) == '.' and isDigit(peekNext(lexer))) {
        advance_(lexer);
        while (isDigit(peek(lexer))) advance_(lexer);
    }

    return makeToken(lexer, tk.TokenType.Number);
}

fn peekNext(lexer: *const Lexer) char {
    return if (isAtEnd(lexer)) ' ' else lexer.lexeme[lexer.current + 1];
}

fn advance_(lexer: *Lexer) void {
    lexer.current += 1;
}

fn makeToken(lexer: *Lexer, type_: tk.TokenType) LexerResult {
    return .{ .token = .{
        .column = lexer.current,
        .length = lexer.current - lexer.start,
        .line = lexer.line,
        .start = lexer.start,
        .type_ = type_,
    } };
}

fn match(lexer: *Lexer, substring: []const char) bool {
    const current = lexer.lexeme[lexer.start..lexer.current];

    return std.mem.eql(char, current, substring);
}

fn string(lexer: *Lexer) LexerResult {
    while (peek(lexer) != '"' and !isAtEnd(lexer)) {
        if (foundNewLine(lexer)) {
            lexer.line += 1;
            advance_(lexer);
        }
    }

    if (isAtEnd(lexer)) return makeError(lexer, "Unterminated string");

    advance_(lexer);

    return makeToken(lexer, tk.TokenType.String);
}

fn peek(lexer: *const Lexer) char {
    return lexer.lexeme[lexer.current];
}

fn isAtEnd(lexer: *const Lexer) bool {
    return lexer.current == lexer.lexeme.len;
}

fn foundNewLine(lexer: *const Lexer) bool {
    return lexer.lexeme[lexer.current] == '\n' or
        (lexer.lexeme.len >= 2 and
        std.mem.eql(char, lexer.lexeme[lexer.current .. lexer.current + 1], "\r\n"));
}

fn makeError(lexer: *Lexer, cause: str) LexerResult {
    return .{ .tokenError = .{
        .cause = cause,
        .column = lexer.start,
        .line = lexer.line,
        .type_ = tk.TokenType.Error,
    } };
}

test "Single tokenization" {
    var lexr = init("{");
    var expected: tk.Token = .{ .column = 1, .length = 1, .line = 1, .start = 0, .type_ = tk.TokenType.LeftBrace };

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("}");
    expected.type_ = tk.TokenType.RightBrace;

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("[");
    expected.type_ = tk.TokenType.LeftBracket;

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("]");
    expected.type_ = tk.TokenType.RightBracket;

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init(",");
    expected.type_ = tk.TokenType.Comma;

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init(":");
    expected.type_ = tk.TokenType.Colon;

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });
}

fn matches(result: tk.Token, expected: tk.Token) bool {
    return result.column == expected.column and result.length == expected.length and result.length == expected.line and result.start == expected.start and result.type_ == expected.type_;
}
