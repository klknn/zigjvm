const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
var allocator = std.heap.c_allocator; // std.heap.page_allocator;

/// Load primitive values from a given class file.
fn loadT(comptime T: type, file: std.fs.File) !T {
    const size = @sizeOf(T);
    var buffer: [size]u8 = undefined;
    const n = try file.read(buffer[0..size]);
    assert(n == size);
    return std.mem.bigToNative(T, @bitCast(T, buffer));
}

/// Load bytes from a given class file.
fn loadBytes(len: usize, file: std.fs.File) ![]u8 {
    var buf = try allocator.alloc(u8, len);
    const n = try file.read(buf);
    assert(n == len);
    return buf;
}

const NameAndType = struct {
    name: u16, t: u16
};

const Field = struct {
    class: u16, name_and_type: u16
};

const Method = Field;

// zig fmt: off
/// Table 4.4-A. Constant pool tags (by section)
/// https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html
const ConstTag = enum(u8) {
    unused = 0x0,
    utf8 = 0x1,
    class = 0x7,
    string = 0x8,
    field = 0x9,
    method = 0xa,
    name_and_type = 0xc
};

/// Values in const pool
const Const = union(ConstTag) {
    unused: u1,
    class: u16,
    string: u16,
    field: Field,
    method: Field,
    name_and_type: NameAndType,
    utf8: []const u8, // format will be broken if this field comes first

    pub fn load(file: std.fs.File) !Const {
        return switch (@intToEnum(ConstTag, try loadT(u8, file))) {
            ConstTag.unused => Const{ .unused = 0 },
            ConstTag.class => Const{ .class = try loadT(u16, file) },
            ConstTag.string => Const{ .string = try loadT(u16, file) },
            ConstTag.utf8 => Const{ .utf8 = try loadBytes(try loadT(u16, file), file) },
            ConstTag.field => Const{
                .field = Field{
                    .class = try loadT(u16, file),
                    .name_and_type = try loadT(u16, file),
                },
            },
            ConstTag.method => Const{
                .method = Method{
                    .class = try loadT(u16, file),
                    .name_and_type = try loadT(u16, file),
                },
            },
            ConstTag.name_and_type => Const{
                .name_and_type = NameAndType{
                    .name = try loadT(u16, file),
                    .t = try loadT(u16, file),
                },
            },
        };
    }
};

fn loadConstPool(file: std.fs.File) ![]Const {
    const len = try loadT(u16, file);
    var ret = try allocator.alloc(Const, len);
    // The constant_pool table is indexed from 1 to constant_pool_count - 1.
    // https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html#jvms-4.1
    for (ret) |*c, i| {
        c.* = if (i == 0) Const { .unused = 0 } else
            try Const.load(file);
        warn("{}: {}\n", .{i, c});
    }

    return ret;
}

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const classFile = if (args.len > 1)
        args[1]
    else
        "Add.class";

    var file = try std.fs.cwd().openFile(classFile, .{ .read = true, .write = false });
    defer file.close();

    var buffer: [4]u8 = undefined;
    const bytes_read = try file.read(buffer[0..buffer.len]);
    warn("OK", .{});
}

test "cafebabe" {
    var file = try std.fs.cwd().openFile("Add.class", .{ .read = true, .write = false });
    defer file.close();

    var buffer: [4]u8 = undefined;
    const bytes_read = try file.read(buffer[0..buffer.len]);
    assert(buffer[0] == 0xca);
    assert(buffer[1] == 0xfe);
    assert(buffer[2] == 0xba);
    assert(buffer[3] == 0xbe);

    const minor = try loadT(u16, file);
    const major = try loadT(u16, file);
    warn("class file version {}.{}\n", .{ major, minor });
    assert(major >= 45);
    const cp = try loadConstPool(file);
    assert(std.mem.eql(u8, cp[14].utf8, "java/lang/Object"));
}
