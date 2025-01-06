const std = @import("std");

const Chunk = @import("Chunk.zig");
const VM = @import("VM.zig");
const compile = @import("compiler.zig").compile;

pub const debug_trace_execution = true;

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    switch (args.len) {
        0 => fatal("got 0 arguments", .{}),
        1 => try repl(arena.allocator()),
        2 => runFile(arena.allocator(), args[1]),
        else => fatal("Usage: jlox [script]", .{}),
    }
}

fn repl(gpa: std.mem.Allocator) !void {
    var line: std.BoundedArray(u8, 1024) = .{};
    var stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdIn().writer();

    while (true) {
        try stdout.writeAll("> ");

        stdin.streamUntilDelimiter(line.writer(), '\n', null) catch |e| switch (e) {
            error.EndOfStream => break,
            error.StreamTooLong => {},
            else => return e,
        };
        interpret(gpa, line.slice()) catch |e| {
            std.log.err("{s}", .{@errorName(e)});
        };

        line.clear();
    }
}

fn runFile(gpa: std.mem.Allocator, path: []const u8) void {
    const program = std.fs.cwd().readFileAlloc(gpa, path, 4 * 1024 * 1024) catch |e| {
        fatal("Could not read file \"{s}\": {s}", .{ path, @errorName(e) });
    };
    defer gpa.free(program);

    interpret(gpa, program) catch |e| {
        std.log.err("{s}", .{@errorName(e)});
    };
}

fn interpret(gpa: std.mem.Allocator, program: []const u8) error{ OutOfMemory, Compile }!void {
    var chunk: Chunk = .init(gpa);
    defer chunk.deinit();
    try compile(program, &chunk);

    var diagnostics: VM.Diagnostics = .{};
    VM.interpret(&chunk, &diagnostics) catch {
        const source_byte = if (diagnostics.byte < chunk.debug_info.items.len) chunk.debug_info.items[diagnostics.byte] else 0;
        report(program, source_byte, "interpret error: {s}", .{diagnostics.message});
    };
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

pub fn report(source_code: []const u8, byte: u32, comptime fmt: []const u8, args: anytype) void {
    // std.debug.print("{d}\n", .{byte});
    std.debug.assert(byte <= source_code.len);

    const stdout = std.io.getStdOut().writer();

    var line_iter = std.mem.splitScalar(u8, source_code, '\n');
    var line_number: u32 = 0;

    while (line_iter.peek()) |line| : (line_number += 1) {
        const start_of_line_byte_pos = line_iter.index orelse source_code.len;
        const end_of_line_byte_pos = start_of_line_byte_pos + line.len;
        _ = line_iter.next();
        if (start_of_line_byte_pos <= byte and byte <= end_of_line_byte_pos) {
            stdout.print(
                \\
                \\
                \\Error: 
            ++ fmt ++
                \\
                \\{d:>4} | {s}
                \\
            , args ++ .{
                line_number + 1,
                line,
            }) catch @panic("failed to write to stdout");
            stdout.writeByteNTimes(' ', 7 + byte - start_of_line_byte_pos) catch @panic("failed to write to stdout");
            stdout.writeAll("^-- Here.\n") catch @panic("failed to write to stdout");
            return;
        }
    }
    unreachable;
}

test {
    _ = @import("Tokenizer.zig");
    _ = @import("VM.zig");
}
