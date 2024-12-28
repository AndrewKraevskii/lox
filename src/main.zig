const std = @import("std");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var chunk: Chunk = .init(gpa);
    defer chunk.deinit();

    // chunk.appendAssumeCapacity(@intFromEnum(OpCode.@"return"));
    const constant = try chunk.addConstant(.{ .inner = 1.2 });
    try chunk.writeOpcode(.constant, 0);
    try chunk.writeByte(constant, 0);
    try chunk.writeOpcode(.@"return", 0);

    debug.disassembleChunk(&chunk, null);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}
