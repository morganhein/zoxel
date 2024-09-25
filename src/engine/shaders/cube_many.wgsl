// Simple fragment shader
@fragment
fn fragment_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Simple lighting calculation
    let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let diffuse = max(dot(in.fragNormal, lightDir), 0.0);
    let color = vec3<f32>(0.7, 0.7, 0.7);  // Gray color
    let finalColor = color * (diffuse + 0.1);  // Add some ambient light

    return vec4<f32>(finalColor, 1.0);
}

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

@vertex
fn vertex_main(
    vertex: VertexInput,
    instance: InstanceInput,
) -> VertexOutput {
    let model = mat4x4<f32>(
        instance.model_matrix_0,
        instance.model_matrix_1,
        instance.model_matrix_2,
        instance.model_matrix_3
    );

    var output: VertexOutput;
    let world_pos = model * vec4<f32>(vertex.position.xyz, 1.0);
    output.position = uniforms.projection * uniforms.view * world_pos;
    output.uv = vertex.uv;
    return output;
}
