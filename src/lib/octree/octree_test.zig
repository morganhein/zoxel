const std = @import("std");
const testing = std.testing;
const Octree = @import("octree.zig").Octree;

test "Octree insertion and retrieval" {
    var octree = Octree(i32).init(std.testing.allocator);
    defer octree.deinit();

    try octree.insert(10, 0, 0, 0, 1);
    try octree.insert(20, 1, 0, 0, 1);
    try octree.insert(30, 0, 1, 0, 1);
    try octree.insert(40, 1, 1, 0, 1);
    try octree.insert(50, 0, 0, 1, 1);
    try octree.insert(60, 1, 0, 1, 1);
    try octree.insert(70, 0, 1, 1, 1);
    try octree.insert(80, 1, 1, 1, 1);

    try testing.expectEqual(@as(?i32, 10), octree.get(0, 0, 0, 1));
    try testing.expectEqual(@as(?i32, 20), octree.get(1, 0, 0, 1));
    try testing.expectEqual(@as(?i32, 30), octree.get(0, 1, 0, 1));
    try testing.expectEqual(@as(?i32, 40), octree.get(1, 1, 0, 1));
    try testing.expectEqual(@as(?i32, 50), octree.get(0, 0, 1, 1));
    try testing.expectEqual(@as(?i32, 60), octree.get(1, 0, 1, 1));
    try testing.expectEqual(@as(?i32, 70), octree.get(0, 1, 1, 1));
    try testing.expectEqual(@as(?i32, 80), octree.get(1, 1, 1, 1));
}

test "Octree insertion and retrieval at different depths" {
    var octree = Octree(i32).init(std.testing.allocator);
    defer octree.deinit();

    try octree.insert(10, 0, 0, 0, 1);
    try octree.insert(20, 2, 0, 0, 2);
    try octree.insert(30, 0, 4, 0, 3);
    try octree.insert(40, 6, 4, 0, 3);

    try testing.expectEqual(@as(?i32, 10), octree.get(0, 0, 0, 1));
    try testing.expectEqual(@as(?i32, 20), octree.get(2, 0, 0, 2));
    try testing.expectEqual(@as(?i32, 30), octree.get(0, 4, 0, 3));
    try testing.expectEqual(@as(?i32, 40), octree.get(6, 4, 0, 3));
}

test "Octree retrieval of non-existent values" {
    var octree = Octree(i32).init(std.testing.allocator);
    defer octree.deinit();

    try octree.insert(10, 0, 0, 0, 1);

    try testing.expectEqual(@as(?i32, null), octree.get(1, 0, 0, 1));
    try testing.expectEqual(@as(?i32, null), octree.get(0, 1, 0, 1));
    try testing.expectEqual(@as(?i32, null), octree.get(0, 0, 1, 1));
    try testing.expectEqual(@as(?i32, null), octree.get(1, 1, 1, 1));
}
