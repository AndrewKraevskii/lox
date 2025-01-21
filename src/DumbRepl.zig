const std = @import("std");

stdin: std.fs.File.Reader,
stdout: std.fs.File.Writer,
line: std.BoundedArray(u8, 1024) = .{},

pub fn init() !@This() {
    return .{
        .stdin = std.io.getStdIn().reader(),
        .stdout = std.io.getStdOut().writer(),
    };
}
pub fn deinit(_: *@This(), _: std.mem.Allocator) void {}

pub fn getLine(self: *@This(), _: std.mem.Allocator) ![]const u8 {
    var stdin = std.io.getStdIn().reader();

    try self.stdout.writeAll("> ");

    self.line.clear();
    stdin.streamUntilDelimiter(self.line.writer(), '\n', null) catch |e| switch (e) {
        error.EndOfStream => return error.EndOfFile,
        inline else => |err| return err,
    };
    return self.line.slice();
}
