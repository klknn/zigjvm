const std = @import("std");
// const warn = std.debug.warn;
pub fn warn(comptime fmt: []const u8, args: var) void {}
const assert = std.debug.assert;

const types = @import("types.zig");

/// Class file loader type.
pub const Loader = struct {
    file: std.fs.File,

    fn primitive(self: Loader, comptime T: type) !T {
        const size = @sizeOf(T);
        var buffer: [size]u8 = undefined;
        const n = try self.file.read(buffer[0..size]);
        assert(n == size);
        return std.mem.bigToNative(T, @bitCast(T, buffer));
    }

    fn bytes(self: Loader, len: usize) ![]u8 {
        const buf = try types.allocator.alloc(u8, len);
        const n = try self.file.read(buf);
        assert(n == len);
        return buf;
    }

    fn constant(self: Loader) !types.Const {
        return switch (@intToEnum(types.ConstTag, try self.primitive(u8))) {
            types.ConstTag.class => types.Const{
                .class = try self.primitive(u16),
            },
            types.ConstTag.string => types.Const{
                .string = try self.primitive(u16),
            },
            types.ConstTag.utf8 => types.Const{
                .utf8 = try self.bytes(try self.primitive(u16)),
            },
            types.ConstTag.field => types.Const{
                .field = types.FieldRef{
                    .class = try self.primitive(u16),
                    .name_and_type = try self.primitive(u16),
                },
            },
            types.ConstTag.method => types.Const{
                .method = types.FieldRef{
                    .class = try self.primitive(u16),
                    .name_and_type = try self.primitive(u16),
                },
            },
            types.ConstTag.name_and_type => types.Const{
                .name_and_type = types.NameAndType{
                    .name = try self.primitive(u16),
                    .t = try self.primitive(u16),
                },
            },
            types.ConstTag.unused => types.Const{ .unused = true },
        };
    }

    fn constPool(self: Loader) ![]types.Const {
        const len = try self.primitive(u16);
        warn("Class.constant_pool length: {}\n", .{len});
        const ret = try types.allocator.alloc(types.Const, len);
        warn("Class.constant_pool [\n", .{});
        for (ret) |*v, i| {
            // The constant_pool table is indexed from 1 to constant_pool_count - 1.
            // https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html#jvms-4.1
            v.* = if (i == 0)
                types.Const{ .unused = true }
            else
                try self.constant();
            warn("  {}: {}\n", .{ i, v });
        }
        warn("]\n", .{});
        return ret;
    }

    fn interfaces(self: Loader, cls: types.Class) ![]([]const u8) {
        const n = try self.primitive(u16);
        const ret = try types.allocator.alloc([]const u8, n);
        for (ret) |*intf, i| {
            intf.* = cls.utf8(try self.primitive(u16));
            warn("Class.interfaces[{}]: {}", .{ i, intf });
        }
        return ret;
    }

    fn attributes(self: Loader, cls: types.Class) ![]types.Attribute {
        const n = try self.primitive(u16);
        const ret = try types.allocator.alloc(types.Attribute, n);
        for (ret) |*a, i| {
            a.* = types.Attribute{
                .name = cls.utf8(try self.primitive(u16)),
                .data = try self.bytes(try self.primitive(u32)),
            };
            warn("attribute {}, name: {}, len: {}\n", .{
                i, a.name, a.data.len,
            });
        }
        return ret;
    }

    fn fields(self: Loader, cls: types.Class) ![]types.Field {
        const n = try self.primitive(u16);
        const ret = try types.allocator.alloc(types.Field, n);
        for (ret) |*f, i| {
            f.* = types.Field{
                .flags = try self.primitive(u16),
                .name = cls.utf8(try self.primitive(u16)),
                .t = cls.utf8(try self.primitive(u16)),
                .attributes = try self.attributes(cls),
            };
            warn("field {}: {}\n", .{ i, f });
        }
        return ret;
    }

    /// ClassFile {
    ///     u4             magic;
    ///     u2             minor_version;
    ///     u2             major_version;
    ///     u2             constant_pool_count;
    ///     cp_info        constant_pool[constant_pool_count-1];
    ///     u2             access_flags;
    ///     u2             this_class;
    ///     u2             super_class;
    ///     u2             interfaces_count;
    ///     u2             interfaces[interfaces_count];
    ///     u2             fields_count;
    ///     field_info     fields[fields_count];
    ///     u2             methods_count;
    ///     method_info    methods[methods_count];
    ///     u2             attributes_count;
    ///     attribute_info attributes[attributes_count];
    /// }
    pub fn class(self: Loader) !types.Class {
        var ret: types.Class = undefined;

        // Loads header.
        var buffer: [4]u8 = undefined;
        const n = try self.file.read(buffer[0..buffer.len]);
        assert(n == 4);
        assert(buffer[0] == 0xca);
        assert(buffer[1] == 0xfe);
        assert(buffer[2] == 0xba);
        assert(buffer[3] == 0xbe);
        ret.minor_version = try self.primitive(u16);
        ret.major_version = try self.primitive(u16);
        warn("class version {}.{}\n", .{ ret.major_version, ret.minor_version });
        assert(ret.major_version >= 45);

        // Loads constants.
        ret.constant_pool = try self.constPool();

        // Loads class fields.
        ret.flags = try self.primitive(u16);
        ret.name = ret.utf8(try self.primitive(u16));
        warn("Class.name: {}\n", .{ret.name});
        ret.super = ret.utf8(try self.primitive(u16));
        warn("Class.super: {}\n", .{ret.super});
        ret.interfaces = try self.interfaces(ret);
        warn("Class.fields:\n", .{});
        ret.fields = try self.fields(ret);
        warn("Class.methods:\n", .{});
        ret.methods = try self.fields(ret);
        warn("Class.attributes:\n", .{});
        ret.attributes = try self.attributes(ret);
        return ret;
    }
};

test "load test/Add.class" {
    const file = try std.fs.cwd().openFile("test/Add.class", .{});
    defer file.close();

    const loader = Loader{ .file = file };
    const c = try loader.class();
    defer c.deinit();

    // version
    assert(c.major_version == 55);
    assert(c.minor_version == 0);

    // const pool
    assert(c.constant_pool.len == 15);
    assert(c.constant_pool[0].unused);
    assert(c.constant_pool[1].method.class == 3);
    assert(c.constant_pool[1].method.name_and_type == 12);
    assert(c.constant_pool[2].class == 13);
    assert(c.constant_pool[3].class == 14);
    assert(std.mem.eql(u8, c.constant_pool[4].utf8, "<init>"));
    assert(std.mem.eql(u8, c.constant_pool[5].utf8, "()V"));
    assert(std.mem.eql(u8, c.constant_pool[6].utf8, "Code"));
    assert(std.mem.eql(u8, c.constant_pool[7].utf8, "LineNumberTable"));
    assert(std.mem.eql(u8, c.constant_pool[8].utf8, "add"));
    assert(std.mem.eql(u8, c.constant_pool[9].utf8, "(II)I"));
    assert(std.mem.eql(u8, c.constant_pool[10].utf8, "SourceFile"));
    assert(std.mem.eql(u8, c.constant_pool[11].utf8, "Add.java"));
    assert(c.constant_pool[12].name_and_type.name == 4);
    assert(c.constant_pool[12].name_and_type.t == 5);
    assert(std.mem.eql(u8, c.constant_pool[13].utf8, "Add"));
    assert(std.mem.eql(u8, c.constant_pool[14].utf8, "java/lang/Object"));

    // other fields
    assert(std.mem.eql(u8, c.name, "Add"));
    assert(std.mem.eql(u8, c.super, "java/lang/Object"));
    assert(c.fields.len == 0);
    assert(c.methods.len == 2);
    assert(std.mem.eql(u8, c.methods[0].name, "<init>"));
    assert(std.mem.eql(u8, c.methods[1].name, "add"));
    assert(c.attributes.len == 1);
    assert(std.mem.eql(u8, c.attributes[0].name, "SourceFile"));
}
