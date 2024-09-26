@group(0) @binding(0) var<uniform> ubo : mat4x4<f32>;
@group(0) @binding(1) var<storage, read> instance_data : array<mat4x4<f32>>;

// types
struct VertexInput {
    @location(0) position: vec4<f32>,
    @location(1) uv: vec2<f32>,
};

struct InstanceInput {
    @location(2) model_matrix_0: vec4<f32>,
    @location(3) model_matrix_1: vec4<f32>,
    @location(4) model_matrix_2: vec4<f32>,
    @location(5) model_matrix_3: vec4<f32>,
};

struct VertexOutput {
     @builtin(position) position : vec4<f32>,
     @location(0) fragUV : vec2<f32>,
     @location(1) fragPosition: vec4<f32>,
}

// vertex shader
@vertex
fn vertex_main(
    vertex: VertexInput,
    @builtin(instance_index) instance_index: u32
) -> VertexOutput {
    var output: VertexOutput;
    let model = instance_data[instance_index];
    let world_pos = model * vertex.position;
    output.position = ubo * world_pos;
    output.fragUV = vertex.uv;
    output.fragPosition = world_pos;
    return output;
}

//  fragment shader
@fragment
fn fragment_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.fragPosition;
}

