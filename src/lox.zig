const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");
const Parser = @import("Parser.zig");

const log = std.log.scoped(.lox);
const max_file_size = 1024 * 1024 * 1024; // 1 GB

pub fn runFile(arena: std.mem.Allocator, path: []const u8) !void {
    const source = try std.fs.cwd().readFileAlloc(arena, path, max_file_size);

    run(arena, source);
}

pub fn runPrompt(arena: std.mem.Allocator) !void {
    log.info("running prompt", .{});
    const stdin = std.io.getStdIn().reader();

    var line: std.ArrayList(u8) = .init(arena);
    while (true) {
        std.debug.print("> ", .{});
        stdin.readUntilDelimiterArrayList(&line, '\n', max_file_size) catch |err| switch (err) {
            error.EndOfStream => return,
            else => |other_errors| return other_errors,
        };
        var run_arena = std.heap.ArenaAllocator.init(arena);
        defer run_arena.deinit();
        run(run_arena.allocator(), line.items);
    }
}

pub fn run(arena: std.mem.Allocator, source: []const u8) void {
    // _ = arena; // autofix
    // log.info("running code:\n{s}", .{source});

    var tokenizer: Tokenizer = .init(source);
    // var number_of_errors: usize = 0;
    var parser = Parser.init(arena, &tokenizer) catch return;

    const expr = parser.parseExpression() catch return;
    parser.print(expr);
    const result = @import("Interpreter.zig").interpret(
        arena,
        source,
        parser.nodes.items,
        expr,
    ) catch |e| {
        log.err("{s}", .{@errorName(e)});
        return;
    };
    std.debug.print("\n", .{});
    result.print();

    std.debug.print("\n", .{});
}

pub fn report(source_code: []const u8, byte: u32, message: []const u8) void {
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
                \\Error: {s}
                \\{d:>4} | {s}
                \\
            , .{
                message,
                line_number + 1,
                line,
            }) catch @panic("failed to write to stdout");
            stdout.writeByteNTimes(' ', 7 + byte - start_of_line_byte_pos) catch @panic("failed to write to stdout");
            stdout.writeAll("^-- Here.\n") catch @panic("failed to write to stdout");
            return;
        }
    }
    @panic("saa");
}
