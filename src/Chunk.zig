const std = @import("std");

pub const OpCode = enum(u8) {
    constant,
    @"return",
};

pub const Value = struct {
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

pub fn addConstant(self: *@This(), value: Value) error{OutOfMemory}!u8 {
    const position = self.constants.items.len;
    try self.constants.append(self.gpa, value);
    return @intCast(position);
}
