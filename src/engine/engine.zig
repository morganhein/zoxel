//stdlib
const std = @import("std");

// external
const core = @import("mach").core;
const gpu = core.gpu;
const math = @import("zmath");

// internal
const Vertex = @import("cube_mesh.zig").Vertex;
const vertices = @import("cube_mesh.zig").vertices;

const UniformBufferObject = struct {
    model: math.Mat,
    view: math.Mat,
    projection: math.Mat,
};

const Camera = struct {
    position: math.Vec,
    target: math.Vec,
    up: math.Vec,
};

pub const Engine = struct {
    camera: Camera,
    pipeline: *gpu.RenderPipeline,
    vertex_buffer: *gpu.Buffer,
    uniform_buffer: *gpu.Buffer,
    bind_group: *gpu.BindGroup,
    title_timer: core.Timer,
    timer: core.Timer,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Engine {
        try core.init(.{});

        const shader_module = core.device.createShaderModuleWGSL("cube.wgsl", @embedFile("shaders/cube.wgsl"));

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

        const bgle = gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, true, 0);
        const bgl = core.device.createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &.{bgle},
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
        const bind_group = core.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = bgl,
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                },
            }),
        );

        const camera = Camera{
            .position = math.f32x4(0, 4, 2, 1),
            .target = math.f32x4(0, 0, 0, 1),
            .up = math.f32x4(0, 0, 1, 0),
        };
        const title_timer = try core.Timer.start();
        const timer = try core.Timer.start();
        const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

        shader_module.release();
        pipeline_layout.release();
        bgl.release();

        return Engine{
            .camera = camera,
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .uniform_buffer = uniform_buffer,
            .bind_group = bind_group,
            .title_timer = title_timer,
            .timer = timer,
            .allocator = allocator,
        };
    }

    pub fn handle_input(self: *Engine) !bool {
        var iter = core.pollEvents();
        while (iter.next()) |event| {
            switch (event) {
                .key_press => |ev| {
                    if (ev.key == .space) return true;
                    if (ev.key == .w) {
                        self.camera.position = self.camera.position + math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .s) {
                        self.camera.position = self.camera.position - math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .d) {
                        self.camera.position = self.camera.position + math.f32x4(0.1, 0, 0, 0);
                    } else if (ev.key == .a) {
                        self.camera.position = self.camera.position - math.f32x4(0.1, 0, 0, 0);
                    }
                },
                .key_repeat => |ev| {
                    if (ev.key == .space) return true;
                    if (ev.key == .w) {
                        self.camera.position = self.camera.position + math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .s) {
                        self.camera.position = self.camera.position - math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .d) {
                        self.camera.position = self.camera.position + math.f32x4(0.1, 0, 0, 0);
                    } else if (ev.key == .a) {
                        self.camera.position = self.camera.position - math.f32x4(0.1, 0, 0, 0);
                    }
                },
                .close => return true,
                else => {},
            }
        }
    }

    pub fn deinit(self: *Engine) void {
        defer core.deinit();

        self.vertex_buffer.release();
        self.uniform_buffer.release();
        self.bind_group.release();
        self.pipeline.release();
    }

    pub fn update(self: *Engine) !bool {
        var iter = core.pollEvents();
        while (iter.next()) |event| {
            switch (event) {
                .key_press => |ev| {
                    if (ev.key == .space) return true;
                    if (ev.key == .w) {
                        self.camera.position = self.camera.position + math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .s) {
                        self.camera.position = self.camera.position - math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .d) {
                        self.camera.position = self.camera.position + math.f32x4(0.1, 0, 0, 0);
                    } else if (ev.key == .a) {
                        self.camera.position = self.camera.position - math.f32x4(0.1, 0, 0, 0);
                    }
                },
                .key_repeat => |ev| {
                    if (ev.key == .space) return true;
                    if (ev.key == .w) {
                        self.camera.position = self.camera.position + math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .s) {
                        self.camera.position = self.camera.position - math.f32x4(0, 0, 0.1, 0);
                    } else if (ev.key == .d) {
                        self.camera.position = self.camera.position + math.f32x4(0.1, 0, 0, 0);
                    } else if (ev.key == .a) {
                        self.camera.position = self.camera.position - math.f32x4(0.1, 0, 0, 0);
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
            const model = math.identity();
            const view = math.lookAtRh(
                self.camera.position,
                self.camera.target,
                self.camera.up,
            );
            const proj = math.perspectiveFovRh(
                (std.math.pi / 4.0),
                @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
                0.1,
                10,
            );
            const ubo = UniformBufferObject{
                .model = model,
                .view = view,
                .projection = proj,
            };
            queue.writeBuffer(self.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
        }

        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(self.pipeline);
        pass.setVertexBuffer(0, self.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
        pass.setBindGroup(0, self.bind_group, &.{0});
        pass.draw(vertices.len, 1, 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        core.swap_chain.present();
        back_buffer_view.release();

        // update the window title every second
        if (self.title_timer.read() >= 1.0) {
            self.title_timer.reset();
            try core.printTitle("Cube with Camera [ {d}fps ] [ Input {d}hz ]", .{
                core.frameRate(),
                core.inputRate(),
            });
        }

        return false;
    }
};
