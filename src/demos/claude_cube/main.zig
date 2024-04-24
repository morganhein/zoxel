const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;

pub const App = @This();

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,

const Uniforms = struct {
    projection_matrix: [16]f32,
};

pub fn init(app: *App) !void {
    try core.init(.{});

    const shader_module = core.device.createShaderModuleWGSL("cube.wgsl", @embedFile("cube.wgsl"));
    defer shader_module.release();

    // Create a uniform buffer
    const uniforms = Uniforms{
        .projection_matrix = core.perspectiveProjection(std.math.pi / 4.0, core.aspect_ratio, 0.1, 100.0),
    };
    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniforms),
    });
    core.queue.writeBuffer(uniform_buffer, 0, &[_]Uniforms{uniforms});

    // Create a bind group layout
    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = &[_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .type = .uniform, .min_binding_size = @sizeOf(Uniforms) }),
        },
    }));
    defer bind_group_layout.release();

    // Create a bind group
    const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = bind_group_layout,
        .entries = &[_]gpu.BindGroup.Entry{
            gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(Uniforms)),
        },
    }));

    // Fragment state
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
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{bind_group_layout},
    };
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    app.* = .{
        .title_timer = try core.Timer.start(),
        .pipeline = pipeline,
        .uniform_buffer = uniform_buffer,
        .bind_group = bind_group,
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    app.pipeline.release();
    app.uniform_buffer.release();
    app.bind_group.release();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setBindGroup(0, app.bind_group, null);
    pass.draw(18, 1, 0, 0);
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
        try core.printTitle("Cube [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
