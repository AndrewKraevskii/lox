const std = @import("std");
const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");

pub const debug_trace_execution = true;

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var chunk: Chunk = .init(gpa);
    defer chunk.deinit();

    // chunk.appendAssumeCapacity(@intFromEnum(OpCode.@"return"));
    // const constant = try chunk.addConstant(.{ .inner = 1.2 });
    // try chunk.writeOpcode(.constant, 0);
    // try chunk.writeByte(constant, 0);
    try chunk.pushConstant(.{ .inner = 1.2 });
    try chunk.pushConstant(.{ .inner = 3.4 });

    try chunk.writeOpcode(.add, 0);

    try chunk.pushConstant(.{ .inner = 5.6 });

    try chunk.writeOpcode(.divide, 0);

    try chunk.writeOpcode(.negate, 0);
    try chunk.writeOpcode(.@"return", 0);

    const result = @import("VM.zig").interpret(&chunk);
    std.log.info("{any}", .{result});
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

test {
    _ = Chunk;
}
