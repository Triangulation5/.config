#version 440

/**
 * Camera: distortion. Placeholder shader for the future camera distortion /
 * glass-warp effect that gives the Dynamic Island its liquid feel. Not yet
 * compiled to .qsb; reserved for the camera effect pipeline.
 */

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    // TODO: warp the UVs for a lens/glass distortion, then sample the feed.
    fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
}
