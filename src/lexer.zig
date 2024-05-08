const tk = @import("./token.zig");
const std = @import("std");
const char = char;

export const Lexer = struct {
    current: usize,
    lexeme: []char,
    line: usize,
    start: usize,
};

export const TokenError = struct {
    cause: []char,
    column: usize,
    line: usize,
    type_: tk.TokenType,
};

pub fn scan(lexer: *Lexer) void {
    const c: char = advance(lexer);

    if (isDigit(c)) return number(lexer);

    switch (c) {
        '{' => return makeToken(lexer, tk.TokenType.LeftBrace),
        '}' => return makeToken(lexer, tk.TokenType.RightBrace),
        '[' => return makeToken(lexer, tk.TokenType.LeftBracket),
        ']' => return makeToken(lexer, tk.TokenType.RightBracket),
        ',' => return makeToken(lexer, tk.TokenType.Comma),
        ':' => return makeToken(lexer, tk.TokenType.Colon),
        'f' => return if (match(lexer, "alse")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.Token.False),
        't' => return if (match(lexer, "rue")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.Token.False),
        'n' => return if (match(lexer, "null")) makeError(lexer, "Unknown value") else makeToken(lexer, tk.Token.False),
        '"' => return string(lexer),
        else => makeError(lexer, "Unexpected character."),
    }
}

fn advance(lexer: *Lexer) char {
    lexer.current += 1;
    return lexer.lexeme[lexer.current - 1];
}

fn isDigit(ch: char) bool {
    return ch >= '0' and ch <= '9';
}

fn number(lexer: *Lexer) tk.Token {
    while (isDigit(peek(lexer))) advance_(lexer);

    if (peek(lexer) == '.' and isDigit(peekNext(lexer))) {
        advance_(lexer);
        while (isDigit(peek(lexer))) advance_(lexer);
    }

    return makeToken(lexer, tk.Token.Number);
}

fn peekNext(lexer: *const Lexer) char {
    return if (isAtEnd(lexer)) ' ' else lexer.lexeme[lexer.current + 1];
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

fn match(lexer: *Lexer, substring: []char) bool {
    const current = lexer.lexeme[lexer.start..lexer.current];

    return current == substring;
}

fn string(lexer: *Lexer) tk.Token {
    while (peek(lexer) != '"' and !isAtEnd(lexer)) {
        if (foundNewLine(lexer)) {
            lexer.line += 1;
            advance_(lexer);
        }
    }

    if (isAtEnd(lexer)) return makeError(lexer, "Unterminated string");

    advance(lexer);

    return makeToken(lexer, tk.Token.String);
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
        std.mem.eql([]char, lexer.lexeme[lexer.current .. lexer.current + 1], "\r\n"));
}

fn makeError(lexer: *Lexer, cause: []char) TokenError {
    return .{
        .cause = cause,
        .column = lexer.start,
        .line = lexer.line,
        .type_ = tk.TokenType.Error,
    };
}
