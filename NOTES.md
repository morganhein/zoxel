# Notes

## Different Coordinate Systems:
1. Model Space (Object Space):
    This is the coordinate system in which your vertex positions are originally defined. In this space, the coordinates are relative to the model's own origin. It's the space where the vertex buffer's data is defined, as seen with the vertex_attributes and vertex_buffer_layout in the code.
    When you define a shape's vertices, you're working in model space. For example, if you're defining a cube, the coordinates of the cube's vertices are relative to the cube itself, not to the world or the scene it will eventually be placed in.
2. World Space:
    After vertices are defined in model space, they are transformed to world space. This transformation involves moving, rotating, and scaling the model according to its intended position and orientation in the scene or the "world". This step makes the model's coordinates relative to a common world origin, allowing multiple objects to be placed in a shared scene.
3. View Space (Camera Space):
    The next transformation moves the vertices from world space to view space. This involves a transformation based on the camera's position and orientation. In view space, coordinates are defined relative to the camera. This step is crucial for determining what is visible to the camera and how objects are positioned relative to it.
4. Clip Space:
    After view space, vertices are transformed into clip space. This involves a projection transformation, which can be either perspective or orthogonal. This step is necessary for determining how vertices map onto a 2D screen, taking into account the camera's field of view and aspect ratio. In clip space, vertices are prepared for clipping and culling operations that remove vertices outside the camera's view.
5. Screen Space:
    Finally, vertices in clip space are transformed to screen space through a viewport transformation. This step maps the 3D coordinates to specific 2D coordinates on the screen, where rendering takes place. This is where the final image is composed, ready to be displayed to the user.


# Rendering Pipeline Information
```
[Initialize Engine]
         |
         v
[Define Shapes]
         |
         v
[Create Vertex Buffer]
         |
         v
[Define Fragments]
         |
         v
[Create Shader Module]
         |
         v
[Set Up Bind Groups]
         |
         v
[Create Uniform Buffer]
         |
         v
[Define Pipeline]
         |
         v
[Create Render Pipeline]
         |
         v
[Initialize Camera]
         |
         v
[Main Render Loop]
         |
    +----|----+
    |         |
    v         v
[Handle Input]  [Update Camera]
    |         |
    +----+----+
         |
         v
[Update Uniforms]
         |
         v
[Begin Render Pass]
         |
         v
[Set Pipeline and Buffers]
         |
         v
[Draw]
         |
         v
[End Render Pass and Submit]
```

1. Initialization
    * Initialize core systems and WebGPU device.
2. Vertex Attributes Definition
    * Define vertex attributes (position, UVs) that describe the layout of vertex data for the GPU.
3. Vertex Buffer Layout
    * Create a vertex buffer layout using the defined vertex attributes. This layout informs the GPU how to interpret the vertex buffer data during rendering.
4. Shader Module
    * Load and create a shader module from WGSL shader code. This module contains the compiled shader code for both vertex and fragment shaders.
5. Fragment State and Color Target State
    * Define the fragment state, including the shader module and entry point for the fragment shader.
    * Define a color target state that specifies the pixel format, blending state, and color write mask for the framebuffer's color attachment.
6. Bind Group Layout and Pipeline Layout
    * Define bind group layout entries for resources (e.g., buffers) used in shaders.
    * Create a bind group layout using these entries, which describes how resources are organized in memory.
    * Define a pipeline layout that organizes bind group layouts. This layout encompasses the entire resource binding architecture for a pipeline.
7. Render Pipeline
    * Create a render pipeline descriptor that configures the GPU pipeline for rendering. This includes specifying the fragment state, pipeline layout, vertex state, and primitive assembly state.
    * Use the render pipeline for rendering operations, which involves setting up the GPU to process vertex data through the shaders and output the final image.
8. Vertex Buffer Creation and Data Upload
    * Create a vertex buffer with the specified size and usage.
    * Map the buffer memory and copy the vertex data into the buffer.


# Definitions

### Vector: 
A vector is a mathematical entity that has both magnitude and direction. In computer graphics, vectors are often used to represent positions, directions (like normals or movement directions), and other spatial relationships in 2D or 3D space. Vectors can be used to describe how far and in what direction an object moves or points. They are typically represented as a collection of two, three, or more coordinates (e.g., [x, y] for 2D vectors, [x, y, z] for 3D vectors).

### Vertex: 
A vertex (plural: vertices) is a point in space that defines the corners or intersections of geometric shapes. In the context of 3D graphics, a vertex usually contains more than just a position; it can also include other attributes such as color, texture coordinates (UVs), normals (which are vectors indicating the surface orientation), and more. Vertices are the basic units used to define shapes in 3D modeling and computer graphics. When multiple vertices are connected together by edges, they form polygons (e.g., triangles, quads).