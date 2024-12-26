const lox = @import("lox.zig");
const std = @import("std");
const log = std.log.scoped(.tokenizer);

source: []const u8,
position: u32,

const digits = "0123456789";

pub fn init(source: []const u8) @This() {
    return .{
        .source = source,
        .position = 0,
    };
}

pub fn next(self: *@This()) ?TokenType {
    outer: while (true) {
        if (self.finished()) return null;
        self.skipWhitespaces();
        if (self.finished()) return null;

        if (std.mem.startsWith(u8, self.source[self.position..], "//")) {
            self.position = @intCast(std.mem.indexOfScalarPos(
                u8,
                self.source,
                self.position,
                '\n',
            ) orelse self.source.len);
            continue;
        }

        for (map) |token| {
            const string = token[0];
            if (std.mem.startsWith(u8, self.source[self.position..], string)) {
                self.position += @intCast(string.len);
                return token[1];
            }
        }

        if (std.mem.startsWith(u8, self.source[self.position..], "\"")) {
            const start = self.position;

            const end = end: while (true) {
                const end = std.mem.indexOfScalarPos(u8, self.source, self.position + 1, '\"') orelse break :outer;
                if (self.source[end - 1] == '\\') {
                    self.position = @intCast(end);
                    continue;
                }
                break :end end;
            };
            self.position = @intCast(end + 1);
            return .{ .string = self.source[start + 1 .. end] };
        }

        if (std.ascii.isDigit(self.source[self.position])) {
            const start = self.position;

            const end = std.mem.indexOfNonePos(
                u8,
                self.source,
                self.position,
                digits,
            ) orelse self.source.len;
            self.position = @intCast(end);

            return .{ .number = self.source[start..end] };
        }

        break;
    }
    lox.report(self.source, self.position, "unexpected token");
    self.position += 1;

    return .invalid;
}

fn finished(self: *const @This()) bool {
    return self.source.len == self.position;
}

fn skipWhitespaces(self: *@This()) void {
    self.position = @intCast(std.mem.indexOfNonePos(
        u8,
        self.source,
        self.position,
        &std.ascii.whitespace,
    ) orelse self.source.len);
}

const map = [_]struct { []const u8, TokenType }{
    // put longer tokens before shorter once so we match them first
    .{ "<=", .less_equal },
    .{ ">=", .greater_equal },
    .{ "==", .equal_equal },
    .{ "!=", .bang_equal },
    .{ "(", .left_paren },
    .{ ")", .right_paren },
    .{ "{", .left_brace },
    .{ "}", .right_brace },
    .{ ",", .comma },
    .{ ".", .dot },
    .{ "-", .minus },
    .{ "+", .plus },
    .{ ";", .semicolon },
    .{ "/", .slash },
    .{ "*", .star },
    .{ "!", .bang },
    .{ "=", .equal },
    .{ ">", .greater },
    .{ "<", .less },
    .{ "and", .@"and" },
    .{ "class", .class },
    .{ "else", .@"else" },
    .{ "false", .false },
    .{ "fun", .fun },
    .{ "for", .@"for" },
    .{ "if", .@"if" },
    .{ "nil", .nil },
    .{ "or", .@"or" },
    .{ "print", .print },
    .{ "return", .@"return" },
    .{ "super", .super },
    .{ "this", .this },
    .{ "true", .true },
    .{ "var", .@"var" },
    .{ "while", .@"while" },
};

pub const TokenType = union(enum) {
    // Single-character tokens.
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,

    // One or two character tokens.
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,

    // Literals.
    identifier: []const u8,
    string: []const u8,
    number: []const u8,

    // Keywords.
    @"and",
    class,
    @"else",
    false,
    fun,
    @"for",
    @"if",
    nil,
    @"or",
    print,
    @"return",
    super,
    this,
    true,
    @"var",
    @"while",

    invalid,

    pub fn asString(token: TokenType) ?[]const u8 {
        return switch (token) {
            .left_paren => "(",
            .right_paren => ")",
            .left_brace => "{",
            .right_brace => "}",
            .comma => ",",
            .dot => ".",
            .minus => "-",
            .plus => "+",
            .semicolon => ";",
            .slash => "/",
            .star => "*",
            .bang => "!",
            .bang_equal => "!=",
            .equal => "=",
            .equal_equal => "==",
            .greater => ">",
            .greater_equal => ">=",
            .less => "<",
            .less_equal => "<=",
            .identifier => null,
            .string => null,
            .number => null,
            .@"and" => "and",
            .class => "class",
            .@"else" => "else",
            .false => "false",
            .fun => "fun",
            .@"for" => "for",
            .@"if" => "if",
            .nil => "nil",
            .@"or" => "or",
            .print => "print",
            .@"return" => "return",
            .super => "super",
            .this => "this",
            .true => "true",
            .@"var" => "var",
            .@"while" => "while",
            .invalid => null,
        };
    }
};
