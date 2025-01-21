const std = @import("std");
const is_test = @import("builtin").is_test;

const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");
const debug_trace_execution = @import("main.zig").debug_trace_execution;
const Value = @import("Value.zig");

const VM = @This();
const stdout = if (is_test or @import("builtin").target.isWasm()) std.io.null_writer else std.io.getStdOut().writer();

const stack_max = 256;

chunk: *const Chunk,
/// instruction pointer
// TODO: in book he says pointer would be faster than index into array check if its true.
// https://craftinginterpreters.com/a-virtual-machine.html#:~:text=Its%20type%20is%20a%20byte%20pointer.%20We%20use%20an%20actual%20real%20C%20pointer%20pointing%20right%20into%20the%20middle%20of%20the%20bytecode%20array%20instead%20of%20something%20like%20an%20integer%20index%20because%20it%E2%80%99s%20faster%20to%20dereference%20a%20pointer%20than%20look%20up%20an%20element%20in%20an%20array%20by%20index.
ip: u32,
stack: std.BoundedArray(Value, stack_max),
diagnostics: ?*Diagnostics,
arena: std.heap.ArenaAllocator.State,
strings: Table,

const Table = std.StringHashMapUnmanaged(void);

pub const Diagnostics = struct {
    byte: u32,
    message: []const u8,

    pub const init: Diagnostics = .{
        .byte = undefined,
        .message = "",
    };

    pub fn deinit(self: *Diagnostics, gpa: std.mem.Allocator) void {
        if (self.message.len != 0) {
            gpa.free(self.message);
        }
    }
};

pub const Error = error{
    OutOfMemory,
    Compile,
    Runtime,
};

pub fn interpret(gpa: std.mem.Allocator, chunk: *const Chunk, diagnostics: ?*Diagnostics) Error!void {
    var vm: VM = .{
        .arena = .{},
        .chunk = chunk,
        .ip = 0,
        .stack = .{},
        .diagnostics = diagnostics,
        .strings = .empty,
    };
    defer vm.deinit(gpa);

    return vm.run(gpa);
}

pub fn run(vm: *@This(), gpa: std.mem.Allocator) Error!void {
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
        const ip_for_current_instruction = vm.ip;
        const instruction = vm.readOpCode() orelse return error.Runtime;
        switch (instruction) {
            .@"return" => {
                const value = try vm.popValue();
                std.log.info("result \"{}\"", .{value});
                return;
            },
            inline .add,
            .subtract,
            .multiply,
            .divide,
            .less,
            .greater,
            => |op| {
                const b = try vm.popValue();
                const a = try vm.popValue();
                const result: Value = if (b.storage == .number and a.storage == .number) result: {
                    const a_num, const b_num = .{
                        a.storage.number,
                        b.storage.number,
                    };
                    break :result switch (op) {
                        .add => .number(a_num + b_num),
                        .subtract => .number(a_num - b_num),
                        .multiply => .number(a_num * b_num),
                        .divide => .number(a_num / b_num),
                        .less => .fromBool(a_num < b_num),
                        .greater => .fromBool(a_num > b_num),
                        else => @compileError("Its comptime"),
                    };
                } else if (b.isObjType(.string) and a.isObjType(.string) and op == .add) result: {
                    const str_b = b.storage.object.asString();
                    const str_a = a.storage.object.asString();
                    var arena = vm.arena.promote(gpa);
                    defer vm.arena = arena.state;
                    const concated = try std.mem.concat(arena.allocator(), u8, &.{ str_a.slice(), str_b.slice() });
                    const str_obj: *Value.Object.String = try .fromSlice(arena.allocator(), concated);

                    break :result .{ .storage = .{ .object = &str_obj.obj } };
                } else {
                    if (vm.diagnostics) |d| {
                        d.byte = ip_for_current_instruction;
                        d.message = try std.fmt.allocPrint(gpa, "cant {s} {s} and {s}", .{
                            @tagName(op),
                            @tagName(a.valueType()),
                            @tagName(b.valueType()),
                        });
                    }
                    return error.Runtime;
                };
                vm.stack.appendAssumeCapacity(result);
            },
            .constant => {
                const constant = vm.readConstant() orelse return error.Runtime;
                vm.stack.append(constant) catch return error.Runtime;
            },
            .true => vm.stack.append(.true) catch return error.Runtime,
            .false => vm.stack.append(.false) catch return error.Runtime,
            .nil => vm.stack.append(.nil) catch return error.Runtime,
            .negate => {
                const value = try vm.popValue();
                if (value.storage == .number) {
                    vm.stack.appendAssumeCapacity(.number(-value.storage.number));
                } else {
                    if (vm.diagnostics) |d| {
                        d.byte = ip_for_current_instruction;
                        d.message = "attempt to negate not number";
                    }
                    return error.Runtime;
                }
            },
            .not => {
                const value = try vm.popValue();
                vm.stack.appendAssumeCapacity(.fromBool(value.isFalsey()));
            },
            .equal => {
                const b = try vm.popValue();
                const a = try vm.popValue();
                if (b.isObjType(.string) and a.isObjType(.string)) {
                    const str_b = b.storage.object.asString();
                    const str_a = a.storage.object.asString();
                    vm.stack.appendAssumeCapacity(.fromBool(std.mem.eql(u8, str_a.slice(), str_b.slice())));
                    continue;
                }
                vm.stack.appendAssumeCapacity(.fromBool(std.meta.eql(a, b)));
            },
        }
    }
    return;
}

fn popValue(vm: *@This()) error{Runtime}!Value {
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

fn readConstant(vm: *@This()) ?Value {
    const byte = vm.readByte() orelse return null;
    if (byte >= vm.chunk.constants.items.len) return null;
    return vm.chunk.constants.items[byte];
}

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    self.arena.promote(gpa).deinit();
    self.strings.deinit(gpa);
}

test "basic fuzz VM" {
    try std.testing.fuzz(struct {
        fn fuzz(input: []const u8) !void {
            var chunk = Chunk.init(std.testing.allocator);
            defer chunk.deinit();
            for (input) |byte| {
                try chunk.writeByte(byte, 0);
            }
            VM.interpret(std.testing.allocator, &chunk, null) catch {};
        }
    }.fuzz, .{
        .corpus = &.{},
    });
}
