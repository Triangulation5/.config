#version 440

/**
 * Camera: mirror. Placeholder shader for the future camera effect pipeline.
 * Intended to mirror/flip the feed and handle camera-space transforms in the
 * shader domain. Not yet compiled to .qsb — nothing references it — it exists
 * to reserve the slot and document the intended layout of assets/shaders/camera.
 */

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    // TODO: sample the camera texture and flip/mirror here.
    fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
}
