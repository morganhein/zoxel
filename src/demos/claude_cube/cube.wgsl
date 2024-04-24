@vertex
fn vertex_main(
    @builtin(vertex_index) VertexIndex : u32
) -> @builtin(position) vec4<f32> {
    var pos = array<vec2<f32>, 6>(
        vec2<f32>(-0.5, 0.5), // Top-left corner
        vec2<f32>(-0.5, -0.5), // Bottom-left corner
        vec2<f32>(0.5, -0.5), // Bottom-right corner
        vec2<f32>(-0.5, 0.5), // Top-left corner
        vec2<f32>(0.5, -0.5), // Bottom-right corner
        vec2<f32>(0.5, 0.5) // Top-right corner
    );
    return vec4<f32>(pos[VertexIndex], 0.0, 1.0);
}

@fragment
fn frag_main() -> @location(0) vec4<f32> {
    return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
