const std = @import("std");

const lox = @import("lox.zig");

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const args = try std.process.argsAlloc(arena);
    switch (args.len) {
        0 => fatal("got 0 arguments", .{}),
        1 => try lox.runPrompt(arena),
        2 => try lox.runFile(arena, args[1]),
        else => fatal("Usage: jlox [script]", .{}),
    }
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}
