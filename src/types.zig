const std = @import("std");

pub var allocator = std.heap.c_allocator; // std.heap.page_allocator;

/// Name and type indices aggregate.
pub const NameAndType = struct {
    name: u16,
    t: u16,
};

/// Field type.
pub const FieldRef = struct {
    class: u16,
    name_and_type: u16,
};

/// Table 4.4-A. Constant pool tags (by section)
/// https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html
pub const ConstTag = enum(u8) {
    unused = 0x0,
    utf8 = 0x1,
    class = 0x7,
    string = 0x8,
    field = 0x9,
    method = 0xa,
    name_and_type = 0xc,
};

/// Values in const pool
pub const Const = union(ConstTag) {
    utf8: []const u8,
    unused: bool,
    class: u16,
    string: u16,
    field: FieldRef,
    method: FieldRef,
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

    // TODO: parse code from data
    // Code_attribute {
    //     u2 attribute_name_index;
    //     u4 attribute_length;
    //     u2 max_stack;
    //     u2 max_locals;
    //     u4 code_length;
    //     u1 code[code_length];
    //     u2 exception_table_length;
    //     {   u2 start_pc;
    //         u2 end_pc;
    //         u2 handler_pc;
    //         u2 catch_type;
    //     } exception_table[exception_table_length];
    //     u2 attributes_count;
    //     attribute_info attributes[attributes_count];
    // }
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

    constant_pool: []Const,
    name: []const u8,
    super: []const u8,
    flags: u16,
    interfaces: []([]const u8),
    fields: []Field,
    methods: []Field,
    attributes: []Attribute,

    pub fn deinit(self: Class) void {
        for (self.constant_pool) |c| {
            c.deinit();
        }
    }

    pub fn utf8(self: Class, index: usize) []const u8 {
        const c = self.constant_pool[index];
        return switch (c) {
            .utf8 => c.utf8,
            .class => self.utf8(c.class),
            else => "",
        };
    }
};
