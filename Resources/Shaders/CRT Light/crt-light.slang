#version 450
// Boxer CRT Light: a static, single-sample scanline effect.
// No curvature, temporal animation, blur passes or intermediate upscale.

layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
} params;

layout(std140, set = 0, binding = 0) uniform UBO { mat4 MVP; } global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
void main() {
    vec3 color = texture(Source, vTexCoord).rgb;
    //Fade the scanlines out when the window is too small to resolve them.
    float strength = clamp(params.OutputSize.y / params.SourceSize.y - 1.0, 0.0, 1.0);
    float distanceFromRowCenter = abs(fract(vTexCoord.y * params.SourceSize.y) - 0.5);
    float scanline = 1.0 - 0.36 * strength * distanceFromRowCenter;
    FragColor = vec4(color * scanline, 1.0);
}
