const std = @import("std");
const builtin = @import("builtin");

const Chunk = @import("Chunk.zig");
const compile = @import("compiler.zig").compile;
const VM = @import("VM.zig");

const is_wasm = builtin.target.isWasm();

const Repl = if (builtin.target.isWasm() or builtin.target.os.tag == .windows)
    @import("DumbRepl.zig")
else
    @import("PosixRepl.zig");

pub const debug_trace_execution = false;

pub fn stdout() @TypeOf(if (is_wasm) @import("wasm_entry.zig").writer else std.io.getStdOut().writer()) {
    return if (is_wasm) @import("wasm_entry.zig").writer else std.io.getStdOut().writer();
}

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const args = try std.process.argsAlloc(arena.allocator());
    switch (args.len) {
        0 => fatal("got 0 arguments", .{}),
        1 => try doRepl(gpa),
        2 => runFile(gpa, args[1]),
        else => fatal("Usage: clox [script]", .{}),
    }
    std.process.cleanExit();
}

fn doRepl(gpa: std.mem.Allocator) !void {
    var repl: Repl = try .init();
    defer repl.deinit(gpa);

    while (true) {
        const line = repl.getLine(gpa) catch |e| switch (e) {
            error.EndOfFile => break,
            else => return e,
        };
        interpret(gpa, line) catch |e| {
            std.log.err("{s}", .{@errorName(e)});
        };
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

pub fn interpret(gpa: std.mem.Allocator, program: []const u8) error{ OutOfMemory, Compile }!void {
    var chunk: Chunk = .init(gpa);
    defer chunk.deinit();
    try compile(program, &chunk);

    var diagnostics: VM.Diagnostics = .init;
    defer diagnostics.deinit(gpa);

    VM.interpret(gpa, &chunk, &diagnostics) catch {
        const source_byte = if (diagnostics.byte < chunk.debug_info.items.len) chunk.debug_info.items[diagnostics.byte] else 0;
        report(program, source_byte, "Runtime error: {s}", .{diagnostics.message});
    };
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

pub fn report(source_code: []const u8, byte: u32, comptime fmt: []const u8, args: anytype) void {
    std.debug.assert(byte <= source_code.len);

    var line_iter = std.mem.splitScalar(u8, source_code, '\n');
    var line_number: u32 = 0;

    while (line_iter.peek()) |line| : (line_number += 1) {
        const start_of_line_byte_pos = line_iter.index orelse source_code.len;
        const end_of_line_byte_pos = start_of_line_byte_pos + line.len;
        _ = line_iter.next();
        if (start_of_line_byte_pos <= byte and byte <= end_of_line_byte_pos) {
            stdout().print(
                \\
                \\
            ++ fmt ++
                \\
                \\{d:>4} | {s}
                \\
            , args ++ .{
                line_number + 1,
                line,
            }) catch @panic("failed to write to stdout");
            stdout().writeByteNTimes(' ', 7 + byte - start_of_line_byte_pos) catch @panic("failed to write to stdout");
            stdout().writeAll("^-- Here.\n") catch @panic("failed to write to stdout");
            return;
        }
    }
    unreachable;
}

test {
    _ = @import("Tokenizer.zig");
    _ = @import("VM.zig");
    _ = @import("Table.zig");
}
