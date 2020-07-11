const std = @import("std");

pub var allocator = std.heap.c_allocator; // std.heap.page_allocator;

// zig fmt: off
/// Name and type indices aggregate.
pub const NameAndType = struct {
    name: u16,
    t: u16
};
// zig fmt: on

// zig fmt: off
/// Field type.
pub const ConstField = struct {
    class: u16,
    name_and_type: u16
};
// zig fmt: on

// zig fmt: off
/// Table 4.4-A. Constant pool tags (by section)
/// https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html
pub const ConstTag = enum(u8) {
    unused = 0x0,
    utf8 = 0x1,
    class = 0x7,
    string = 0x8,
    field = 0x9,
    method = 0xa,
    name_and_type = 0xc
};
// zig fmt: on

/// Values in const pool
pub const Const = union(ConstTag) {
    utf8: []const u8,
    unused: bool,
    class: u16,
    string: u16,
    field: ConstField,
    method: ConstField,
    name_and_type: NameAndType,

    /// Destroys utf8 string.
    pub fn deinit(self: Const) void {
        switch (self) {
            .utf8 => allocator.destroy(self.utf8.ptr),
            else => {},
        }
    }
};

/// Attributes contain addition information about fields and classes
/// The most useful is "Code" attribute, which contains actual byte code
pub const Attribute = struct {
    name: []const u8,
    data: []u8,
};

/// Field type is used for both, fields and methods
pub const Field = struct {
    flags: u16,
    name: []const u8,
    t: []const u8,
    attributes: []Attribute,
};

/// Top-level class type.
pub const Class = struct {
    major_version: u16,
    minor_version: u16,

    const_pool: []Const,
    name: []const u8,
    super: []const u8,
    flags: u16,
    interfaces: []([]const u8),
    fields: []Field,
    methods: []Field,
    attributes: []Attribute,

    pub fn deinit(self: Class) void {
        for (self.const_pool) |c| {
            c.deinit();
        }
    }

    fn utf8(self: Class, index: usize) []const u8 {
        const c = self.const_pool[index];
        return switch (c) {
            .utf8 => c.utf8,
            .class => self.utf8(c.class),
            else => "",
        };
    }
};
