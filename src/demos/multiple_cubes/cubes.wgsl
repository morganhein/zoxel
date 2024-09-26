struct Uniforms {
    view : mat4x4<f32>,
    projection : mat4x4<f32>,
}

struct Cube {
    position : mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> ubo : Uniforms;
@group(0) @binding(1) var<storage, read> instance_data : array<Cube>;

struct VertexOut {
     @builtin(position) position_clip : vec4<f32>,
     @location(0) fragUV : vec2<f32>,
     @location(1) fragPosition: vec4<f32>,
}

@vertex fn vertex_main(
     // this is the position of the vertex in model space.
     // this function is run for each vertex, and the instance index is the same for every triangle, so all
     // three points will use the same instance index.
     @location(0) position : vec4<f32>,
     @location(1) uv: vec2<f32>,
     @builtin(instance_index) instance_index: u32
) -> VertexOut {
     var output : VertexOut;

     // Get the model matrix for this instance
     let cube = instance_data[instance_index];

     // Calculate the position in world space
     var worldPosition : vec4<f32> = cube.position * position;

     // Calculate the position in view space
     var viewPosition : vec4<f32> = ubo.view * worldPosition;

     // Calculate the position in clip space
     output.position_clip = ubo.projection * viewPosition;

     output.fragUV = uv;
     output.fragPosition = 0.5 * (position + vec4<f32>(1.0, 1.0, 1.0, 1.0));

     return output;
}

@fragment fn frag_main(
    @location(0) fragUV: vec2<f32>,
    @location(1) fragPosition: vec4<f32>
) -> @location(0) vec4<f32> {
//    return vec4<f32>(1.0, 0.0, 0.0, 1.0); // Red color
    return fragPosition;
}
