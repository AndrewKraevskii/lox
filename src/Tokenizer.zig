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

pub fn next(self: *@This()) ?Token {
    outer: while (true) {
        if (self.finished()) return null;
        self.skipWhitespaces();
        if (self.finished()) return null;

        const start = self.position;
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
                if (token[1].isKeyword() and
                    std.ascii.isAlphanumeric(self.source[self.position + string.len]))
                {
                    // Keyword is prefix for identifier.
                    break;
                }
                self.position += @intCast(string.len);
                return .{ .type = token[1], .position = start };
            }
        }

        if (std.mem.startsWith(u8, self.source[self.position..], "\"")) {
            const end = end: while (true) {
                const end = std.mem.indexOfScalarPos(u8, self.source, self.position + 1, '\"') orelse break :outer;
                if (self.source[end - 1] == '\\') {
                    self.position = @intCast(end);
                    continue;
                }
                break :end end;
            };
            self.position = @intCast(end + 1);
            return .{
                .type = .{ .string = self.source[start + 1 .. end] },
                .position = start,
            };
        }

        if (std.ascii.isDigit(self.source[self.position])) {
            var end = std.mem.indexOfNonePos(
                u8,
                self.source,
                self.position,
                digits,
            ) orelse self.source.len;
            if (self.source.len - end >= 2 and self.source[end] == '.' and std.ascii.isDigit(self.source[end + 1])) {
                end = std.mem.indexOfNonePos(
                    u8,
                    self.source,
                    end + 1,
                    digits,
                ) orelse self.source.len;
            }

            self.position = @intCast(end);
            const num = std.fmt.parseFloat(f64, self.source[start..end]) catch break :outer;
            return .{ .type = .{ .number = num }, .position = start };
        }

        if (std.ascii.isAlphabetic(self.source[self.position])) {
            const end = for (self.source[self.position..], self.position..) |char, index| {
                if (!std.ascii.isAlphanumeric(char)) {
                    break index;
                }
            } else self.source.len;
            self.position = @intCast(end);

            return .{ .type = .{ .identifier = self.source[start..end] }, .position = start };
        }

        break;
    }
    lox.report(self.source, self.position, "unexpected token");
    defer self.position += 1;

    return .{ .type = .invalid, .position = self.position };
}

pub fn peek(self: *@This()) ?TokenType {
    const position = self.position;
    defer self.position = position;
    return self.next();
}

pub fn peekNext(self: *@This()) ?TokenType {
    const position = self.position;
    defer self.position = position;
    self.next();
    return self.next();
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

pub const Token = struct {
    position: u32,
    type: TokenType,
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
    number: f64,

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

    pub fn isKeyword(token: TokenType) bool {
        return switch (token) {
            .@"and",
            .class,
            .@"else",
            .false,
            .fun,
            .@"for",
            .@"if",
            .nil,
            .@"or",
            .print,
            .@"return",
            .super,
            .this,
            .true,
            .@"var",
            .@"while",
            => true,
            else => false,
        };
    }
};
