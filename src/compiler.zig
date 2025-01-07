const std = @import("std");

const Chunk = @import("Chunk.zig");
const report = @import("main.zig").report;
const Tokenizer = @import("Tokenizer.zig");
const Value = @import("Value.zig");

const log = std.log.scoped(.compiler);

const Compiler = @This();

tokenizer: Tokenizer,
chunk: *Chunk,

curr: Tokenizer.Token,
prev: Tokenizer.Token,
had_error: bool,
panic_mode: bool,

const Error = error{ Compile, OutOfMemory };

pub fn compile(source: []const u8, chunk: *Chunk) Error!void {
    var c: Compiler = .{
        .tokenizer = .init(source),
        .curr = undefined,
        .prev = undefined,
        .chunk = chunk,
        .had_error = false,
        .panic_mode = false,
    };

    c.advance();
    try c.expression();
    c.consume(.eof);

    try c.emitOpcode(.@"return");
    if (c.had_error) return error.Compile;
}

const Precedence = enum {
    // zig fmt: off
    none,
    assignment, // =
    @"or",      // or
    @"and",     // and
    equality,   // == !=
    comparison, // < > <= >=
    term,       // + -
    factor,     // * /
    unary,      // ! -
    call,       // . ()
    primary,
    // zig fmt: on

    fn less(a: Precedence, b: Precedence) bool {
        return @intFromEnum(a) < @intFromEnum(b);
    }

    fn lessEq(a: Precedence, b: Precedence) bool {
        return !b.less(a);
    }

    fn next(a: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(a) + 1);
    }
};

fn expression(c: *Compiler) Error!void {
    log.debug("expression", .{});
    try c.parsePresedence(.assignment);
}

const ParseRule = struct {
    prefix: ?*const fn (c: *Compiler) Error!void,
    infix: ?*const fn (c: *Compiler) Error!void,
    precedence: Precedence,
};

const oper_table: std.EnumArray(std.meta.Tag(Tokenizer.TokenType), ParseRule) = .init(.{
    // zig fmt: off
    .left_paren    = .{ .prefix = grouping, .infix = null,   .precedence = .none     },
    .right_paren   = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .left_brace    = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .right_brace   = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .comma         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .dot           = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .minus         = .{ .prefix = unary,    .infix = binary, .precedence = .term     },
    .plus          = .{ .prefix = unary,    .infix = binary, .precedence = .term     },
    .semicolon     = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .slash         = .{ .prefix = null,     .infix = binary, .precedence = .factor   },
    .star          = .{ .prefix = null,     .infix = binary, .precedence = .factor   },
    .bang          = .{ .prefix = unary,    .infix = null,   .precedence = .none     },
    .bang_equal    = .{ .prefix = null,     .infix = binary, .precedence = .equality },
    .equal         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .equal_equal   = .{ .prefix = null,     .infix = binary, .precedence = .equality },
    .greater       = .{ .prefix = null,     .infix = binary, .precedence = .comparison },
    .greater_equal = .{ .prefix = null,     .infix = binary, .precedence = .comparison },
    .less          = .{ .prefix = null,     .infix = binary, .precedence = .comparison },
    .less_equal    = .{ .prefix = null,     .infix = binary, .precedence = .comparison },
    .identifier    = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .string        = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .number        = .{ .prefix = number,   .infix = null,   .precedence = .none     },
    .@"and"        = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .class         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .@"else"       = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .false         = .{ .prefix = literal,  .infix = null,   .precedence = .none     },
    .@"for"        = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .fun           = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .@"if"         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .nil           = .{ .prefix = literal,  .infix = null,   .precedence = .none     },
    .@"or"         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .print         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .@"return"     = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .super         = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .this          = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .true          = .{ .prefix = literal,  .infix = null,   .precedence = .none     },
    .@"var"        = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .@"while"      = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .@"error"      = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    .eof           = .{ .prefix = null,     .infix = null,   .precedence = .none     },
    // zig fmt: on
});

fn parsePresedence(c: *Compiler, pres: Precedence) Error!void {
    log.debug("parsePresedence with {s}", .{@tagName(pres)});
    c.advance();

    log.debug("{}", .{c.prev.type});

    if (oper_table.get(c.prev.type).prefix) |rule| {
        try rule(c);
    } else {
        c.errorAtPrev("Expected expression.", .{});
        return error.Compile;
    }

    while (pres.lessEq(oper_table.get(c.curr.type).precedence)) {
        c.advance();
        const infix_rule = oper_table.get(c.prev.type).infix.?;
        try infix_rule(c);
    }
}

fn unary(c: *Compiler) Error!void {
    log.debug("unary", .{});
    const token = c.prev.type;

    try c.parsePresedence(.unary);

    switch (token) {
        .minus => try c.emitOpcodePos(.negate, c.prev.position),
        .bang => try c.emitOpcodePos(.not, c.prev.position),
        else => unreachable,
    }
}

fn grouping(c: *Compiler) Error!void {
    try c.expression();
    c.consume(.right_paren);
}

fn binary(c: *Compiler) Error!void {
    const operator = c.prev;
    const prec = oper_table.get(operator.type).precedence;

    try c.parsePresedence(prec.next());

    try switch (operator.type) {
        .bang_equal => c.emitOpcodesPos(&.{ .equal, .not }, operator.position),
        .equal_equal => c.emitOpcodePos(.equal, operator.position),
        .greater => c.emitOpcodePos(.greater, operator.position),
        .greater_equal => c.emitOpcodesPos(&.{ .less, .not }, operator.position),
        .less => c.emitOpcodePos(.less, operator.position),
        .less_equal => c.emitOpcodesPos(&.{ .greater, .not }, operator.position),
        .plus => c.emitOpcodePos(.add, operator.position),
        .minus => c.emitOpcodePos(.subtract, operator.position),
        .star => c.emitOpcodePos(.multiply, operator.position),
        .slash => c.emitOpcodePos(.divide, operator.position),
        else => unreachable,
    };
}

fn number(c: *Compiler) Error!void {
    const value = c.prev.type.number;
    return c.emitConstant(.number(value)) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        error.NoSpaceForConstant => error.Compile,
    };
}

fn advance(c: *Compiler) void {
    c.prev = c.curr;

    while (true) {
        c.curr = c.tokenizer.next();
        if (c.curr.type != .@"error") break;

        c.errorAtCurrent("", .{});
    }
}

fn literal(c: *Compiler) Error!void {
    switch (c.prev.type) {
        .nil => try c.emitOpcode(.nil),
        .false => try c.emitOpcode(.false),
        .true => try c.emitOpcode(.true),
        else => unreachable,
    }
}

fn consume(c: *Compiler, token_type: Tokenizer.TokenType) void {
    if (@intFromEnum(c.curr.type) == @intFromEnum(token_type)) {
        c.advance();
        return;
    }
    c.errorAtCurrent("expected {} found {}", .{
        token_type,
        c.curr.type,
    });
}

fn errorAtCurrent(c: *@This(), comptime fmt: []const u8, args: anytype) void {
    c.had_error = true;
    report(c.tokenizer.source, c.curr.position, fmt, args);
}

fn errorAtPrev(c: *@This(), comptime fmt: []const u8, args: anytype) void {
    c.had_error = true;
    report(c.tokenizer.source, c.prev.position, fmt, args);
}

fn emitByte(c: *Compiler, byte: u8) error{OutOfMemory}!void {
    try c.chunk.writeByte(byte, c.prev.position);
}

fn emitOpcode(c: *Compiler, op: Chunk.OpCode) error{OutOfMemory}!void {
    try c.chunk.writeOpcode(op, c.prev.position);
}

fn emitOpcodesPos(c: *Compiler, ops: []const Chunk.OpCode, pos: u32) error{OutOfMemory}!void {
    for (ops) |op| {
        try c.emitOpcodePos(op, pos);
    }
}

fn emitOpcodePos(c: *Compiler, op: Chunk.OpCode, pos: u32) error{OutOfMemory}!void {
    try c.chunk.writeOpcode(op, pos);
}

fn emitConstant(c: *Compiler, value: Value) error{ OutOfMemory, NoSpaceForConstant }!void {
    const constant = try c.chunk.addConstant(value);
    try c.emitOpcode(.constant);
    try c.emitByte(constant);
}
