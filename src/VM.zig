const Chunk = @import("Chunk.zig");
const Vm = @This();
const std = @import("std");
const debug = @import("debug.zig");
const debug_trace_execution = @import("main.zig").debug_trace_execution;

const stack_max = 256;

chunk: *Chunk,

/// instruction pointer
// TODO: in book he sais pointer would be faster than index into array check if its true.
// https://craftinginterpreters.com/a-virtual-machine.html#:~:text=Its%20type%20is%20a%20byte%20pointer.%20We%20use%20an%20actual%20real%20C%20pointer%20pointing%20right%20into%20the%20middle%20of%20the%20bytecode%20array%20instead%20of%20something%20like%20an%20integer%20index%20because%20it%E2%80%99s%20faster%20to%20dereference%20a%20pointer%20than%20look%20up%20an%20element%20in%20an%20array%20by%20index.
ip: u32,
stack: std.BoundedArray(Chunk.Value, stack_max),

const Error = error{
    Compile,
    Runtime,
};

pub fn interpret(chunk: *Chunk) Error!void {
    var vm = @This(){
        .chunk = chunk,
        .ip = 0,
        .stack = .{},
    };

    return vm.run();
}

pub fn run(vm: *@This()) Error!void {
    // TODO: gotta go fast use labled switch
    while (true) {
        if (debug_trace_execution) {
            std.debug.print("          ", .{});
            for (vm.stack.slice()) |*value| {
                std.debug.print("[ {} ]", .{value});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(vm.chunk, null, vm.ip);
        }
        const instruction = vm.readOpCode();
        switch (instruction) {
            .@"return" => {
                const value = vm.stack.pop();
                std.debug.print("{}\n", .{value});
                return;
            },
            .add => {
                const b = vm.stack.pop();
                const a = vm.stack.pop();
                vm.stack.appendAssumeCapacity(.{ .inner = a.inner + b.inner });
            },
            .subtract => {
                const b = vm.stack.pop();
                const a = vm.stack.pop();
                vm.stack.appendAssumeCapacity(.{ .inner = a.inner - b.inner });
            },
            .multiply => {
                const b = vm.stack.pop();
                const a = vm.stack.pop();
                vm.stack.appendAssumeCapacity(.{ .inner = a.inner * b.inner });
            },
            .divide => {
                const b = vm.stack.pop();
                const a = vm.stack.pop();
                vm.stack.appendAssumeCapacity(.{ .inner = a.inner / b.inner });
            },
            .constant => {
                const constant = vm.readConstant();
                vm.stack.append(constant) catch return error.Runtime;
            },
            .negate => {
                vm.stack.appendAssumeCapacity(.{ .inner = -vm.stack.pop().inner });
            },
        }
    }
    return;
}

fn readByte(vm: *@This()) u8 {
    defer vm.ip += 1;
    return vm.chunk.code.items[vm.ip];
}

fn readOpCode(vm: *@This()) Chunk.OpCode {
    return @enumFromInt(vm.readByte());
}

fn readConstant(vm: *@This()) Chunk.Value {
    return vm.chunk.constants.items[vm.readByte()];
}

pub fn deinit(self: *@This()) void {
    self.chunk.deinit();
}
