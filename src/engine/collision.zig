const std = @import("std");
const assert = std.debug.assert;
const zmath = @import("zmath");

/// Test whether an OBB (oriented AABB) is outside of clipping space.
/// Algorithm description: We simply test whether all vertices is
/// outside of clipping space, the method will report some very close
/// OBBs as inside, but it's fast.
pub inline fn isOBBOutside(obb: []const zmath.Vec) bool {
    assert(obb.len == 8);

    // Get extents of AABB (our clipping space)
    const es = zmath.f32x8(
        obb[0][3],
        obb[1][3],
        obb[2][3],
        obb[3][3],
        obb[4][3],
        obb[5][3],
        obb[6][3],
        obb[7][3],
    );
    const e = @reduce(.Max, es);

    // test x coordinate
    const xs = zmath.f32x8(
        obb[0][0],
        obb[1][0],
        obb[2][0],
        obb[3][0],
        obb[4][0],
        obb[5][0],
        obb[6][0],
        obb[7][0],
    );
    if (@reduce(.Min, xs) > e or @reduce(.Max, xs) < -e) {
        return true;
    }

    // test y coordinate
    const ys = zmath.f32x8(
        obb[0][1],
        obb[1][1],
        obb[2][1],
        obb[3][1],
        obb[4][1],
        obb[5][1],
        obb[6][1],
        obb[7][1],
    );
    if (@reduce(.Min, ys) > e or @reduce(.Max, ys) < -e) {
        return true;
    }

    // test z coordinate
    const zs = zmath.f32x8(
        obb[0][2],
        obb[1][2],
        obb[2][2],
        obb[3][2],
        obb[4][2],
        obb[5][2],
        obb[6][2],
        obb[7][2],
    );
    if (@reduce(.Min, zs) > e or @reduce(.Max, zs) < -e) {
        return true;
    }

    return false;
}
