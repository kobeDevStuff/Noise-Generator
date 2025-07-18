#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Input noise texture
layout(set = 0, binding = 0, rgba8) readonly uniform image2D input_image;
// Output colored texture
layout(set = 0, binding = 1, rgba8) writeonly uniform image2D output_image;
// Gradient color palette
layout(set = 0, binding = 2, std430) buffer Colors {
    vec4 colors[];
};
layout(set = 0, binding = 3, std430) buffer ParamsBuffer {
    int params[];
};

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(input_image);
    if (coord.x >= size.x || coord.y >= size.y) return;

    vec4 pixel = imageLoad(input_image, coord);
    float value = clamp(pixel.r, 0.0, 1.0);

    vec4 out_color;
    int gradient_mode = params[0] & 1;

    if (gradient_mode == 1) {
        float scaled = value * float(colors.length());
        int index = int(floor(scaled));
        int next_index = min(index + 1, colors.length() - 1);
        out_color = mix(colors[index], colors[next_index], fract(scaled));
    } else {
        int color_index = int(floor(value * float(colors.length())));
        color_index = clamp(color_index, 0, colors.length() - 1);
        out_color = colors[color_index];
    }
    
    imageStore(output_image, coord, out_color);
}