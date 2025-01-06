const std = @import("std");

pub const OpCode = enum(u8) {
    constant,
    negate,
    add,
    subtract,
    multiply,
    divide,
    @"return",
};

pub const Value = extern struct {
    inner: f64,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{d}", .{self.inner});
    }
};

gpa: std.mem.Allocator,
code: std.ArrayListUnmanaged(u8),
constants: std.ArrayListUnmanaged(Value),

/// Stores byte of source code from which opcode was generated.
/// we use bytes instead of lines because of this
/// https://www.computerenhance.com/p/byte-positions-are-better-than-line
/// TODO: think of a smarter algorithm.
debug_info: std.ArrayListUnmanaged(u32),

pub fn init(gpa: std.mem.Allocator) @This() {
    return .{
        .code = .empty,
        .constants = .empty,
        .debug_info = .empty,
        .gpa = gpa,
    };
}

pub fn deinit(self: *@This()) void {
    self.code.deinit(self.gpa);
    self.constants.deinit(self.gpa);
    self.debug_info.deinit(self.gpa);
}

pub fn writeOpcode(self: *@This(), opcode: OpCode, source_byte: u32) error{OutOfMemory}!void {
    try self.writeByte(@intFromEnum(opcode), source_byte);
}

pub fn writeByte(self: *@This(), byte: u8, source_byte: u32) error{OutOfMemory}!void {
    try self.code.append(self.gpa, byte);
    try self.debug_info.append(self.gpa, source_byte);
}

pub fn addConstant(self: *@This(), value: Value) error{ OutOfMemory, NoSpaceForConstant }!u8 {
    const position = self.constants.items.len;
    if (position == std.math.maxInt(u8)) return error.NoSpaceForConstant;
    try self.constants.append(self.gpa, value);
    return @intCast(position);
}

fn pushConstant(c: *Chunk, v: Value) error{ OutOfMemory, NoSpaceForConstant }!void {
    const constant = try c.addConstant(v);
    try c.writeOpcode(.constant, 0);
    try c.writeByte(constant, 0);
}

const Chunk = @This();

test Chunk {
    var chunk: Chunk = .init(std.testing.allocator);
    defer chunk.deinit();

    try chunk.pushConstant(.{ .inner = 1.2 });
    try chunk.pushConstant(.{ .inner = 3.4 });

    try chunk.writeOpcode(.add, 0);

    try chunk.pushConstant(.{ .inner = 5.6 });

    try chunk.writeOpcode(.divide, 0);

    try chunk.writeOpcode(.negate, 0);
    try chunk.writeOpcode(.@"return", 0);
}
