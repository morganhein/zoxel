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
    view: math.Mat,
    projection: math.Mat,
};

const Camera = struct {
    position: math.Vec,
    target: math.Vec,
    up: math.Vec,
};

const Cube = struct {
    // cube position
    position: math.Mat,
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
    // slice of cubes
    cubes: std.ArrayList(Cube),
    instance_buffer: *gpu.Buffer,

    pub fn init(allocator: std.mem.Allocator) !Engine {
        try core.init(.{});

        //const newPosition = math.f32x4(1.0, 0.0, 0.0, 0.0);
        // Create multiple cubes
        var cubes = std.ArrayList(Cube).init(allocator);
        defer cubes.deinit(); // This defer is for safety in case of errors during initialization

        // Add multiple cubes
        try cubes.append(Cube{ .position = math.translate(math.identity(), math.f32x4(0.0, 0.0, 0.0, 1.0)) });
        try cubes.append(Cube{ .position = math.translate(math.identity(), math.f32x4(2.0, 0.0, 0.0, 1.0)) });
        try cubes.append(Cube{ .position = math.translate(math.identity(), math.f32x4(-2.0, 0.0, 0.0, 1.0)) });
        try cubes.append(Cube{ .position = math.translate(math.identity(), math.f32x4(0.0, 2.0, 0.0, 1.0)) });
        try cubes.append(Cube{ .position = math.translate(math.identity(), math.f32x4(0.0, -2.0, 0.0, 1.0)) });

        // `vertex_attributes` defines the layout of vertex data for the GPU. It is an array of `gpu.VertexAttribute` structures, each specifying:
        // 1. The data format of the attribute (e.g., `float32x4` for a 4-component float vector, `float32x2` for a 2-component float vector).
        // 2. The byte offset of the attribute in the vertex structure (`@offsetOf(Vertex, "pos")` for position, `@offsetOf(Vertex, "uv")` for UV coordinates).
        // 3. The shader location binding where the attribute will be accessible in the vertex shader (`0` for position, `1` for UV coordinates).
        // This setup is used to inform the GPU how to interpret the vertex buffer data during rendering.
        // This step is a "shape definition" step, like defining a struct, but does not actually define
        // the values of that shape/struct.
        const vertex_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        };

        // create the layout of the passed information in a buffer
        // The information in this buffer is not normally updated during runtime.
        // It defines shapes/vertices up front in "object" or "model" space.
        // Later the vertices will be transformed into world/screen space
        const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(Vertex),
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        });

        // ! Define fragments/visual attributes of the shapes

        // load the shader
        // ? what does it mean to convert a shader to a module in this context?
        const shader_module = core.device.createShaderModuleWGSL("cube.wgsl", @embedFile("shaders/cube_many.wgsl"));
        defer shader_module.release();

        // create the fragment, which is the color/aesethetics/transparency etc for the objects
        // BlendState controls how the blending is done for color and alpha channels when rendering
        const blend = gpu.BlendState{};
        //  Defines a ColorTargetState for a render pipeline.
        // It specifies the pixel format for the framebuffer's color attachment,
        // the blending state, and the color write mask.
        // The format is taken from a core descriptor,
        // likely indicating the color format (e.g., RGBA, RGB).
        // The blend points to our previously defined BlendState,
        // affecting how new colors are blended with existing ones in the framebuffer.
        // write_mask specifies which color channels (R, G, B, A) can be written to,
        // with all indicating all channels are writable.
        const color_target = gpu.ColorTargetState{
            .format = core.descriptor.format,
            .blend = &blend,
            .write_mask = gpu.ColorWriteMaskFlags.all,
        };

        // Initializes a FragmentState, which is crucial for setting up the fragment shader stage of the graphics pipeline.
        // The module specifies the shader module containing the compiled shader code.
        // entry_point is the name of the function within the shader module to be executed for each fragment; "frag_main" in this case.
        // targets points to an array of ColorTargetState,
        // which describes how the output of the fragment shader is written to the framebuffer.
        // This setup indicates a single color target is used, which is common for many rendering tasks.
        const fragment = gpu.FragmentState.init(.{
            .module = shader_module,
            .entry_point = "frag_main",
            .targets = &.{color_target},
        });

        // ! Define bing groups to send data to GPU

        // Create a bind group layout entry for a buffer. This specifies that the buffer is at binding 0,
        // it will be used for vertex data (`.vertex = true`), it's of type `uniform`, and it's accessible
        // by both the vertex and fragment shaders (the last `true` argument), with a dynamic offset of 0.
        const bgle = gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, true, 0);

        // Create a bind group layout using the previously defined entry. This layout is used to inform the GPU
        // how the buffers are organized in memory. The layout is created by the device and is initialized with
        // the descriptor that contains our entries (in this case, just `bgle`).
        const bgl = core.device.createBindGroupLayout(
            &gpu.BindGroupLayout.Descriptor.init(.{
                .entries = &.{bgle},
            }),
        );
        defer bgl.release();

        // Define an array of pointers to BindGroupLayout objects, initializing it with `bgl`. This array specifies
        // the layout of resources (like buffers and textures) that will be used by the pipeline. Unlike the BindGroupEntry,
        // which defines individual entries (like a single buffer or texture) within a bind group, this step is about
        // organizing those groups at the pipeline level, indicating how different bind groups are structured and accessed.
        const bind_group_layouts = [_]*gpu.BindGroupLayout{bgl};

        // ! Define pipelines that describe how to use the shaders, fragments and shapes

        // Create a pipeline layout using the previously defined array of bind group layouts. This pipeline layout
        // is a higher-level construct that encompasses the entire resource binding architecture for a pipeline.
        // It specifies how bind groups are organized and accessed by the pipeline, contrasting with the BindGroupLayout,
        // which only specifies the layout within a single bind group. This step is crucial for configuring the pipeline
        // to understand the organization of resources across all the bind groups it will use.
        const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
            .bind_group_layouts = &bind_group_layouts,
        }));

        // Bind group entries define individual resources,
        // bind group layouts organize these resources into groups,
        // and pipeline layouts organize how these groups are used by the entire pipeline.
        defer pipeline_layout.release();

        // bind instance information for the cubes
        const instance_attributes = [_]gpu.VertexAttribute{
            .{ .format = .float32x4, .offset = 0, .shader_location = 2 },
            .{ .format = .float32x4, .offset = 16, .shader_location = 3 },
            .{ .format = .float32x4, .offset = 32, .shader_location = 4 },
            .{ .format = .float32x4, .offset = 48, .shader_location = 5 },
        };

        const instance_buffer_layout = gpu.VertexBufferLayout.init(.{
            .array_stride = @sizeOf(math.Mat),
            .step_mode = .instance,
            .attributes = &instance_attributes,
        });

        // Initialize a RenderPipeline descriptor for a "cube" rendering operation.
        // This descriptor configures the GPU pipeline for rendering cubes by specifying various stages and settings:
        // 1. `.label = "cube"`: Assigns a human-readable label to this pipeline configuration for easier identification.
        // 2. `.fragment = &fragment`: Sets the fragment shader to be used for this pipeline. The fragment shader is responsible for determining the color of each pixel of the cube.
        // 3. `.layout = pipeline_layout`: Specifies the pipeline layout, which includes the organization of resources (like buffers and textures) used by both the vertex and fragment shaders.
        // 4. `.vertex = gpu.VertexState.init(...)`: Configures the vertex processing stage of the pipeline. This includes:
        //    - `.module = shader_module`: The shader module containing the vertex shader code.
        //    - `.entry_point = "vertex_main"`: The entry point function name in the shader module for vertex processing.
        //    - `.buffers = &.{vertex_buffer_layout}`: Defines the layout of the vertex buffer(s) that will be used, including how vertex attributes (like position, color) are laid out in memory.
        // 5. `.primitive = .{.cull_mode = .back}`: Sets the primitive assembly and rasterization state, specifically enabling back-face culling. This means that triangles facing away from the camera will not be rendered, optimizing performance by not processing unseen surfaces of the cube.
        // This descriptor is used to create a render pipeline that defines how graphics are rendered from the input vertex data to the final output image, including shader stages, fixed-function states, and resource bindings.
        const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
            .label = "cube",
            .fragment = &fragment,

            .layout = pipeline_layout,
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main",
                .buffers = &.{vertex_buffer_layout, instance_buffer_layout},
            }),
            .primitive = .{
                .cull_mode = .back,
            },
        };

        // This snippet is responsible for creating and initializing a vertex buffer for use in graphics rendering.
        // 1. `vertex_buffer` is created by calling `createBuffer` on a device with specific parameters:
        //    - The buffer's usage is set to vertex, indicating it will store vertex data.
        //    - The size of the buffer is determined by multiplying the size of a single Vertex struct by the number of vertices (`vertices.len`).
        //    - The buffer is created with its memory mapped for immediate access (`mapped_at_creation` set to true).
        // 2. `vertex_mapped` obtains a pointer to the mapped range of the buffer memory, specifying the type of data (Vertex) and the range (from 0 to `vertices.len`).
        // 3. `@memcpy` is used to copy the vertex data from `vertices` array into the mapped buffer memory.
        // 4. Finally, `vertex_buffer.unmap()` is called to unmap the buffer memory, making it ready for use by the GPU.
        const vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .vertex = true },
            .size = @sizeOf(Vertex) * vertices.len,
            .mapped_at_creation = .true,
        });
        const vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
        @memcpy(vertex_mapped.?, vertices[0..]);
        vertex_buffer.unmap();

        // A uniform buffer is created with specific usage flags indicating it can be a destination for copy operations
        // (`copy_dst`) and will be used as a uniform buffer (`uniform`).
        // The size of the buffer is set to the size of a `UniformBufferObject`,
        // and it is not mapped into host-visible memory at creation (`mapped_at_creation = .false`).
        const uniform_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(UniformBufferObject),
            .mapped_at_creation = .false,
        });

        // Create instance buffer
        const instance_buffer = core.device.createBuffer(&.{
            .usage = .{ .vertex = true, .copy_dst = true },
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

        // A bind group is created, which is a collection of resources (buffers, textures, samplers)
        // that can be bound to the rendering pipeline. The bind group is configured with a layout (`bgl`)
        // that specifies how the resources are organized and accessed by the shader.
        // The bind group includes one entry, which is the uniform buffer created earlier, specifying its binding index (0),
        // the buffer itself, the starting offset within the buffer (0), and the size of the data being bound (`@sizeOf(UniformBufferObject)`).
        const bind_group = core.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = bgl,
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                },
            }),
        );

        // Create a camera at the given Vector
        const camera = Camera{
            .position = math.f32x4(0, 4, 2, 1),
            .target = math.f32x4(0, 0, 0, 1),
            .up = math.f32x4(0, 0, 1, 0),
        };

        // start timers, pipeline
        const title_timer = try core.Timer.start();
        const timer = try core.Timer.start();
        const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

        return Engine{
            .camera = camera,
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .uniform_buffer = uniform_buffer,
            .bind_group = bind_group,
            .title_timer = title_timer,
            .timer = timer,
            .allocator = allocator,
            // also allocate a new cubes array
            .cubes = std.ArrayList(Cube).init(allocator),
            // and a new instance buffer
            .instance_buffer = instance_buffer,
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
                else => return false,
            }
        }
        return false;
    }

    pub fn deinit(self: *Engine) void {
        defer core.deinit();

        self.vertex_buffer.release();
        self.uniform_buffer.release();
        self.bind_group.release();
        self.pipeline.release();
    }

    pub fn update(self: *Engine) !bool {
        const stop = try self.handle_input();
        if (stop) return true;

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
            // Create view matrix from camera position
            const view = math.lookAtRh(
                self.camera.position,
                self.camera.target,
                self.camera.up,
            );

            // Create projection matrix
            const proj = math.perspectiveFovRh(
                (std.math.pi / 4.0),
                @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
                0.1,
                100,
            );

            // Combine view and projection matrices
            const view_proj = math.mul(proj, view);

            // Update uniform buffer with view-projection matrix
            const ubo = UniformBufferObject{
                .projection = view_proj,
                .view = view,
            };
            queue.writeBuffer(self.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
        }

        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(self.pipeline);
        pass.setVertexBuffer(0, self.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
        pass.setVertexBuffer(1, self.instance_buffer, 0, @sizeOf(math.Mat) * self.cubes.items.len);
        pass.setBindGroup(0, self.bind_group, &.{0});
        pass.draw(vertices.len, @intCast(self.cubes.items.len), 0, 0);
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
            try core.printTitle("Render [ {d}fps ] [ Input {d}hz ]", .{
                core.frameRate(),
                core.inputRate(),
            });
        }

        return false;
    }

};

fn createInstanceBuffer(self: *Engine) !void {
    const instance_data = try self.allocator.alloc(math.Mat, self.cubes.items.len);
    defer self.allocator.free(instance_data);

    var index: usize = 0;
    for (self.cubes.items) |cube| {
        instance_data[index] = cube.position;
        index += 1;
    }

    self.instance_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true, .copy_dst = true },
        .size = @sizeOf(math.Mat) * instance_data.len,
        .mapped_at_creation = .true,
    });

    const mapped = self.instance_buffer.getMappedRange(math.Mat, 0, instance_data.len);
    @memcpy(mapped.?, instance_data);
    self.instance_buffer.unmap();
}
