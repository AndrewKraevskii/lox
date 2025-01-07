const std = @import("std");

const Value = @This();

storage: union(enum) {
    boolean: bool,
    number: f64,
    nil,
},

pub const @"true" = Value{ .storage = .{ .boolean = true } };
pub const @"false" = Value{ .storage = .{ .boolean = false } };
pub const nil = Value{ .storage = .nil };

pub fn fromBool(b: bool) Value {
    return if (b) .true else .false;
}

pub fn isFalsey(v: Value) bool {
    return switch (v.storage) {
        .boolean => |b| !b,
        .nil => true,
        else => false,
    };
}

pub fn format(
    self: @This(),
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    switch (self.storage) {
        .number => |n| {
            try writer.print("{d}", .{n});
        },
        .boolean => |b| {
            try writer.print("{}", .{b});
        },
        .nil => {
            try writer.writeAll("nil");
        },
    }
}

pub fn number(n: f64) Value {
    return .{ .storage = .{ .number = n } };
}
