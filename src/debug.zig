const std = @import("std");
const Chunk = @import("Chunk.zig");
const print = std.debug.print;

pub fn disassembleChunk(chunk: *const Chunk, source: ?[]const u8) void {
    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, source, offset);
    }
}

pub fn disassembleInstruction(chunk: *const Chunk, source: ?[]const u8, offset: usize) usize {
    print("0x{x:04} ", .{offset});
    const instruction = chunk.code.items[offset];
    const opcode = std.meta.intToEnum(Chunk.OpCode, instruction) catch {
        print("Unknown opcode {d}\n", .{instruction});
        return offset + 1;
    };
    printSourceLine(chunk, source, offset);
    switch (opcode) {
        .@"return" => {
            print("{s}", .{@tagName(opcode)});
            print("\n", .{});
            return offset + 1;
        },
        .constant => {
            print("{s} ", .{@tagName(opcode)});
            const constant_index = chunk.code.items[offset];
            print("0x{d:02} ", .{constant_index});
            print("{}", .{chunk.constants.items[constant_index]});
            print("\n", .{});
            return offset + 2;
        },
    }
}

fn printSourceLine(chunk: *const Chunk, source: ?[]const u8, offset: usize) void {
    const show_byte_number = blk: {
        if (offset == 0) break :blk true;

        break :blk chunk.debug_info.items[offset - 1] !=
            chunk.debug_info.items[offset];
    };

    const debug_info_position = chunk.debug_info.items[offset];
    if (show_byte_number) {
        print("{d:>4} ", .{debug_info_position});
        if (source) |s| {
            const end = std.mem.indexOfScalarPos(u8, s, debug_info_position, '\n') orelse s.len;
            print("{s} ", .{s[debug_info_position..end]});
        }
    } else {
        print("   | ", .{});
    }
}
