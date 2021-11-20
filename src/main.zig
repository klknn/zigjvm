// Boost Software License - Version 1.0 - August 17th, 2003
//
// Permission is hereby granted, free of charge, to any person or organization
// obtaining a copy of the software and accompanying documentation covered by
// this license (the "Software") to use, reproduce, display, distribute,
// execute, and transmit the Software, and to prepare derivative works of the
// Software, and to permit third-parties to whom the Software is furnished to
// do so, all subject to the following:
//
// The copyright notices in the Software and this entire statement, including
// the above license grant, this restriction and the following disclaimer,
// must be included in all copies of the Software, in whole or in part, and
// all derivative works of the Software, unless such copies or derivative
// works are solely in the form of machine-executable object code generated by
// a source language processor.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
// SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
// FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

const std = @import("std");
const warn = std.debug.warn;
const assert = std.debug.assert;
const loader = @import("loader.zig");
const types = @import("types.zig");

const help = "Usage: zigjvm foo.class";

pub fn main() !u8 {
    types.allocator = std.heap.page_allocator;
    // get args
    const args = try std.process.argsAlloc(types.allocator);
    defer std.process.argsFree(types.allocator, args);
    if (args.len == 1) {
        warn("{s}\n", .{help});
        return 1;
    }
    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        warn("{s}\n", .{help});
        return 0;
    }

    const path = args[1];
    const file = try std.fs.cwd().openFile(path, .{ .write = false });
    defer file.close();

    const l = loader.Loader{ .file = file };
    const c = try l.class();
    defer c.deinit();
    return 0;
}
