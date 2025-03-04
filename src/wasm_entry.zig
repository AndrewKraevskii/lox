const std = @import("std");
const log = std.log;

const gpa = std.heap.wasm_allocator;

const js = struct {
    extern "js" fn log(ptr: [*]const u8, len: usize) void;
    extern "js" fn stdout(ptr: [*]const u8, len: usize) void;
    extern "js" fn panic(ptr: [*]const u8, len: usize) noreturn;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .info,
};

pub const writer = std.io.Writer(void, error{}, struct {
    fn write(_: void, bytes: []const u8) !usize {
        js.stdout(bytes.ptr, bytes.len);
        return bytes.len;
    }
}.write){ .context = {} };

pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    log.err("panic: {s}", .{msg});
    @trap();
}

fn logFn(
    comptime message_level: log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buf: [500]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, level_txt ++ prefix2 ++ format, args) catch l: {
        buf[buf.len - 3 ..][0..3].* = "...".*;
        break :l &buf;
    };
    js.log(line.ptr, line.len);
}

export fn alloc(n: usize) [*]u8 {
    const slice = gpa.alloc(u8, n) catch @panic("OOM");
    return slice.ptr;
}

var input_string: std.ArrayListUnmanaged(u8) = .empty;

export fn set_input_string(len: usize) [*]u8 {
    input_string.resize(gpa, len) catch @panic("OOM");
    return input_string.items.ptr;
}

export fn main() void {
    std.log.info("got string: \"{s}\"", .{input_string.items});
    @import("main.zig").interpret(
        gpa,
        input_string.items,
    ) catch {
        std.log.err("compile error", .{});
    };
}
