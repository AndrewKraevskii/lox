//! https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm

const std = @import("std");
const fs = std.fs;

history: std.ArrayListUnmanaged([]const u8),
string_arena: std.heap.ArenaAllocator.State,

tty: fs.File,

original_termios: std.posix.termios,
raw_termios: std.posix.termios,

pub fn init() !@This() {
    const tty: fs.File = fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |e| {
        std.log.warn("failed to uncook terminal: {s}", .{@errorName(e)});
        return error.FailedToOpenTty;
    };
    const raw, const coocked = uncookTerminal(tty) catch |e| {
        std.log.warn("failed to uncook terminal: {s}", .{@errorName(e)});
        return error.FailedToUncookTerminal;
    };

    return .{
        .string_arena = .{},
        .history = .empty,
        .tty = tty,
        .original_termios = coocked,
        .raw_termios = raw,
    };
}

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    self.string_arena.promote(gpa).deinit();
    self.history.deinit(gpa);
    const termios = self.original_termios;
    std.posix.tcsetattr(self.tty.handle, .FLUSH, termios) catch |e| {
        std.log.err("failed to ununcook terminal: {s}", .{@errorName(e)});
    };
    self.tty.writer().writeAll("\x1B[?1049l" // Disable alternative buffer.
    ++ "\x1B[?47l" // Restore screen.
    ++ "\x1B[u" // Restore cursor position.
    ) catch |e| {
        std.log.err("failed to ununcook terminal: {s}", .{@errorName(e)});
    };
}

fn uncookTerminal(tty: fs.File) !struct { std.posix.termios, std.posix.termios } {
    const original_termios = try std.posix.tcgetattr(tty.handle);
    var raw = original_termios;
    //   ECHO: Stop the terminal from displaying pressed keys.
    // ICANON: Disable canonical ("cooked") input mode. Allows us to read inputs
    //         byte-wise instead of line-wise.
    //   ISIG: Disable signals for Ctrl-C (SIGINT) and Ctrl-Z (SIGTSTP), so we
    //         can handle them as "normal" escape sequences.
    // IEXTEN: Disable input preprocessing. This allows us to handle Ctrl-V,
    //         which would otherwise be intercepted by some terminals.
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    //   IXON: Disable software control flow. This allows us to handle Ctrl-S
    //         and Ctrl-Q.
    //  ICRNL: Disable converting carriage returns to newlines. Allows us to
    //         handle Ctrl-J and Ctrl-M.
    // BRKINT: Disable converting sending SIGINT on break conditions. Likely has
    //         no effect on anything remotely modern.
    //  INPCK: Disable parity checking. Likely has no effect on anything
    //         remotely modern.
    // ISTRIP: Disable stripping the 8th bit of characters. Likely has no effect
    //         on anything remotely modern.
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    // Disable output processing. Common output processing includes prefixing
    // newline with a carriage return.
    raw.oflag.OPOST = false;

    // Set the character size to 8 bits per byte. Likely has no efffect on
    // anything remotely modern.
    raw.cflag.CSIZE = .CS8;

    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;

    try std.posix.tcsetattr(tty.handle, .FLUSH, raw);

    return .{ raw, original_termios };
}

const escape_code = '\x1B';

fn clearLine(self: *@This()) !void {
    try self.tty.writeAll(.{escape_code} ++ "[2K" ++ .{escape_code} ++ "[0G");
}

pub fn getLine(self: *@This(), gpa: std.mem.Allocator) ![]const u8 {
    try std.posix.tcsetattr(self.tty.handle, .FLUSH, self.raw_termios);
    defer std.posix.tcsetattr(self.tty.handle, .FLUSH, self.original_termios) catch {};

    self.tty.writeAll("> ") catch return error.Unexpected;
    var line: std.BoundedArray(u8, 1024) = .{};
    var selected_line = self.history.items.len;

    while (true) {
        const byte = try self.tty.reader().readByte();
        switch (byte) {
            '\r' => {
                try self.tty.writer().writeByte('\r');
                break;
            },
            'q' => return error.EndOfFile,
            escape_code => {
                self.raw_termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;
                self.raw_termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
                try std.posix.tcsetattr(self.tty.handle, .NOW, self.raw_termios);

                var esc_buffer: [8]u8 = undefined;
                const esc_read = try self.tty.read(&esc_buffer);

                self.raw_termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;
                self.raw_termios.cc[@intFromEnum(std.posix.V.MIN)] = 1;

                if (esc_read == 0) {
                    std.debug.print("input: escape\r\n", .{});
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[A")) up: {
                    if (self.history.items.len == 0) break :up;
                    selected_line -|= 1;
                    line = try .fromSlice(self.history.items[selected_line]);
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "[B")) down: {
                    if (self.history.items.len == 0) break :down;
                    selected_line = @min(selected_line + 1, self.history.items.len - 1);
                    line = try .fromSlice(self.history.items[selected_line]);
                } else if (std.mem.eql(u8, esc_buffer[0..esc_read], "a")) {
                    std.debug.print("input: Alt-a\r\n", .{});
                } else {
                    std.debug.print("input: unknown escape sequence\r\n", .{});
                }
                try std.posix.tcsetattr(self.tty.handle, .NOW, self.raw_termios);
            },
            127 => { // del
                _ = line.popOrNull();
            },
            else => {
                // std.debug.print("input: unknown escape sequence {d}\r\n", .{byte});
                try line.append(byte);
            },
        }

        try self.clearLine();
        try self.tty.writeAll("> ");
        try self.tty.writer().writeAll(line.slice());
    }
    try self.tty.writeAll("> ");
    self.tty.writer().writeAll(line.slice()) catch |e| switch (e) {
        else => return error.Unexpected,
    };
    self.tty.writer().writeAll("\r\n") catch |e| switch (e) {
        else => return error.Unexpected,
    };

    var arena = self.string_arena.promote(gpa);
    defer self.string_arena = arena.state;
    const duped_line = try arena.allocator().dupe(u8, line.slice());
    try self.history.append(gpa, duped_line);

    return duped_line;
}
