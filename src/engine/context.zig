const std = @import("std");

pub const Context = struct {
    ctx: *anyopaque,
    vtable: struct {
        allocator: *const fn (ctx: *anyopaque) std.mem.Allocator,
        getWindowSize: *const fn (ctx: *anyopaque) std.meta.Vector(2, f32),
        getCanvasSize: *const fn (ctx: *anyopaque) std.meta.Vector(2, f32),
        getAspectRatio: *const fn (ctx: *anyopaque) f32,
    },

    /// Get meomry allocator
    pub fn allocator(self: Context) std.mem.Allocator {
        return self.vtable.allocator(self.ctx);
    }

    /// Get size of window
    pub fn getWindowSize(self: Context) std.meta.Vector(2, f32) {
        return self.vtable.getWindowSize(self.ctx);
    }

    /// Get size of canvas
    pub fn getCanvasSize(self: Context) std.meta.Vector(2, f32) {
        return self.vtable.getCanvasSize(self.ctx);
    }

    /// Get aspect ratio of drawing area
    pub fn getAspectRatio(self: Context) f32 {
        return self.vtable.getAspectRatio(self.ctx);
    }
};
