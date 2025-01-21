const std = @import("std");

const Value = @import("Value.zig");
const String = Value.Object.String;
const Table = @This();

/// entries or tombstones
count: usize,
entries: []Entry,

/// out of 100
const table_max_load_persentage = 75;

const Entry = struct {
    key: ?*String,
    value: Value,

    const tombstone: Entry = .{
        .key = null,
        .value = .true,
    };
};

pub const empty: @This() = .{
    .count = 0,
    .entries = &.{},
};

pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(self.entries);
}

pub fn clear(self: *@This(), gpa: std.mem.Allocator) void {
    gpa.free(self.entries);
    self.* = .init;
}

fn growCapacity(capacity: usize) usize {
    if (capacity < 8) return 8;
    return capacity * 2;
}

fn adjustCapacity(
    self: *@This(),
    gpa: std.mem.Allocator,
    new_capacity: usize,
) error{OutOfMemory}!void {
    const new_buffer = try gpa.alloc(Entry, new_capacity);
    @memset(new_buffer, .{ .key = null, .value = .nil });

    self.count = 0;
    for (self.entries) |entry| {
        const key = entry.key orelse continue;
        const bucket = find(new_buffer, key);
        bucket.* = entry;
        self.count += 1;
    }

    gpa.free(self.entries);
    self.entries = new_buffer;
}

pub fn set(
    self: *@This(),
    gpa: std.mem.Allocator,
    key: *String,
    value: Value,
) !bool {
    if (100 * (self.count + 1) > self.entries.len * table_max_load_persentage) {
        const capacity = growCapacity(self.entries.len);
        try self.adjustCapacity(gpa, capacity);
    }
    const entry = find(self.entries, key);
    const is_new_key = entry.key == null;
    if (is_new_key and entry.value.isNil()) {
        self.count += 1;
    }
    entry.* = .{
        .key = key,
        .value = value,
    };

    return is_new_key;
}

pub fn get(
    self: *@This(),
    key: *String,
) ?*Entry {
    if (self.count == 0) return null;
    const entry = find(self.entries, key);
    if (entry.key == null) return null;
    return entry;
}

pub fn delete(self: *@This(), key: *String) bool {
    if (self.count == 0) return false;
    const bucket = find(self.entries, key);
    if (bucket.key == null) return false;

    bucket.* = .tombstone;
    return true;
}

fn find(entries: []Entry, key: *String) *Entry {
    var bucket = key.hash % entries.len;

    var tombstone: ?*Entry = null;
    while (true) : (bucket = (bucket + 1) % entries.len) {
        const entry = &entries[bucket];

        if (entry.key == null) {
            if (entry.value.isNil()) {
                return if (tombstone) |t| t else entry;
            } else {
                if (tombstone == null) tombstone = entry;
            }
        } else if (entry.key == key) {
            return entry;
        }
    }
}

pub fn findString(table: *Table, str: []const u8, hash: u32) ?*String {
    if (table.count == 0) return null;
    var bucket = hash % table.entries.len;

    while (true) : (bucket = (bucket + 1) % table.entries.len) {
        const entry = &table.entries[bucket];

        if (entry.key == null) {
            if (entry.value.isNil()) {
                return null;
            }
        } else if (entry.key.?.len == str.len and
            entry.key.?.hash == hash and
            std.mem.eql(u8, entry.key.?.slice(), str))
        {
            return entry.key;
        }
    }
}

pub fn addAll(gpa: std.mem.Allocator, from: *const Table, to: *Table) error{OutOfMemory}!void {
    for (from.entries) |entry| {
        if (entry.key) |key| {
            _ = try to.set(gpa, key, entry.value);
        }
    }
}

test Table {
    const alloc = std.testing.allocator;
    var table = empty;
    defer table.deinit(alloc);
    const str: *String = try .copyString(alloc, "hello world");
    defer str.deinit(alloc);
    {
        const is_new = try table.set(
            alloc,
            str,
            .number(10),
        );
        try std.testing.expect(is_new);
    }
    {
        const is_new = try table.set(
            alloc,
            str,
            .number(20),
        );
        try std.testing.expect(!is_new);
    }
    {
        const entry = table.get(str).?;
        try std.testing.expectEqual(entry.value, Value.number(20));
    }
    {
        var second_table = empty;
        defer second_table.deinit(alloc);

        {
            try addAll(alloc, &table, &second_table);
            const entry = second_table.get(str).?;
            try std.testing.expectEqual(entry.value, Value.number(20));
        }
        {
            const different_str: *String = try .copyString(alloc, "hello underworld");
            defer different_str.deinit(alloc);
            const entry = second_table.get(different_str);
            try std.testing.expectEqual(entry, null);
        }
        {
            const entry = second_table.get(str).?;
            try std.testing.expectEqual(entry.value, Value.number(20));
            try std.testing.expect(second_table.delete(str));
            try std.testing.expect(!second_table.delete(str));
            try std.testing.expectEqual(second_table.get(str), null);
        }
    }
}
