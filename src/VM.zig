const std = @import("std");
const is_test = @import("builtin").is_test;

const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");
const debug_trace_execution = @import("main.zig").debug_trace_execution;

const VM = @This();
const stdout = if (is_test) std.io.null_writer else std.io.getStdOut().writer();

const stack_max = 256;

chunk: *const Chunk,

/// instruction pointer
// TODO: in book he says pointer would be faster than index into array check if its true.
// https://craftinginterpreters.com/a-virtual-machine.html#:~:text=Its%20type%20is%20a%20byte%20pointer.%20We%20use%20an%20actual%20real%20C%20pointer%20pointing%20right%20into%20the%20middle%20of%20the%20bytecode%20array%20instead%20of%20something%20like%20an%20integer%20index%20because%20it%E2%80%99s%20faster%20to%20dereference%20a%20pointer%20than%20look%20up%20an%20element%20in%20an%20array%20by%20index.
ip: u32,
stack: std.BoundedArray(Chunk.Value, stack_max),
diagnostics: ?*Diagnostics,

pub const Diagnostics = struct {
    byte: u32 = undefined,
    message: []const u8 = "",
};

pub const Error = error{
    Compile,
    Runtime,
};

pub fn interpret(chunk: *const Chunk, diagnostics: ?*Diagnostics) Error!void {
    var vm = @This(){
        .chunk = chunk,
        .ip = 0,
        .stack = .{},
        .diagnostics = diagnostics,
    };

    return vm.run();
}

pub fn run(vm: *@This()) Error!void {
    // TODO: gotta go fast use labeled switch
    while (true) {
        if (debug_trace_execution) {
            std.debug.print("          ", .{});
            for (vm.stack.slice()) |*value| {
                std.debug.print("[ {} ]", .{value});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(vm.chunk, null, vm.ip);
        }
        const instruction = vm.readOpCode() orelse return error.Runtime;
        switch (instruction) {
            .@"return" => {
                const value = try vm.popValue();
                stdout.print("{}\n", .{value}) catch return error.Runtime;
                return;
            },
            inline .add,
            .subtract,
            .multiply,
            .divide,
            => |op| {
                const b = try vm.popValue();
                const a = try vm.popValue();
                const result = switch (op) {
                    .add => a.inner + b.inner,
                    .subtract => a.inner - b.inner,
                    .multiply => a.inner * b.inner,
                    .divide => a.inner / b.inner,
                    else => comptime unreachable,
                };
                vm.stack.appendAssumeCapacity(.{ .inner = result });
            },

            .constant => {
                const constant = vm.readConstant() orelse return error.Runtime;
                vm.stack.append(constant) catch return error.Runtime;
            },
            .negate => {
                const value = try vm.popValue();
                vm.stack.appendAssumeCapacity(.{ .inner = -value.inner });
            },
        }
    }
    return;
}

fn popValue(vm: *@This()) error{Runtime}!Chunk.Value {
    return vm.stack.popOrNull() orelse {
        if (vm.ip == vm.chunk.code.items.len) {
            if (vm.diagnostics) |d| {
                d.byte = vm.ip;
                d.message = "not enough values on stack";
            }
        }
        return error.Runtime;
    };
}

fn readByte(vm: *@This()) ?u8 {
    if (vm.ip == vm.chunk.code.items.len) {
        if (vm.diagnostics) |d| {
            d.byte = vm.ip;
            d.message = "attempt to read byte out of bounds";
        }
        return null;
    }
    defer vm.ip += 1;
    return vm.chunk.code.items[vm.ip];
}

fn readOpCode(vm: *@This()) ?Chunk.OpCode {
    if (vm.ip == vm.chunk.code.items.len) {
        if (vm.diagnostics) |d| {
            d.byte = vm.ip;
            d.message = "attempt to read instruction out of bounds";
        }
        return null;
    }
    defer vm.ip += 1;
    return std.meta.intToEnum(Chunk.OpCode, vm.chunk.code.items[vm.ip]) catch return null;
}

fn readConstant(vm: *@This()) ?Chunk.Value {
    const byte = vm.readByte() orelse return null;
    if (byte >= vm.chunk.constants.items.len) return null;
    return vm.chunk.constants.items[byte];
}

pub fn deinit(self: *@This()) void {
    self.chunk.deinit();
}

test "basic fuzz VM" {
    try std.testing.fuzz(struct {
        fn fuzz(input: []const u8) !void {
            var chunk = Chunk.init(std.testing.allocator);
            defer chunk.deinit();
            for (input) |byte| {
                try chunk.writeByte(byte, 0);
            }
            VM.interpret(&chunk, null) catch {};
        }
    }.fuzz, .{
        .corpus = &.{},
    });
}
