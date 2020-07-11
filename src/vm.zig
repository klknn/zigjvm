const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const types = @import("types.zig");

/// Instructions in byte-code as described in
/// https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-6.html#jvms-6.5
const Inst = enum(u8) {
    iload_0 = 26,
    iload_1 = 27,
    iadd = 96,
    ireturn = 172,
};

/// Runtime values in VM
const Obj = union {
    int: i32
};

const Frame = struct {
    class: types.Class,
    code: []u8,
    locals: []Obj,
    stack: []Obj,

    pub fn init(c: types.Class, method: []const u8, args: []const Obj) !Frame {
        // TODO: make these available as struct fields or hashmaps.
        for (c.methods) |m| if (std.mem.eql(u8, m.name, method)) {
            for (m.attributes) |a| if (std.mem.eql(u8, a.name, "Code")) {
                // Code layout
                // https://docs.oracle.com/javase/specs/jvms/se14/html/jvms-4.html#jvms-4.7.3
                const ns = std.mem.bigToNative(u16, @bitCast(u16, a.data[0..2].*));
                const nl = std.mem.bigToNative(u16, @bitCast(u16, a.data[2..4].*));
                var ret = Frame{
                    .class = c,
                    .code = a.data[8..],
                    .locals = try types.allocator.alloc(Obj, nl),
                    // TODO: remove + 1
                    .stack = try types.allocator.alloc(Obj, ns + 1),
                };
                for (args) |arg, i| {
                    ret.locals[i] = arg;
                }
                return ret;
            };
        };
        return error.InvalidParam;
    }

    pub fn exec(self: Frame) Obj {
        var code_ptr: usize = 0;
        var stack_ptr: usize = 0;
        while (true) {
            const inst = @intToEnum(Inst, self.code[code_ptr]);
            code_ptr += 1;
            switch (inst) {
                Inst.iload_0 => {
                    stack_ptr += 1;
                    self.stack[stack_ptr] = self.locals[0];
                },
                Inst.iload_1 => {
                    stack_ptr += 1;
                    self.stack[stack_ptr] = self.locals[1];
                },
                Inst.iadd => {
                    const a = self.stack[stack_ptr].int;
                    stack_ptr -= 1;
                    const b = self.stack[stack_ptr].int;
                    stack_ptr -= 1;
                    stack_ptr += 1;
                    self.stack[stack_ptr] = Obj{ .int = a + b };
                },
                Inst.ireturn => {
                    stack_ptr -= 1;
                    return self.stack[stack_ptr + 1];
                },
                else => {
                    warn("NOT IMPLEMENTED: {}", .{inst});
                    assert(false);
                },
            }
        }
    }
};

test "vm.Frame" {
    const loader = @import("loader.zig");
    const file = try std.fs.cwd().openFile("test/Add.class", .{});
    defer file.close();
    const l = loader.Loader{ .file = file };
    const c = try l.class();
    defer c.deinit();

    const args = [_]Obj{ Obj{ .int = 1 }, Obj{ .int = 2 } };
    const f = try Frame.init(c, "add", args[0..2]);
    assert(f.locals[0].int == 1);
    assert(f.locals[1].int == 2);
    assert(f.exec().int == 1 + 2);
}
