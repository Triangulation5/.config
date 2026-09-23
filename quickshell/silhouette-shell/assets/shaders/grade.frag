#version 440

/**
 * Backdrop grade. Bicubic-upscales the blurred low-resolution lock grab back to
 * screen size, then lays the lock's look over it: it darkens the result, pulls
 * or pushes its colour saturation, adds a soft vignette and mixes in a hint of
 * film grain, so the lock reads as one heavy cinematic layer.
 *
 * Every step's strength is a uniform rather than a constant baked in here, so
 * the settings app's Lock Screen › Backdrop rows can retune the grade without a
 * rebuild. The defaults the shell ships are the numbers this shader used to
 * hard-code: darken 0.62, saturation 1.0, vignette 0.14 (the old 0.86 floor),
 * grain 0.012 (the old 3/255).
 */

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 srcSize;
    float darken;
    float saturate;
    float vignette;
    float grain;
};
layout(binding = 1) uniform sampler2D source;

vec4 cubicW(float t) {
    float t2 = t * t;
    float t3 = t2 * t;
    return vec4(
        (-t3 + 3.0 * t2 - 3.0 * t + 1.0) / 6.0,
        (3.0 * t3 - 6.0 * t2 + 4.0) / 6.0,
        (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) / 6.0,
        t3 / 6.0
    );
}

vec3 bicubic(vec2 uv) {
    vec2 pos = uv * srcSize - 0.5;
    vec2 base = floor(pos);
    vec2 f = pos - base;
    vec4 wx = cubicW(f.x);
    vec4 wy = cubicW(f.y);
    vec3 acc = vec3(0.0);
    for (int j = -1; j <= 2; j++) {
        for (int i = -1; i <= 2; i++) {
            vec2 tc = (base + vec2(float(i), float(j)) + 0.5) / srcSize;
            acc += texture(source, clamp(tc, vec2(0.0), vec2(1.0))).rgb * wx[i + 1] * wy[j + 1];
        }
    }
    return acc;
}

void main() {
    vec3 c = bicubic(qt_TexCoord0) * darken;

    /**
     * Saturation, at Rec. 709 luma so a pull toward grey keeps the perceived
     * brightness of the backdrop. 1.0 leaves the grab untouched.
     */
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(luma), c, saturate);

    vec2 d = qt_TexCoord0 - vec2(0.5);
    float vig = smoothstep(0.95, 0.40, length(d));
    c *= mix(1.0 - vignette, 1.0, vig);

    /**
     * Hash noise, mixed in as a signed offset so it only ever reads as grain —
     * the old constant was 3 levels out of 255, which is what grain defaults to.
     */
    float n = fract(sin(dot(qt_TexCoord0, vec2(12.9898, 78.233))) * 43758.5453);
    c += (n - 0.5) * grain;

    fragColor = vec4(c, 1.0) * qt_Opacity;
}
