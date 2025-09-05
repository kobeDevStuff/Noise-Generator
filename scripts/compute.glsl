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
        // Handle edge cases properly for gradient mode
        if (colors.length() <= 1) {
            // If we only have one color or no colors, use that color
            out_color = colors.length() > 0 ? colors[0] : vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            // Scale value to color range, but prevent out-of-bounds access
            float scaled = value * float(colors.length() - 1);
            int index = int(floor(scaled));
            int next_index = index + 1;
            
            // Clamp indices to valid range
            index = clamp(index, 0, colors.length() - 1);
            next_index = clamp(next_index, 0, colors.length() - 1);
            
            // Calculate interpolation factor
            float t = fract(scaled);
            
            // Ensure both colors have full alpha if they should
            vec4 color1 = colors[index];
            vec4 color2 = colors[next_index];
            
            // If either color has zero alpha, this could cause transparency artifacts
            // Ensure alpha is at least preserved properly
            if (color1.a == 0.0) color1.a = 1.0;
            if (color2.a == 0.0) color2.a = 1.0;
            
            out_color = mix(color1, color2, t);
        }
    } else {
        // Discrete color mode
        int color_index = int(floor(value * float(colors.length())));
        color_index = clamp(color_index, 0, colors.length() - 1);
        out_color = colors[color_index];
        
        // Ensure alpha is set properly
        if (out_color.a == 0.0) out_color.a = 1.0;
    }
    
    // Ensure final output has proper alpha
    out_color.a = 1.0;
    
    imageStore(output_image, coord, out_color);
}