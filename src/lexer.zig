const std = @import("std");

const tk = @import("token.zig");

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

    if (c == '-' or isDigit(c)) return number(lexer);

    if (isAlpha(c)) return literal(lexer);

    switch (c) {
        '{' => return makeToken(lexer, tk.TokenType.LeftBrace),
        '}' => return makeToken(lexer, tk.TokenType.RightBrace),
        '[' => return makeToken(lexer, tk.TokenType.LeftBracket),
        ']' => return makeToken(lexer, tk.TokenType.RightBracket),
        ',' => return makeToken(lexer, tk.TokenType.Comma),
        ':' => return makeToken(lexer, tk.TokenType.Colon),
        '"' => return string(lexer),
        '/' => return makeError(lexer, "Comments are not permitted in JSON."),
        else => return makeError(lexer, "Expected JSON object, array or literal."),
    }
}

fn skipWhitespace(lexer: *Lexer) void {
    while (true) {
        switch (peek(lexer)) {
            ' ', '\r', '\t' => {
                advance_(lexer);
            },
            '\n' => {
                lexer.line += 1;
                advance_(lexer);
            },
            else => return,
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

fn isAlpha(ch: char) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

fn number(lexer: *Lexer) LexerResult {
    var isFloat = false;

    if (peek(lexer) == '-') advance_(lexer);

    while (isDigit(peek(lexer))) advance_(lexer);

    isFloat = peek(lexer) == '.';

    if (peek(lexer) == '.' and isDigit(peekNext(lexer))) {
        isFloat = true;
        advance_(lexer);
        while (isDigit(peek(lexer))) advance_(lexer);
    }

    const current = peek(lexer);
    if (current == 'E' or current == 'e') {
        advance_(lexer);
        if (peek(lexer) == '+' or peek(lexer) == '-') advance_(lexer);
        while (isDigit(peek(lexer))) advance_(lexer);
        return makeToken(lexer, tk.TokenType.Float);
    }

    return makeToken(lexer, if (isFloat) tk.TokenType.Float else tk.TokenType.Int);
}

fn literal(lexer: *Lexer) LexerResult {
    while (isAlpha(peek(lexer))) advance_(lexer);

    return switch (literalType(lexer)) {
        tk.TokenType.Error => makeError(lexer, "Value expected."),
        else => |type_| makeToken(lexer, type_),
    };
}

fn literalType(lexer: *Lexer) tk.TokenType {
    return switch (lexer.lexeme[lexer.start]) {
        'f' => checkSubstring(lexer, 1, 5, "alse", tk.TokenType.False),
        't' => checkSubstring(lexer, 1, 4, "rue", tk.TokenType.True),
        'n' => checkSubstring(lexer, 1, 4, "ull", tk.TokenType.Null),
        else => tk.TokenType.Error,
    };
}

fn checkSubstring(lexer: *Lexer, start: usize, length: usize, rest: str, type_: tk.TokenType) tk.TokenType {
    const matched = lexer.current == start + length - 1 and
        std.mem.eql(u8, lexer.lexeme[(lexer.start + start)..length], rest);

    return if (matched) type_ else tk.TokenType.Error;
}

fn peekNext(lexer: *const Lexer) char {
    return if (isAtEnd(lexer)) ' ' else lexer.lexeme[lexer.current + 1];
}

fn advance_(lexer: *Lexer) void {
    lexer.current += 1;
}

fn makeToken(lexer: *Lexer, type_: tk.TokenType) LexerResult {
    return .{ .token = .{
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
        }
        advance_(lexer);
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
    var expected: tk.Token = .{ .length = 1, .line = 1, .start = 0, .type_ = tk.TokenType.LeftBrace };

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

test "Whitespace" {
    var lexr = init(" \t\r\n");

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, .{
            .length = 0,
            .line = 2,
            .start = 4,
            .type_ = tk.TokenType.Eof,
        }),
        .tokenError => false,
    });
}

test "Literals" {
    var lexr = init("false");

    var expected: tk.Token = .{ .length = 5, .line = 1, .start = 0, .type_ = tk.TokenType.False };

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("true");

    expected = .{ .length = 4, .line = 1, .start = 0, .type_ = tk.TokenType.True };

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("null");

    expected = .{ .length = 4, .line = 1, .start = 0, .type_ = tk.TokenType.Null };

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });
}

test "Numbers" {
    var lexr = init("1");
    var expected: tk.Token = .{ .length = 1, .line = 1, .start = 0, .type_ = tk.TokenType.Int };

    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("1.0");
    expected = .{ .length = 3, .line = 1, .start = 0, .type_ = tk.TokenType.Float };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("-1");
    expected = .{ .length = 2, .line = 1, .start = 0, .type_ = tk.TokenType.Int };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("-1.0");
    expected = .{ .length = 4, .line = 1, .start = 0, .type_ = tk.TokenType.Float };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("1e1");
    expected = .{ .length = 3, .line = 1, .start = 0, .type_ = tk.TokenType.Float };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("1e+1");
    expected = .{ .length = 4, .line = 1, .start = 0, .type_ = tk.TokenType.Float };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("1e-1");
    expected = .{ .length = 4, .line = 1, .start = 0, .type_ = tk.TokenType.Float };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });
}

test "Strings" {
    var lexr = init("\"h\"");
    var expected: tk.Token = .{ .length = 3, .line = 1, .start = 0, .type_ = tk.TokenType.String };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("\"h\n\"");
    expected = .{ .length = 4, .line = 2, .start = 0, .type_ = tk.TokenType.String };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("\"h\r\n\"");
    expected = .{ .length = 5, .line = 2, .start = 0, .type_ = tk.TokenType.String };
    try std.testing.expect(switch (scan(&lexr)) {
        .token => |token| matches(token, expected),
        .tokenError => false,
    });

    lexr = init("\"h");
    try std.testing.expect(switch (scan(&lexr)) {
        .token => false,
        .tokenError => true,
    });
}

fn matches(result: tk.Token, expected: tk.Token) bool {
    return result.length == expected.length and result.line == expected.line and result.start == expected.start and result.type_ == expected.type_;
}
