//stdlib
const std = @import("std");

// external
const core = @import("mach").core;
const gpu = core.gpu;
const math = @import("zmath");

// internal
const Vertex = @import("cube_mesh.zig").Vertex;
const vertices = @import("cube_mesh.zig").vertices;
const cam = @import("camera.zig").Camera;
const RndGen = std.rand.DefaultPrng;

// uniform buffers contain data that is constant for all vertices in a draw call
// like lighting, camera position, etc.
const UniformBufferObject = struct {
    view: math.Mat,
    projection: math.Mat,
};

const Cube = struct {
    position: math.Mat,
    color: math.Vec,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    debug: bool,

    title_timer: core.Timer,
    timer: core.Timer,

    pipeline: *gpu.RenderPipeline,
    vertex_buffer: *gpu.Buffer,
    uniform_buffer: *gpu.Buffer,
    instance_buffer: *gpu.Buffer,
    bind_group: *gpu.BindGroup,

    depth_texture: *gpu.Texture,
    depth_view: *gpu.TextureView,

    cubes: std.ArrayList(Cube),
    camera: *cam,

    pub fn init(allocator: std.mem.Allocator, debug: bool) !Engine {
        try core.init(.{});

        const shader_module = core.device.createShaderModuleWGSL("cubes.wgsl", @embedFile("shaders/cube_many.wgsl"));

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
                .entries = &.{ uniformBgle, instanceBgle },
            }),
        );

        const bind_group_layouts = [_]*gpu.BindGroupLayout{bgl};
        const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
            .bind_group_layouts = &bind_group_layouts,
        }));

        // depth
        const depth_format = gpu.Texture.Format.depth24_plus;
        const depth_texture = core.device.createTexture(&gpu.Texture.Descriptor{
            .size = .{
                .width = core.descriptor.width,
                .height = core.descriptor.height,
                .depth_or_array_layers = 1,
            },
            .mip_level_count = 1,
            .sample_count = 1,
            .dimension = .dimension_2d,
            .format = depth_format,
            .usage = .{ .render_attachment = true },
        });
        const depth_view = depth_texture.createView(null);

        var depth_stencil_state = gpu.DepthStencilState{
            .format = depth_format,
            .depth_write_enabled = gpu.Bool32.true,
            .depth_compare = .less,
            .stencil_front = .{},
            .stencil_back = .{},
        };

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
            .depth_stencil = &depth_stencil_state,
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

        const cubes = try addCubes(1000);

        if (debug) {
            std.debug.print("Created {} cubes\n", .{cubes.items.len});
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

        // instantiate the timer deps
        const title_timer = try core.Timer.start();
        const timer = try core.Timer.start();
        // pipeline
        const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

        const camera = try allocator.create(cam);
        camera.* = cam{
            .position = math.f32x4(0, 4, 4, 1),
            .target = math.f32x4(0, 0, 0, 1),
            .up = math.f32x4(0, 1, 0, 0),
        };
        std.debug.print("\ninit camera position:\n", .{});
        debugCam(debug, camera);

        shader_module.release();
        pipeline_layout.release();
        bgl.release();
        return Engine{
            .debug = debug,
            .camera = camera,
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .uniform_buffer = uniform_buffer,
            .depth_texture = depth_texture,
            .depth_view = depth_view,
            .bind_group = bind_group,
            .title_timer = title_timer,
            .timer = timer,
            .allocator = allocator,
            // also allocate a new cubes array
            .cubes = cubes,
            // and a new instance buffer
            .instance_buffer = instance_buffer,
        };
    }

    pub fn deinit(engine: *Engine) void {
        defer core.deinit();

        engine.cubes.deinit();
        engine.vertex_buffer.release();
        engine.uniform_buffer.release();
        engine.instance_buffer.release();
        engine.bind_group.release();
        engine.pipeline.release();

        engine.depth_texture.release();

        // clean up the camera
        engine.allocator.destroy(engine.camera);
    }

    pub fn update(engine: *Engine) !bool {

        // const speed = zm.Vec{ delta_time * 5, delta_time * 5, delta_time * 5, delta_time * 5 };

        var iter = core.pollEvents();
        while (iter.next()) |event| {
            switch (event) {
                .key_press => |ev| {
                    if (handleKeypress(engine.debug, engine.camera, ev)) {
                        return true;
                    }
                },
                .key_repeat => |ev| {
                    if (handleKeypress(engine.debug, engine.camera, ev)) {
                        return true;
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

        // depth
        const depth_attachment = gpu.RenderPassDepthStencilAttachment{
            .view = engine.depth_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        };

        const queue = core.queue;
        const encoder = core.device.createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
            .depth_stencil_attachment = &depth_attachment,
        });

        {
            const view = math.lookAtRh(
                engine.camera.position,
                engine.camera.target,
                engine.camera.up,
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
            queue.writeBuffer(engine.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
        }

        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(engine.pipeline);
        pass.setVertexBuffer(0, engine.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
        pass.setBindGroup(0, engine.bind_group, &.{0});
        pass.draw(vertices.len, @intCast(engine.cubes.items.len), 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        core.swap_chain.present();
        back_buffer_view.release();

        // update the window title every second
        if (engine.title_timer.read() >= 1.0) {
            engine.title_timer.reset();
            try core.printTitle("Engine With Camera [ {d}fps ] [ Input {d}hz ] [ Cube(s): {d} ]", .{
                core.frameRate(),
                core.inputRate(),
                engine.cubes.items.len,
            });
          debugInfo(engine);
        }

        return false;
    }

    fn handleKeypress(debug: bool, camera: *cam, key: core.KeyEvent) bool {
        debugKeyPress(debug, key);
        switch (key.key) {
            .space => {
                camera.moveUp(0.1);
            },
            .c => {
                camera.moveUp(-0.1);
            },
            .q => {
                // rotate camera to the left
                camera.turnY(-0.1);
            },
            .e => {
                // rotate camera to the right
                camera.turnY(0.1);
            },
            .w => {
                camera.moveForward(0.1);
            },
            .s => {
                camera.moveBackward(0.1);
            },
            .d => {
                camera.moveRight(0.1);
            },
            .a => {
                camera.moveLeft(0.1);
            },
            .escape => {
                return true;
            },
            else => {
                return false;
            },
        }
        return false;
    }

    fn debugInfo(engine: *Engine) void {
        if (!engine.debug) {
            return;
        }
        debugCam(engine.debug, engine.camera);
    }

    pub fn debugCam(debug: bool, camera: *cam) void {
        if (!debug) {
            return;
        }
        std.debug.print("Camera Position: {any}\n", .{camera.position});
        std.debug.print("Camera Target: {any}\n", .{camera.target});
        std.debug.print("Camera Up: {any}\n", .{camera.up});
        std.debug.print("\n", .{});
    }

    fn debugKeyPress(debug: bool, key: core.KeyEvent) void {
        if (!debug) {
            return;
        }
        std.debug.print("Key Pressed: {any}\n", .{key.key});
    }

    pub fn randomColor(rng: *std.Random.Xoshiro256) math.Vec {
        const max_u64 = @as(f32, std.math.maxInt(u64));
        return math.f32x4(
            @as(f32, @floatFromInt(rng.next())) / max_u64,
            @as(f32, @floatFromInt(rng.next())) / max_u64,
            @as(f32, @floatFromInt(rng.next())) / max_u64,
            1.0,
        );
    }

    fn addCubes(allocator: std.mem.Allocator, count: usize) !std.ArrayList(Cube) {
        var cubes = std.ArrayList(Cube).init(allocator);

        const plane_size = count;
        const cube_size = 1.0;
        const total_cubes = plane_size * plane_size;

        try cubes.ensureTotalCapacity(total_cubes);

        var rnd = RndGen.init(0);
        var x: i32 = plane_size / -2;
        std.debug.print("x {d}", .{x});
        while (x < (plane_size / 2)) : (x += 1) {
            var z: i32 = plane_size / -2;
            while (z < (plane_size / 2)) : (z += 1) {
                const position = math.translate(
                    math.identity(),
                    math.f32x4(
                        @as(f32, @floatFromInt(x)) * cube_size,
                        0,
                        @as(f32, @floatFromInt(z)) * cube_size,
                        1
                    )
                );
                cubes.appendAssumeCapacity(Cube{ .position = position, .color = randomColor(&rnd) });
            }
        }
    }
};

test "randomColor returns valid color" {
    var rng = std.rand.DefaultPrng.init(0);
    defer rng.deinit();

    const color = Engine.randomColor(rng);

    try std.testing.expect(color.x >= 0.0 and color.x <= 1.0);
    try std.testing.expect(color.y >= 0.0 and color.y <= 1.0);
    try std.testing.expect(color.z >= 0.0 and color.z <= 1.0);
    try std.testing.expect(color.w == 1.0);
}
