const std = @import("std");

pub fn Octree(comptime T: type) type {
    return struct {
        const Node = struct {
            value: T,
            children: [8]?*Node,
        };

        max_x: usize,
        max_y: usize,
        max_z: usize,

        root: ?*Node,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, max_x: usize, max_y: usize, max_z: usize) Self {
            return Self{
                .root = null,
                .allocator = allocator,
                .max_x = max_x,
                .max_y = max_y,
                .max_z = max_z,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root| {
                self.deinitNode(root);
            }
        }

        fn deinitNode(self: *Self, node: *Node) void {
            for (node.children) |child| {
                if (child) |c| {
                    self.deinitNode(c);
                    self.allocator.destroy(c);
                }
            }
        }

        pub fn insert(self: *Self, value: T, x: usize, y: usize, z: usize, depth: usize) !void {
            if (self.root == null) {
                self.root = try self.allocator.create(Node);
                self.root.?.* = Node{
                    .value = value,
                    .children = [_]?*Node{null} ** 8,
                };
                return;
            }

            var node = self.root.?;
            var d = depth;
            while (d > 0) : (d -= 1) {
                const index = self.getChildIndex(x, y, z, d);
                if (node.children[index] == null) {
                    node.children[index] = try self.allocator.create(Node);
                    node.children[index].?.* = Node{
                        .value = value,
                        .children = [_]?*Node{null} ** 8,
                    };
                    return;
                }
                node = node.children[index].?;
            }
            node.value = value;
        }

        pub fn get(self: Self, x: usize, y: usize, z: usize, depth: usize) ?T {
            var node = self.root;
            var d = depth;
            while (d > 0) : (d -= 1) {
                if (node == null) return null;
                const index = self.getChildIndex(x, y, z, d);
                node = node.?.children[index];
            }
            return if (node) |n| n.value else null;
        }

        fn getChildIndex(_: Self, x: usize, y: usize, z: usize, depth: usize) usize {
            const shift = @as(usize, @intCast(depth));
            // const size = (self.max_x - self.min_x + 1) >> shift;
            const x_offset = x >> shift;
            const y_offset = y >> shift;
            const z_offset = z >> shift;
            const bit_x = @as(u1, @truncate(x_offset - (0 >> shift)));
            const bit_y = @as(u1, @truncate(y_offset - (0 >> shift)));
            const bit_z = @as(u1, @truncate(z_offset - (0 >> shift)));

            var index: usize = 0;
            index |= @as(usize, bit_x) << 0;
            index |= @as(usize, bit_y) << 1;
            index |= @as(usize, bit_z) << 2;

            return index;
        }
    };
}
