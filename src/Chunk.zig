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

pub fn pushConstant(self: *@This(), value: Value) !void {
    const constant = try self.addConstant(value);
    try self.writeOpcode(.constant, 0);
    try self.writeByte(constant, 0);
}

test "Basic" {
    const alloc = std.testing.allocator;
    var chunk: @This() = .init(alloc);
    defer chunk.deinit();

    const constant = try chunk.addConstant(.{ .inner = 1.2 });
    try chunk.writeOpcode(.constant, 0);
    try chunk.writeByte(constant, 0);
    try chunk.writeOpcode(.@"return", 0);
}
