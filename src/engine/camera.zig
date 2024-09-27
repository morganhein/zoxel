//stdlib
const std = @import("std");
// external
const math = @import("zmath");
const core = @import("mach").core;


pub const Camera = struct {
    position: math.Vec,
    target: math.Vec,
    up: math.Vec,

    pub fn lookAt(self: *Camera) math.Mat {
        return math.lookAtRh(self.position, self.target, self.up);
    }

    pub fn perspective(_: *Camera) math.Mat {
        return math.perspectiveFovRh(
            (std.math.pi / 4.0),
            @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
            0.1,
            10,
        );
    }

    pub fn turnY(self: *Camera, angle: f32) void {
        const cosAngle = std.math.cos(angle);
        const sinAngle = std.math.sin(angle);
        self.position = math.Vec{
            self.position[0] * cosAngle - self.position[2] * sinAngle,
            self.position[1],
            self.position[0] * sinAngle + self.position[2] * cosAngle,
            self.position[3],
        };
    }

    pub fn moveForward(self: *Camera, distance: f32) void {
        self.position = self.position + math.f32x4(0, 0, distance, 0);
        self.target = self.target + math.f32x4(0, 0, distance, 0);
    }

    pub fn moveBackward(self: *Camera, distance: f32) void {
        self.position = self.position - math.f32x4(0, 0, distance, 0);
        self.target = self.target - math.f32x4(0, 0, distance, 0);
    }

    pub fn moveRight(self: *Camera, distance: f32) void {
        self.position = self.position + math.f32x4(distance, 0, 0, 0);
        self.target = self.target + math.f32x4(distance, 0, 0, 0);
    }

    pub fn moveLeft(self: *Camera, distance: f32) void {
        self.position = self.position - math.f32x4(distance, 0, 0, 0);
        self.target = self.target - math.f32x4(distance, 0, 0, 0);
    }
};
