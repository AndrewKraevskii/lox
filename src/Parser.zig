const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");
const TokenType = Tokenizer.TokenType;
const Token = Tokenizer.Token;
const report = @import("lox.zig").report;

const Parser = @This();
const log = std.log.scoped(.parser);

const Error = error{ParseError} || std.mem.Allocator.Error;

const ExpressionType = enum {
    string,
    number,
    true,
    false,
    nil,

    less_equal,
    greater_equal,
    equal,
    not_equal,
    less,
    greater,
    not,
    mult,
    div,
    negation,
    binary_sub,
    unary_add,
    binary_add,
    @"and",
    @"or",

    // "(", // .left_paren,
    // ")", // .right_paren,
    // "{", // .left_brace,
    // "}", // .right_brace,
    // ",", // .comma,
    // ".", // .dot,
    // ";", // .semicolon,
    // "=", // .equal,
    // "class", // .class,
    // "else", // .@"else",
    // "fun", // .fun,
    // "for", // .@"for",
    // "if", // .@"if",
    // "print", // .print,
    // "return", // .@"return",
    // "super", // .super,
    // "this", // .this,
    // "var", // .@"var",
    // "while", // .@"while",

    pub fn kind(self: @This()) enum {
        literal,
        unary,
        binary,
    } {
        return switch (self) {
            .string,
            .number,
            .true,
            .false,
            .nil,
            => .literal,
            .less_equal,
            .greater_equal,
            .equal,
            .not_equal,
            .less,
            .greater,
            .mult,
            .div,
            .binary_sub,
            .binary_add,
            .@"and",
            .@"or",
            => .binary,
            .not,
            .negation,
            .unary_add,
            => .unary,
        };
    }
};

const Expression = struct {
    type: ExpressionType,
    value: union {
        string: []const u8,
        number: f64,
        children: [2]u32,
    },
};

arena: std.mem.Allocator,
nodes: std.ArrayListUnmanaged(Expression),
tokenizer: *Tokenizer,

pub fn init(arena: std.mem.Allocator, tokenizer: *Tokenizer) error{OutOfMemory}!Parser {
    var parser: @This() = .{
        .arena = arena,
        .nodes = .empty,
        .tokenizer = tokenizer,
    };
    try parser.nodes.append(arena, undefined);

    return parser;
}

fn addNode(parser: *Parser, expr: Expression) error{OutOfMemory}!u32 {
    try parser.nodes.append(parser.arena, expr);
    return @intCast(parser.nodes.items.len - 1);
}

pub fn print(parser: *Parser, expression_index: u32) void {
    if (expression_index == 0) return;

    const expression = parser.nodes.items[expression_index];

    std.debug.print("({s}", .{@tagName(expression.type)});
    switch (expression.type.kind()) {
        .literal => switch (expression.type) {
            .string => std.debug.print(" {s}", .{expression.value.string}),
            .number => std.debug.print(" {d}", .{expression.value.number}),
            .true, .false, .nil => {
                // already printed in type
            },
            else => unreachable,
        },
        .unary => {
            std.debug.print(" ", .{});
            parser.print(expression.value.children[0]);
        },
        .binary => {
            std.debug.print(" ", .{});
            parser.print(expression.value.children[0]);
            parser.print(expression.value.children[1]);
        },
    }
    std.debug.print(")", .{});
}

fn parsePrefix(p: *Parser) Error!u32 {
    const token = p.tokenizer.peek().?;
    const expr_type: ExpressionType = switch (token.type) {
        .plus => .unary_add,
        .minus => .negation,
        else => return p.parsePrimaryExpression(),
    };
    _ = p.tokenizer.next();
    return p.addNode(.{
        .type = expr_type,
        .value = .{
            .children = .{
                try p.parsePrefix(),
                undefined,
            },
        },
    });
}

const operTable = std.enums.directEnumArrayDefault(std.meta.Tag(Tokenizer.TokenType), OperInfo, .{ .prec = -1, .tag = .nil }, 0, .{
    .bang_equal = .{ .prec = 10, .tag = .not_equal },
    .equal_equal = .{ .prec = 10, .tag = .equal },

    .greater = .{ .prec = 20, .tag = .greater },
    .greater_equal = .{ .prec = 20, .tag = .greater_equal },
    .less = .{ .prec = 20, .tag = .less },
    .less_equal = .{ .prec = 20, .tag = .less_equal },

    .minus = .{ .prec = 30, .tag = .binary_sub },
    .plus = .{ .prec = 30, .tag = .binary_add },

    .slash = .{ .prec = 40, .tag = .div },
    .star = .{ .prec = 40, .tag = .mult },
});

fn check(p: *Parser, expected_token: std.meta.Tag(TokenType)) bool {
    const token = p.tokenizer.peek() orelse return false;
    return expected_token == token.type;
}

fn matchAny(p: *Parser, list: []const std.meta.Tag(TokenType)) bool {
    for (list) |expected_token| {
        if (p.check(expected_token)) {
            p.tokenizer.next();
            return true;
        }
    }
    return false;
}

fn consume(p: *Parser, expected_token: std.meta.Tag(TokenType)) Error!void {
    if (p.check(expected_token)) {
        _ = p.tokenizer.next() orelse unreachable;
        return;
    }
    p.err("expected token not found");
    return error.ParseError;
}

fn err(p: *Parser, message: []const u8) void {
    if (p.tokenizer.peek()) |token| {
        report(p.tokenizer.source, token.position, message);
    } else {
        report(p.tokenizer.source, @intCast(p.tokenizer.source.len), message);
    }
}

const OperInfo = struct {
    prec: i8,
    tag: ExpressionType,
};

fn parsePrimaryExpression(p: *Parser) Error!u32 {
    const expr = p.tokenizer.next() orelse return error.ParseError;
    return p.addNode(switch (expr.type) {
        .number => |n| .{
            .type = .number,
            .value = .{ .number = n },
        },
        .string => |s| .{
            .type = .string,
            .value = .{ .string = s },
        },
        .true => .{
            .type = .true,
            .value = undefined,
        },
        .false => .{
            .type = .false,
            .value = undefined,
        },
        .nil => .{
            .type = .nil,
            .value = undefined,
        },
        .left_paren => {
            const res = try p.parseExpression();
            _ = try p.consume(.right_paren);
            return res;
        },
        else => {
            p.err("unexpected token found");
            return error.ParseError;
        },
    });
}

fn parseExpressionPresedence(p: *Parser, min_prec: i8) Error!u32 {
    var node = try p.parsePrefix();

    while (true) {
        const token = p.tokenizer.peek() orelse return node;

        const info = operTable[@as(usize, @intCast(@intFromEnum(token.type)))];
        if (info.prec < min_prec) {
            break;
        }
        _ = p.tokenizer.next();
        const rhs = try p.parseExpressionPresedence(info.prec + 1);

        node = try p.addNode(.{
            .type = info.tag,
            .value = .{ .children = .{ node, rhs } },
        });
    }

    return node;
}

pub fn parseExpression(p: *Parser) !u32 {
    return p.parseExpressionPresedence(0);
}
