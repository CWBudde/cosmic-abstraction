// grade.glsl - G: chroma boost and film grain, sRGB encode happens in main.

#ifndef SATURATION
#define SATURATION 1.12
#endif

// Linear blends lose saturation; give a little back.
vec3 boostChroma(vec3 col) {
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    return max(mix(vec3(lum), col, SATURATION), 0.0);
}

// ---- L8: grain (the chroma grade is applied inline in mainImage) -----------------
vec3 grain(vec3 col, vec2 fragCoord, vec2 p) {
    float n = hash12(fragCoord + 0.37) - 0.5;
    float t = tearCoord(p);
    // quieter in the sky, grittiest in the tear band
    float amp = mix(0.06, 0.10, smoothstep(-0.1, 0.0, t)) + 0.08 * exp(-pow((t - 0.12) / 0.15, 2.0));
    // additive part: film grain still shows in the near-black sky
    float sky = 1.0 - smoothstep(-0.05, 0.05, t);
    return col * (1.0 + amp * n) + vec3(0.8, 0.7, 1.0) * (0.0018 * sky * n);
}

