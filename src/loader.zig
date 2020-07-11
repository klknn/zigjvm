const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;

const types = @import("types.zig");

const Loader = struct {
    file: std.fs.File,

    fn primitive(self: Loader, comptime T: type) !T {
        const size = @sizeOf(T);
        var buffer: [size]u8 = undefined;
        const n = try self.file.read(buffer[0..size]);
        assert(n == size);
        return std.mem.bigToNative(T, @bitCast(T, buffer));
    }

    fn bytes(self: Loader, len: usize) ![]u8 {
        var buf = try types.allocator.alloc(u8, len);
        const n = try self.file.read(buf);
        assert(n == len);
        return buf;
    }

    /// Loads union fields from a given file.
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
                .field = types.ConstField{
                    .class = try self.primitive(u16),
                    .name_and_type = try self.primitive(u16),
                },
            },
            types.ConstTag.method => types.Const{
                .method = types.ConstField{
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
        // Loads a constant pool.
        // The constant_pool table is indexed from 1 to constant_pool_count - 1.
        // https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html#jvms-4.1
        const len = try self.primitive(u16);
        warn("Class.const_pool length: {}\n", .{len});
        var ret = try types.allocator.alloc(types.Const, len);
        warn("Class.const_pool [\n", .{});
        for (ret) |*v, i| {
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
        var ret = try types.allocator.alloc([]const u8, n);
        for (ret) |*intf, i| {
            intf.* = cls.utf8(try self.primitive(u16));
            warn("Class.interfaces[{}]: {}", .{ i, intf });
        }
        return ret;
    }

    fn attributes(self: Loader, cls: types.Class) ![]types.Attribute {
        const n = try self.primitive(u16);
        var ret = try types.allocator.alloc(types.Attribute, n);
        for (ret) |*a, i| {
            a.* = types.Attribute{
                .name = cls.utf8(try self.primitive(u16)),
                .data = try self.bytes(try self.primitive(u32)),
            };
            warn("attribute {}, name: {}, len: {}\n", .{
                i,
                a.name,
                a.data.len,
            });
        }
        return ret;
    }

    fn fields(self: Loader, cls: types.Class) ![]types.Field {
        const n = try self.primitive(u16);
        var ret = try types.allocator.alloc(types.Field, n);
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

    pub fn class(self: Loader) !types.Class {
        var ret: types.Class = undefined;

        // Loads header.
        var buffer: [4]u8 = undefined;
        const bytes_read = try self.file.read(buffer[0..buffer.len]);
        assert(buffer[0] == 0xca);
        assert(buffer[1] == 0xfe);
        assert(buffer[2] == 0xba);
        assert(buffer[3] == 0xbe);
        ret.minor_version = try self.primitive(u16);
        ret.major_version = try self.primitive(u16);
        warn("class version {}.{}\n", .{ ret.major_version, ret.minor_version });
        assert(ret.major_version >= 45);

        // Loads constants.
        ret.const_pool = try self.constPool();

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

    // const pool
    assert(c.const_pool.len == 15);
    assert(c.const_pool[0].unused);
    assert(c.const_pool[1].method.class == 3);
    assert(c.const_pool[1].method.name_and_type == 12);
    assert(c.const_pool[2].class == 13);
    assert(c.const_pool[3].class == 14);
    assert(std.mem.eql(u8, c.const_pool[4].utf8, "<init>"));
    assert(std.mem.eql(u8, c.const_pool[5].utf8, "()V"));
    assert(std.mem.eql(u8, c.const_pool[6].utf8, "Code"));
    assert(std.mem.eql(u8, c.const_pool[7].utf8, "LineNumberTable"));
    assert(std.mem.eql(u8, c.const_pool[8].utf8, "add"));
    assert(std.mem.eql(u8, c.const_pool[9].utf8, "(II)I"));
    assert(std.mem.eql(u8, c.const_pool[10].utf8, "SourceFile"));
    assert(std.mem.eql(u8, c.const_pool[11].utf8, "Add.java"));
    assert(c.const_pool[12].name_and_type.name == 4);
    assert(c.const_pool[12].name_and_type.t == 5);
    assert(std.mem.eql(u8, c.const_pool[13].utf8, "Add"));
    assert(std.mem.eql(u8, c.const_pool[14].utf8, "java/lang/Object"));

    // other fields
    assert(c.fields.len == 0);
    assert(c.methods.len == 2);
    assert(std.mem.eql(u8, c.methods[0].name, "<init>"));
    assert(std.mem.eql(u8, c.methods[1].name, "add"));
    assert(c.attributes.len == 1);
    assert(std.mem.eql(u8, c.attributes[0].name, "SourceFile"));
}