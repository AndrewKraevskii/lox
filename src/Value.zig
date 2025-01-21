const std = @import("std");

const Value = @This();
// same hash as in book
const hash = std.hash.Fnv1a_32.hash;
const Table = @import("Table.zig");

storage: union(enum) {
    boolean: bool,
    number: f64,
    object: *Object,
    nil,
},

pub const Object = struct {
    type: Type,

    pub const String = struct {
        obj: Object,
        hash: u32,
        len: usize,
        ptr: [*]const u8,

        pub fn slice(str: *String) []const u8 {
            return str.ptr[0..str.len];
        }

        pub fn copyString(alloc: std.mem.Allocator, strings: *Table, str: []const u8) error{OutOfMemory}!*String {
            const str_hash = hash(str);

            const maybe_interned = strings.findString(str, str_hash);
            if (maybe_interned) |interned| return interned;

            const duped = try alloc.dupe(u8, str);
            errdefer alloc.free(duped);

            return allocateString(alloc, strings, duped, str_hash);
        }

        pub fn fromSlice(alloc: std.mem.Allocator, strings: *Table, str: []const u8) error{OutOfMemory}!*String {
            const str_hash = hash(str);
            const maybe_interned = strings.findString(str, str_hash);

            if (maybe_interned) |interned| {
                alloc.free(str);
                return interned;
            }

            return allocateString(alloc, strings, str, str_hash);
        }

        pub fn allocateString(alloc: std.mem.Allocator, strings: *Table, str: []const u8, str_hash: u32) error{OutOfMemory}!*String {
            const obj_str = try alloc.create(String);
            obj_str.* = .{
                .obj = .{ .type = .string },
                .len = str.len,
                .ptr = str.ptr,
                .hash = str_hash,
            };

            _ = try strings.set(
                alloc,
                obj_str,
                .nil,
            );
            return obj_str;
        }

        pub fn deinit(str: *String, gpa: std.mem.Allocator) void {
            gpa.free(str.slice());
            gpa.destroy(str);
        }
    };

    pub const Type = enum {
        string,
    };

    pub fn asString(o: *Object) *Object.String {
        return @alignCast(@fieldParentPtr("obj", o));
    }
};

pub const @"true": Value = .{ .storage = .{ .boolean = true } };
pub const @"false": Value = .{ .storage = .{ .boolean = false } };
pub const nil: Value = .{ .storage = .nil };

pub fn isObjType(value: Value, @"type": Object.Type) bool {
    return value.storage == .object and value.storage.object.type == @"type";
}

pub fn fromBool(b: bool) Value {
    return if (b) .true else .false;
}

pub fn isFalsey(v: Value) bool {
    return switch (v.storage) {
        .boolean => |b| !b,
        .nil => true,
        else => false,
    };
}

pub fn isNil(v: Value) bool {
    return v.storage == .nil;
}

pub fn format(
    self: @This(),
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    switch (self.storage) {
        .number => |n| {
            try writer.print("{d}", .{n});
        },
        .boolean => |b| {
            try writer.print("{}", .{b});
        },
        .object => |o| {
            switch (o.type) {
                .string => {
                    const str = o.asString();
                    try writer.print("{s}", .{str.ptr[0..str.len]});
                },
            }
        },
        .nil => {
            try writer.writeAll("nil");
        },
    }
}

/// For object it also checks its type
pub fn valueType(
    self: @This(),
) enum {
    number,
    boolean,
    nil,
    string,
} {
    switch (self.storage) {
        .number => return .number,
        .boolean => return .boolean,
        .nil => return .nil,
        .object => |o| {
            switch (o.type) {
                .string => return .string,
            }
        },
    }
}

pub fn number(n: f64) Value {
    return .{ .storage = .{ .number = n } };
}
