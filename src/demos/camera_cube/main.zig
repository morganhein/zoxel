const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;
const math = @import("zmath");
const Vertex = @import("cube_mesh.zig").Vertex;
const vertices = @import("cube_mesh.zig").vertices;

pub const App = @This();
const debug: bool = true;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const UniformBufferObject = struct {
    view: math.Mat,
    projection: math.Mat,
};

const Camera = struct {
    position: math.Vec,
    target: math.Vec,
    up: math.Vec,
};

const Cube = struct {
    position: math.Mat,
};

title_timer: core.Timer,
timer: core.Timer,
pipeline: *gpu.RenderPipeline,
vertex_buffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,
instance_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,
cubes: std.ArrayList(Cube),
camera: Camera,
allocator: std.mem.Allocator,

pub fn init(app: *App) !void {
    try core.init(.{});

    app.allocator = gpa.allocator();

    const shader_module = core.device.createShaderModuleWGSL("cube.wgsl", @embedFile("cube.wgsl"));

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const uniformBgle = gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, true, 0);
    const instanceBgle = gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0);
    const bgl = core.device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .entries = &.{uniformBgle, instanceBgle},
        }),
    );

    const bind_group_layouts = [_]*gpu.BindGroupLayout{bgl};
    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &bind_group_layouts,
    }));

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .label = "cube",
        .fragment = &fragment,

        .layout = pipeline_layout,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{vertex_buffer_layout},
        }),
        .primitive = .{
            .cull_mode = .back,
        },
    };

    const vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * vertices.len,
        .mapped_at_creation = .true,
    });
    const vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
    @memcpy(vertex_mapped.?, vertices[0..]);
    vertex_buffer.unmap();

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = .false,
    });

    var cubes = std.ArrayList(Cube).init(app.allocator);

    const positions = [_]math.F32x4{
        math.f32x4(0.0, 0.0, 0.0, 1.0),
        math.f32x4(1.0, 0.0, 0.0, 1.0),
        math.f32x4(1.0, 1.0, 0.0, 1.0),
        math.f32x4(1.0, 1.0, 1.0, 1.0),
    };

    const singelCube = Cube{ .position = math.identity() };
    try cubes.append(singelCube);
    if (debug) {
        const translation = math.Vec{
            singelCube.position[3][0],
            singelCube.position[3][1],
            singelCube.position[3][2],
            singelCube.position[3][3],
        };
        std.debug.print("Identity Cube: {any}\n", .{translation});
    }

    for (positions) |pos| {
        const translated = math.translate(math.identity(), pos);
        try cubes.append(Cube{ .position = translated });
        if (debug) {
            const translation = math.Vec{
                translated[3][0],
                translated[3][1],
                translated[3][2],
                translated[3][3],
            };
            std.debug.print("Cube position: {any}\n", .{translation});
        }
    }

    const instance_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = @sizeOf(math.Mat) * cubes.items.len,
        .mapped_at_creation = .true,
    });

    {
        const mapped = instance_buffer.getMappedRange(math.Mat, 0, cubes.items.len);
        var i: usize = 0;
        for (cubes.items) |cube| {
            mapped.?[i] = cube.position;
            i += 1;
        }
        instance_buffer.unmap();
    }

    const bind_group = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = bgl,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.buffer(1, instance_buffer, 0, @sizeOf(math.Mat) * cubes.items.len),
            },
        }),
    );

    app.title_timer = try core.Timer.start();
    app.timer = try core.Timer.start();
    app.pipeline = core.device.createRenderPipeline(&pipeline_descriptor);
    app.vertex_buffer = vertex_buffer;
    app.uniform_buffer = uniform_buffer;
    app.bind_group = bind_group;
    app.camera = Camera{
        .position = math.f32x4(0, 4, 4, 1),
        .target = math.f32x4(0, 0, 0, 1),
        .up = math.f32x4(0, 0, 1, 0),
    };
    app.instance_buffer = instance_buffer;
    app.cubes = cubes;

    shader_module.release();
    pipeline_layout.release();
    bgl.release();
}

pub fn turnY(position: math.Vec, angle: f32) math.Vec {
    const cosAngle = std.math.cos(angle);
    const sinAngle = std.math.sin(angle);
    return math.Vec{
        position[0] * cosAngle - position[2] * sinAngle,
        position[1],
        position[0] * sinAngle + position[2] * cosAngle,
        position[3],
    };
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer core.deinit();

    app.cubes.deinit();
    app.vertex_buffer.release();
    app.uniform_buffer.release();
    app.instance_buffer.release();
    app.bind_group.release();
    app.pipeline.release();}

pub fn update(app: *App) !bool {

    // const speed = zm.Vec{ delta_time * 5, delta_time * 5, delta_time * 5, delta_time * 5 };

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .space => return true,
                    .q => {
                        // rotate camera to the left
                        app.camera.position = turnY(app.camera.position, 0.1);
                    },
                    .e => {
                        // rotate camera to the right
                        app.camera.position = turnY(app.camera.position, -0.1);
                    },
                    .w => {
                        app.camera.position = app.camera.position + math.f32x4(0, 0, 0.1, 0);
                        app.camera.target = app.camera.target + math.f32x4(0, 0, 0.1, 0);
                    },
                    .s => {
                        app.camera.position = app.camera.position - math.f32x4(0, 0, 0.1, 0);
                        app.camera.target = app.camera.target - math.f32x4(0, 0, 0.1, 0);
                    },
                    .d => {
                        app.camera.position = app.camera.position + math.f32x4(0.1, 0, 0, 0);
                        app.camera.target = app.camera.target + math.f32x4(0.1, 0, 0, 0);
                    },
                    .a => {
                        app.camera.position = app.camera.position - math.f32x4(0.1, 0, 0, 0);
                        app.camera.target = app.camera.target - math.f32x4(0.1, 0, 0, 0);
                    },
                    else => {},
                }
            },
            .key_repeat => |ev| {
                switch (ev.key) {
                    .space => return true,
                    .q => {
                        // rotate camera to the left
                        app.camera.position = turnY(app.camera.position, 0.1);
                    },
                    .e => {
                        // rotate camera to the right
                        app.camera.position = turnY(app.camera.position, -0.1);
                    },
                    .w => {
                        app.camera.position = app.camera.position + math.f32x4(0, 0, 0.1, 0);
                        app.camera.target = app.camera.target + math.f32x4(0, 0, 0.1, 0);
                    },
                    .s => {
                        app.camera.position = app.camera.position - math.f32x4(0, 0, 0.1, 0);
                        app.camera.target = app.camera.target - math.f32x4(0, 0, 0.1, 0);
                    },
                    .d => {
                        app.camera.position = app.camera.position + math.f32x4(0.1, 0, 0, 0);
                        app.camera.target = app.camera.target + math.f32x4(0.1, 0, 0, 0);
                    },
                    .a => {
                        app.camera.position = app.camera.position - math.f32x4(0.1, 0, 0, 0);
                        app.camera.target = app.camera.target - math.f32x4(0.1, 0, 0, 0);
                    },
                    else => {},
                }
            },
            .close => return true,
            else => {},
        }
    }

    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const queue = core.queue;
    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    {
        const view = math.lookAtRh(
            app.camera.position,
            app.camera.target,
            app.camera.up,
        );
        const proj = math.perspectiveFovRh(
            (std.math.pi / 4.0),
            @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
            0.1,
            10,
        );
        const ubo = UniformBufferObject{
            .view = view,
            .projection = proj,
        };
        queue.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.setBindGroup(0, app.bind_group, &.{0});
    pass.draw(vertices.len, @intCast(app.cubes.items.len), 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Cube with Camera [ {d}fps ] [ Input {d}hz ] [ Cube(s): {d} ]", .{
            core.frameRate(),
            core.inputRate(),
            app.cubes.items.len,
        });
    }

    return false;
}