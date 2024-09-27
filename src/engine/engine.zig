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

// uniform buffers contain data that is constant for all vertices in a draw call
// like lighting, camera position, etc.
const UniformBufferObject = struct {
    view: math.Mat,
    projection: math.Mat,
};

const Cube = struct {
    position: math.Mat,
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

        var cubes = std.ArrayList(Cube).init(allocator);

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

        // instantiate the timer deps
        const title_timer = try core.Timer.start();
        const timer = try core.Timer.start();
        // pipeline
        const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

        const camera = try allocator.create(cam);
        camera.* = cam{
            .position = math.f32x4(0, 4, 4, 1),
            .target = math.f32x4(0, 0, 0, 1),
            .up = math.f32x4(0, 0, 1, 0),
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

        const queue = core.queue;
        const encoder = core.device.createCommandEncoder(null);
        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
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
                camera.turnY(0.1);
            },
            .e => {
                // rotate camera to the right
                camera.turnY(-0.1);
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
};
