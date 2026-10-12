// rival_b.glsl - Rival B, "directional smear".
//
// The picture is modelled as paint that was thrown and then dragged: a crisp
// pre-smear painting is rendered first, then smeared along a flow field, and
// only the marks that have to stay crisp are drawn afterwards.
//
// Passes (Shadertoy: Buffer A -> iChannel0 of Image, filter linear, clamp):
//   Buffer A  rival_b_paint.glsl   crisp paint: wash, tear lumps, dark
//                                  splats, burst splatter, ink slashes,
//                                  grain; alpha = wetness
//   Image     this file
//     S  smear   bristle drag of Buffer A along the flow field. The flow is
//                the level lines of a stream function psi (35 deg, wobbled),
//                overridden by fixed-angle zones (52 deg top right, 5 deg
//                right middle, 100 deg drips) and the near-vertical burst.
//                The brush is a comb of 2-9 px bristle lines (level lines of
//                psi / zone lines, dithered at zone borders); each bristle
//                picks paint up at its own hashed distance upstream (load
//                window) plus a fading trail -> striated streaks, not blur.
//                Length per pixel from the smear map (long in the tear and
//                dry-brush zone, ~0 in the sky), scaled by wetness (alpha);
//                dry paint (leaves, flakes) is neither dragged nor picked up.
//     C  crisp   marks drawn after the smear: C1 pink sky specks / chipped
//                flakes and dust, C2 orange sparks and radial burst shards,
//                C3 navy ink specks on the warm side, C4 dark and magenta
//                specks over the dragged tear / dry-brush paint
//     G  grade   film grain (less in the sky), sRGB encode
// Shared helpers: rival_b_common.glsl (directions, windows, tear distance).
//
// iTime makes the smear flow slowly downstream (t = 0 is the scored frame).
// Debug: -D SHOW_PAINT=1 shows Buffer A unsmeared, -D SHOW_LEN=1 the smear
// map, -D ONLY_SMEAR=1 the smear without the crisp marks.

#bufferA "rival_b_paint.glsl"

#ifndef EXPOSURE
#define EXPOSURE 1.0
#endif
#ifndef SMEAR
#define SMEAR 1.0
#endif

#include "rival_b_common.glsl"

const int TAPS = 28;

// ---- flow field ------------------------------------------------------------
// Drag direction (unit vector in pixel space).
// Stream function of the base drag (pixels): its level lines are the drag
// lines, so the bristle comb can use it directly and stays aligned with the
// flow (no shear moire where the flow bends).
float psi(vec2 fc) {
    vec2 uv = fc / iResolution.xy;
    return dot(fc, ACROSS) + 80.0 * (fbm(uv * vec2(3.0, 2.2) + 2.0, 2) - 0.5)
         + 28.0 * (noise(uv * vec2(11.0, 8.0) + 5.0) - 0.5);
}

// Zones where the drag runs at its own fixed angle (radians); w = weight.
//   top right: the coral field is dragged steeper (52 deg)
//   right middle: the drag flattens out to almost horizontal (5 deg)
//   lower right: drips run down, leaning a little left (100 deg)
float zoneAngle(vec2 uv, out float w) {
    float wt = win(uv, vec4(0.52, 0.62, 1.1, 1.1), 0.06);
    float wm = 0.8 * win(uv, vec4(0.74, 0.27, 1.1, 0.50), 0.05);
    float wd = 0.8 * win(uv, vec4(0.70, -0.1, 1.1, 0.22), 0.05);
    w = max(wt, max(wm, wd));
    return wt >= max(wm, wd) ? radians(52.0) : (wm >= wd ? radians(5.0) : radians(100.0));
}

// Burst weight: there the paint is thrown up and down (near vertical).
float burstW(vec2 uv) {
    return max(win(uv, vec4(0.26, 0.58, 0.50, 1.10), 0.07), win(uv, vec4(0.24, 0.48, 0.45, 0.70), 0.05));
}

vec2 flowDir(vec2 uv) {
    vec2 fc = uv * iResolution.xy;
    vec2 g = vec2(psi(fc + vec2(1.0, 0.0)) - psi(fc - vec2(1.0, 0.0)),
                  psi(fc + vec2(0.0, 1.0)) - psi(fc - vec2(0.0, 1.0)));
    vec2 dir = normalize(vec2(-g.y, g.x));
    float a = atan(dir.y, dir.x);
    float wz;
    float az = zoneAngle(uv, wz);
    a = mix(a, az, wz);
    a = mix(a, radians(95.0) + radians(50.0) * (noise(uv * 9.0) - 0.5), burstW(uv));
    return vec2(cos(a), sin(a));
}

// Smear length in pixels.
float smearLen(vec2 uv, float asp) {
    float td = tearDist(uv, asp);
    float sky = 1.0 - smoothstep(-0.12, 0.0, td);
    float L = mix(30.0, 3.0, sky);
    L += 50.0 * smoothstep(-0.03, 0.05, td) * (1.0 - smoothstep(0.25, 0.4, td));  // tear
    L += 50.0 * win(uv, vec4(0.28, -0.1, 0.75, 0.40), 0.08);                      // dry brush
    L += 30.0 * win(uv, vec4(-0.1, -0.1, 0.25, 0.20), 0.06);                      // lower-left drag
    L = mix(L, 18.0, win(uv, vec4(0.26, 0.58, 0.58, 1.10), 0.06));                 // burst
    return L * SMEAR;
}

vec3 smear(vec2 fragCoord, float asp) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec4 c0 = texture(iChannel0, uv);
    float L = smearLen(uv, asp) * mix(0.05, 1.0, c0.a);

    // Bristles: the brush is a comb of bristle lines (1-4 px wide) across
    // the drag. Each bristle picks its paint up at its own hashed distance
    // upstream (load point b) and drags it down to here, so neighbouring
    // lines carry different colours: a dry-brush striation, not a blur.
    // The comb follows the stream function, in the fixed-angle zones it runs
    // straight at the zone angle, in the burst vertically. The switch between
    // comb orientations is dithered so there is no sheared seam.
    float wz;
    float az = zoneAngle(uv, wz);
    float dith = hash12(fragCoord * 0.731);
    float lc = dith < burstW(uv) ? fragCoord.x
             : dith < wz ? dot(fragCoord, vec2(-sin(az), cos(az)))
             : psi(fragCoord);
    lc += 6.0 * noise(vec2(lc * 0.02, dot(fragCoord, ALONG) * 0.004));
    float wb = 2.0 + 7.0 * hash11(floor(lc / 24.0) + 0.5);
    float id = floor(lc / wb);
    vec3 hb = hash33(vec3(id, wb, 7.0));
    float b = hb.x;                                       // load point 0..1
    L *= mix(0.3, 1.4, hb.y) * (1.0 + 0.3 * sin(iTime * 0.3 + hb.z * 6.28));

    vec3 acc = c0.rgb * 0.6;
    float wsum = 0.6;
    vec2 pos = fragCoord;
    float stp = L / float(TAPS);
    for (int i = 1; i <= TAPS; i++) {
        pos -= flowDir(pos / res) * stp;                  // walk upstream
        float t = float(i) / float(TAPS);
        vec4 s = texture(iChannel0, pos / res);
        // trail (fades upstream) + the bristle's load window around b
        float w = 0.25 * pow(max(1.0 - t, 1e-3), 1.3) + exp(-pow((t - b) / 0.08, 2.0));
        w *= mix(0.03, 1.0, s.a * s.a);                  // dry paint is not picked up
        acc += s.rgb * w;
        wsum += w;
    }
    // dry paint (leaves, flakes) keeps its own colour: it was not dragged
    return mix(acc / wsum, c0.rgb, smoothstep(0.6, 0.85, 1.0 - c0.a));
}

// ---- C: crisp marks ----------------------------------------------------------
// Jittered-grid dots stretched along the drag; coverage + per-dot hash.
float dots(vec2 p, float cell, float density, float rmin, float rmax, vec2 stretch, float seed, out vec3 hh) {
    vec2 g = floor(p / cell);
    float cov = 0.0;
    hh = vec3(0.0);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 gg = g + vec2(i, j);
            vec3 h = hash33(vec3(gg, seed));
            if (h.z > density) continue;
            vec2 c = (gg + 0.15 + 0.7 * h.xy) * cell;
            float r = cell * mix(rmin, rmax, pow(hash12(gg + seed), 3.0));
            vec2 d = p - c;
            d = rot(0.5 * (h.y - 0.5)) * vec2(dot(d, ALONG), dot(d, ACROSS));  // +-15 deg
            d /= mix(vec2(1.0), stretch, h.x * h.x * h.x);   // few are elongated
            // sky flakes (seed <= 2) are half chipped squares, the rest round
            vec2 q = rot(h.z * 40.0) * d;
            float e = mix(length(d), max(abs(q.x), abs(q.y)) * 1.1, step(0.6, fract(h.z * 17.0)) * step(seed, 2.5));   // sky only
            e += 0.45 * r * (noise(d / r * 2.5 + h.xy * 9.0) - 0.5);
            float a = 1.0 - smoothstep(r * 0.8, r, e);
            if (a > cov) { cov = a; hh = h; }
        }
    return cov;
}

// Thin shards thrown out of the burst: each points away from the burst
// centre (+-30 deg), aspect 3-6, jagged.
float shards(vec2 p, float cell, float density, vec2 centre, float seed, out vec3 hh) {
    vec2 g = floor(p / cell);
    float cov = 0.0;
    hh = vec3(0.0);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 gg = g + vec2(i, j);
            vec3 h = hash33(vec3(gg, seed));
            if (h.z > density) continue;
            vec2 c = (gg + 0.2 + 0.6 * h.xy) * cell;
            vec2 r = normalize(c - centre + 1e-4);
            r = rot(1.0 * (h.x - 0.5)) * r;
            vec2 d = p - c;
            d = vec2(dot(d, r), dot(d, vec2(-r.y, r.x)));
            float len = cell * mix(0.08, 0.5, pow(hash12(gg + seed), 2.0));
            float wid = len * mix(0.15, 0.35, h.y);
            float t = clamp(d.x / len, -1.0, 1.0);
            float e = abs(d.y) / (wid * (1.0 - t * t) + 1e-4) + 0.8 * (noise(d / wid * 0.8 + h.xy * 7.0) - 0.5);
            float a = (1.0 - smoothstep(0.7, 1.0, e)) * step(abs(d.x), len);
            if (a > cov) { cov = a; hh = h; }
        }
    return cov;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float asp = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * asp, uv.y);

#ifdef SHOW_PAINT
    fragColor = vec4(linearToSrgb(texture(iChannel0, uv).rgb), 1.0);
    return;
#endif
#ifdef SHOW_LEN
    fragColor = vec4(vec3(smearLen(uv, asp) / 150.0), 1.0);
    return;
#endif

    // S: the smear
    vec3 col = smear(fragCoord, asp);
#ifdef ONLY_SMEAR
    fragColor = vec4(linearToSrgb(col), 1.0);
    return;
#endif

    float td = tearDist(uv, asp);
    float sky = 1.0 - smoothstep(-0.08, 0.02, td);
    float warm = smoothstep(0.15, 0.30, td);
    vec3 h;

    // C1: pink sky specks (round) and a few bigger irregular flakes
    float s1 = dots(p, 0.024, 0.14, 0.05, 0.20, vec2(1.0), 1.0, h) * sky;
    col = mix(col, mix(hexColor(0xe060b0), hexColor(0xf090c8), h.x), s1);
    float s2 = dots(p, 0.10, 0.12, 0.08, 0.20, vec2(1.0, 0.8), 2.0, h) * sky;
    col = mix(col, mix(hexColor(0xe064a8), hexColor(0xf0a0cc), h.y), s2);
    // fine dust in the sky near the burst
    float s0 = dots(p, 0.008, 0.25, 0.08, 0.16, vec2(1.0), 6.0, h) * sky * win(uv, vec4(0.22, 0.5, 0.55, 1.1), 0.08);
    col = mix(col, hexColor(0xc0508a), 0.7 * s0);

    // C2: orange sparks in the burst
    float burst = win(uv, vec4(0.28, 0.52, 0.60, 1.05), 0.05);
    float s3 = dots(p, 0.014, 0.40, 0.06, 0.22, vec2(1.3, 0.8), 3.0, h) * burst;
    col = mix(col, mix(hexColor(0xe8602e), hexColor(0xffa060), h.y), s3);
    // dense spark cloud: tiny orange / pink dots
    float s8 = dots(p, 0.006, 0.45, 0.10, 0.22, vec2(1.0), 9.0, h) * win(uv, vec4(0.24, 0.55, 0.56, 1.05), 0.06);
    col = mix(col, h.x > 0.4 ? mix(hexColor(0xf07a3a), hexColor(0xffb070), h.y) : hexColor(0xf070b0), 0.9 * s8);
    vec2 bc = vec2(0.46 * asp, 0.80);
    float s6 = shards(p, 0.022, 0.30, bc, 7.0, h) * win(uv, vec4(0.20, 0.45, 0.52, 1.05), 0.06);
    col = mix(col, h.y > 0.4 ? mix(hexColor(0xd84a20), hexColor(0xf59050), h.x)
                             : mix(hexColor(0x7a40c0), hexColor(0xc070d0), h.x), s6);

    // C3: navy / violet ink specks on the warm side, some elongated at 35 deg
    float inkZone = warm * (1.0 - 0.7 * win(uv, vec4(0.85, 0.80, 1.1, 1.1), 0.05));
    float s4 = dots(p, 0.016, 0.45, 0.06, 0.22, vec2(1.8, 0.9), 4.0, h) * inkZone;
    col = mix(col, mix(hexColor(0x1a1040), hexColor(0x3a1e70), h.y), 0.9 * s4);
    float s5 = dots(p, 0.07, 0.18, 0.08, 0.22, vec2(1.2, 1.0), 5.0, h) * inkZone;
    col = mix(col, hexColor(0x241038), 0.9 * s5);

    // C4: crisp round specks over the dragged tear / dry-brush paint
    float dz = smoothstep(0.0, 0.06, td) * (1.0 - warm) + 0.6 * win(uv, vec4(0.3, -0.1, 0.75, 0.4), 0.08);
    dz *= 1.0 - burst;
    float s7 = dots(p, 0.012, 0.35, 0.06, 0.25, vec2(1.0), 8.0, h) * min(dz, 1.0);
    col = mix(col, h.y > 0.3 ? mix(hexColor(0x1c1048), hexColor(0x3a1a6a), h.x) : hexColor(0xe060b8), 0.85 * s7);

    // G: film grain
    col *= 1.0 + 0.10 * (1.0 - 0.6 * sky) * (hash12(fragCoord + 0.37) - 0.5);
    fragColor = vec4(linearToSrgb(col * EXPOSURE), 1.0);
}
