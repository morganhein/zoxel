const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;

// This file exists b/c the mach library expects these functions to be in the root of the library,
// then we reverse control of who calls who and start our own internal engine and forward the calls to it.

pub const App = @This();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
engine: Engine,

pub fn init(app: *App) !void {
    app.engine = try Engine.init(gpa.allocator());
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    app.engine.deinit();
}

pub fn update(app: *App) !bool {
    return app.engine.update();
}
