#version 440

/**
 * Camera: scanline. Placeholder shader for the future Face ID scanning sweep —
 * a travelling highlight line that reads like the iPhone Face ID scan. Not yet
 * compiled to .qsb; reserved for the camera effect pipeline.
 */

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    // TODO: draw the travelling scanline driven by a uniform progress value.
    fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
}
