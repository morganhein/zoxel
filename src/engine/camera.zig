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

        // Compute the direction vector from position to target
        const direction = self.target - self.position;

        // Rotate the direction vector around the Y-axis
        const rotatedDirection = math.Vec{
            direction[0] * cosAngle - direction[2] * sinAngle,
            direction[1],
            direction[0] * sinAngle + direction[2] * cosAngle,
            direction[3],
        };

        // Update the target by adding the rotated direction to the position
        self.target = self.position + rotatedDirection;
    }

    // z is "forward" / "backward"
    pub fn moveForward(self: *Camera, distance: f32) void {
        self.position = self.position + math.f32x4(0, 0, distance,  0);
        self.target = self.target + math.f32x4(0, 0, distance, 0);
    }

    pub fn moveBackward(self: *Camera, distance: f32) void {
        self.position = self.position - math.f32x4(0, 0, distance,  0);
        self.target = self.target - math.f32x4(0, 0, distance,  0);
    }

    // x is "right" / 'left'
    pub fn moveRight(self: *Camera, distance: f32) void {
        self.position = self.position + math.f32x4(distance, 0, 0, 0);
        self.target = self.target + math.f32x4(distance, 0, 0, 0);
    }

    pub fn moveLeft(self: *Camera, distance: f32) void {
        self.position = self.position - math.f32x4(distance, 0, 0, 0);
        self.target = self.target - math.f32x4(distance, 0, 0, 0);
    }

    // y is "up" / "down"
    pub fn moveUp(self: *Camera, distance: f32) void {
        self.position = self.position + math.f32x4(0, distance, 0, 0);
        self.target = self.target + math.f32x4(0,  distance, 0,0);
    }

    pub fn moveDown(self: *Camera, distance: f32) void {
        self.position = self.position - math.f32x4(0, distance, 0, 0);
        self.target = self.target - math.f32x4(0, distance, 0, 0);
    }
};
