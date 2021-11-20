const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const assert = std.debug.assert;

test "memo" {
    var b: ?i32 = null;
    assert(b == null);
    b = 2;
    assert(b.? == 2);
}
