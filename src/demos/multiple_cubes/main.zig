const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;
const math = @import("zmath");
const Vertex = @import("cube_mesh.zig").Vertex;
const vertices = @import("cube_mesh.zig").vertices;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const debug: bool = false;

const UniformBufferObject = struct {
    projection: math.Mat,
    view: math.Mat,
    model: math.Mat,
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
camera: Camera,
cubes: std.ArrayList(Cube),
allocator: std.mem.Allocator,

pub fn init(app: *App) !void {
    try core.init(.{});

    // const allocator = gpa.allocator();
    app.allocator = gpa.allocator();

    const shader_module = core.device.createShaderModuleWGSL("cubes.wgsl", @embedFile("cube.wgsl"));

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
    // const instanceBgle = gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0);
    // const bgl = core.device.createBindGroupLayout(
    //     &gpu.BindGroupLayout.Descriptor.init(.{
    //         .entries = &.{ uniformBgle, instanceBgle },
    //     }),
    // );

    const bgl = core.device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor.init(.{
            .entries = &.{ uniformBgle },
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

    // Create multiple cubes
    var cubes = std.ArrayList(Cube).init(app.allocator);

    // Add cubes and print their positions
    // const positions = [_]math.F32x4{
    //     math.f32x4(0.0, 0.0, 0.0, 1.0),
    //     math.f32x4(1.0, 0.0, 0.0, 1.0),
    //     math.f32x4(1.0, 1.0, 0.0, 1.0),
    //     math.f32x4(1.0, 1.0, 1.0, 1.0),
    // };

    // for (positions) |pos| {
    //     const translated = math.translate(math.identity(), pos);
    //     try cubes.append(Cube{ .position = translated });
    //     if (debug) {
    //         const translation = math.Vec{
    //             translated[3][0],
    //             translated[3][1],
    //             translated[3][2],
    //             translated[3][3],
    //         };
    //         std.debug.print("Cube position: {any}\n", .{translation});
    //     }
    // }

    try cubes.append(Cube{ .position = math.identity() });

    const instance_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = @sizeOf(math.Mat) * cubes.items.len,
        .mapped_at_creation = .true,
    });

    // this code is scoped b/c it was copied from an AI response. Keeping it here just b/c it's interesting
    // and I want to get used to using it.
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
                // gpu.BindGroup.Entry.buffer(1, instance_buffer, 0, @sizeOf(math.Mat) * cubes.items.len),
            },
        }),
    );

    const bind_group2 = core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = bgl,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(1, instance_buffer, 0, @sizeOf(math.Mat) * cubes.items.len),
            },
        }),
    );

    app.title_timer = try core.Timer.start();
    app.timer = try core.Timer.start();
    app.pipeline = core.device.createRenderPipeline(&pipeline_descriptor);
    app.vertex_buffer = vertex_buffer;
    app.uniform_buffer = uniform_buffer;
    app.instance_buffer = instance_buffer;
    app.bind_group = bind_group;
    app.camera = Camera{
        .position = math.f32x4(0, 4, 2, 1),
        .target = math.f32x4(0, 0, 0, 1),
        .up = math.f32x4(0, 0, 1, 0),
    };
    app.cubes = cubes;

    shader_module.release();
    pipeline_layout.release();
    bgl.release();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer core.deinit();

    app.cubes.deinit();
    app.vertex_buffer.release();
    app.uniform_buffer.release();
    app.instance_buffer.release();
    app.bind_group.release();
    app.pipeline.release();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space) return true;
                if (ev.key == .w) {
                    app.camera.position = app.camera.position + math.f32x4(0, 0, 0.1, 0);
                } else if (ev.key == .s) {
                    app.camera.position = app.camera.position - math.f32x4(0, 0, 0.1, 0);
                } else if (ev.key == .d) {
                    app.camera.position = app.camera.position + math.f32x4(0.1, 0, 0, 0);
                } else if (ev.key == .a) {
                    app.camera.position = app.camera.position - math.f32x4(0.1, 0, 0, 0);
                }
            },
            .key_repeat => |ev| {
                if (ev.key == .space) return true;
                if (ev.key == .w) {
                    app.camera.position = app.camera.position + math.f32x4(0, 0, 0.1, 0);
                } else if (ev.key == .s) {
                    app.camera.position = app.camera.position - math.f32x4(0, 0, 0.1, 0);
                } else if (ev.key == .d) {
                    app.camera.position = app.camera.position + math.f32x4(0.1, 0, 0, 0);
                } else if (ev.key == .a) {
                    app.camera.position = app.camera.position - math.f32x4(0.1, 0, 0, 0);
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
            .model = model,
            .view = view,
            .projection = proj,
        };
        queue.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }
    //
    // {
    //     const instance_data = app.cubes.items;
    //     queue.writeBuffer(app.instance_buffer, 0, instance_data);
    // }

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.setBindGroup(0, app.bind_group, &.{ 0 });
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
        try core.printTitle("Cube with Camera [ {d}fps ] [ Input {d}hz ] [ Cube(s): {d}", .{
            core.frameRate(),
            core.inputRate(),
            app.cubes.items.len,
        });
    }

    return false;
}
