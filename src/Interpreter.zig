const report = @import("lox.zig").report;
const std = @import("std");
const Expression = @import("Parser.zig").Expression;

const Value = union(enum) {
    nil,
    number: f64,
    string: []const u8,
    bool: bool,

    pub fn isTruthy(v: Value) bool {
        return switch (v) {
            .nil => false,
            .bool => |b| b,
            .string, .number => true,
        };
    }

    pub fn eql(lhs: Value, rhs: Value) bool {
        const TagType = std.meta.Tag(Value);
        const lhs_tag: TagType = lhs;
        const rhs_tag: TagType = rhs;
        if (lhs_tag != rhs_tag) return false;

        return switch (lhs_tag) {
            .nil => true,
            .number => lhs.number == rhs.number or (std.math.isNan(lhs.number) and std.math.isNan(rhs.number)),
            .string => std.mem.eql(u8, lhs.string, rhs.string),
            .bool => lhs.bool == rhs.bool,
        };
    }

    pub fn print(v: Value) void {
        return switch (v) {
            .nil => std.debug.print("nil", .{}),
            .number => |n| std.debug.print("{d}", .{n}),
            .string => |s| std.debug.print("{s}", .{s}),
            .bool => |b| std.debug.print("{}", .{b}),
        };
    }
};

pub fn interpret(
    arena: std.mem.Allocator,
    source: []const u8,
    nodes: []const Expression,
    expr_id: u32,
) error{ RuntimeError, OutOfMemory }!Value {
    const expression = nodes[expr_id];
    switch (expression.type.kind()) {
        .literal => {
            return switch (expression.type) {
                .string => .{ .string = expression.value.string },
                .number => .{ .number = expression.value.number },
                .true => .{ .bool = true },
                .false => .{ .bool = false },
                .nil => .nil,
                else => unreachable,
            };
        },
        .unary => {
            const result = try interpret(
                arena,
                source,
                nodes,
                expression.value.children[0],
            );
            return switch (expression.type) {
                .not => .{ .bool = !result.isTruthy() },
                .negation => switch (result) {
                    .number => |n| .{ .number = -n },
                    else => {
                        report(
                            source,
                            expression.source_loc,
                            try std.fmt.allocPrint(
                                arena,
                                "Can't negate {s}",
                                .{@tagName(result)},
                            ),
                        );
                        return error.RuntimeError;
                    },
                },
                else => unreachable,
            };
        },
        .binary => {
            const lhs = try interpret(
                arena,
                source,
                nodes,
                expression.value.children[0],
            );
            const rhs = try interpret(
                arena,
                source,
                nodes,
                expression.value.children[1],
            );

            switch (expression.type) {
                .mult, .div, .binary_sub => |op| {
                    if (lhs != .number or rhs != .number) {
                        const op_name = switch (op) {
                            .mult => "multiply",
                            .div => "divide",
                            .binary_sub => "substract",
                            else => unreachable,
                        };
                        report(
                            source,
                            expression.source_loc,
                            try std.fmt.allocPrint(
                                arena,
                                "Can't {s} {s} and {s}",
                                .{ op_name, @tagName(lhs), @tagName(rhs) },
                            ),
                        );
                        return error.RuntimeError;
                    }

                    return switch (op) {
                        .mult => .{ .number = lhs.number * rhs.number },
                        .div => .{ .number = lhs.number / rhs.number },
                        .binary_sub => .{ .number = lhs.number - rhs.number },
                        else => unreachable,
                    };
                },
                .binary_add => {
                    if (lhs == .number and rhs == .number) {
                        return .{ .number = lhs.number + rhs.number };
                    }
                    if (lhs == .string and rhs == .string) {
                        return .{ .string = try std.mem.concat(arena, u8, &.{ lhs.string, rhs.string }) };
                    }
                    report(
                        source,
                        expression.source_loc,
                        try std.fmt.allocPrint(
                            arena,
                            "Can't add {s} and {s}",
                            .{ @tagName(lhs), @tagName(rhs) },
                        ),
                    );
                    return error.RuntimeError;
                },
                .less_equal, .less, .greater_equal, .greater => |op| {
                    if (lhs != .number or rhs != .number)
                        return error.RuntimeError;
                    const zop: std.math.CompareOperator = switch (op) {
                        .less => .lt,
                        .less_equal => .lte,
                        .greater_equal => .gte,
                        .greater => .gt,
                        else => unreachable,
                    };

                    return .{ .bool = std.math.compare(lhs.number, zop, rhs.number) };
                },
                .@"or" => return .{ .bool = lhs.isTruthy() or rhs.isTruthy() },
                .@"and" => return .{ .bool = lhs.isTruthy() and rhs.isTruthy() },
                .equal => return .{ .bool = lhs.eql(rhs) },
                .not_equal => return .{ .bool = !lhs.eql(rhs) },
                else => unreachable,
            }
        },
    }

    unreachable;
}
