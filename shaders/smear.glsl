// smear.glsl - S: bristle drag of the wet background (paint.glsl, linear colour).
//
// A comb of 2-9 px bristles parallel to the drag; each bristle shows the paint
// picked up at its own hashed distance upstream, so neighbouring bristles carry
// different colours (dry-brush striation, not blur). The drag runs along the
// 35 deg tear and turns to ~50 deg in the warm top right, switching between
// two fixed frames so the comb never shears.

// Drag length in p units: none in the sky, long in the tear band and the
// dry-brush lower middle, shorter in the top right (keeps its ~50 deg strokes).
float dragLen(vec2 p) {
    float t = tearCoord(p);
    float band = smoothstep(-0.02, 0.10, t);
    float topRight = smoothstep(0.55, 0.8, p.y) * smoothstep(0.95, 1.2, p.x);
    float lowRight = smoothstep(1.05, 1.3, p.x) * smoothstep(0.55, 0.35, p.y);  // calm pink wash
    return band * mix(70.0, 40.0, topRight) * (1.0 - 0.8 * burstMask(p)) * (1.0 - 0.85 * lowRight) * PX;
}

vec3 smear(vec2 fragCoord, vec2 p) {
    vec3 col = paintAt(p, false);
#ifndef NO_SMEAR
    float L = dragLen(p);
    if (L > 0.5 * PX) {
        float tr = smoothstep(0.55, 0.75, p.y) * smoothstep(0.95, 1.15, p.x);
        vec2 dir = tr > 0.5 ? vec2(0.6428, 0.7660) : DIR;
        float lc = dot(fragCoord, vec2(-dir.y, dir.x)) * (816.0 / iResolution.y);
        float wb = 2.0 + 7.0 * hash11(floor(lc / 24.0) + 0.5);
        vec3 hb = hash33(vec3(floor(lc / wb), wb, 7.0));
        float wet = hb.y * hb.y * smoothstep(0.1, 0.5, noise(p * vec2(6.0, 9.0) + hb.z));
        if (wet > 0.02)
            col = mix(col, paintAt(p - dir * L * (0.2 + 0.8 * hb.x), true), 0.85 * wet);
    }
#endif
    return col;
}
