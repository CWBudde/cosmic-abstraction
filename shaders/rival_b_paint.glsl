// rival_b_paint.glsl - Buffer A of Rival B ("directional smear").
//
// Paints the crisp PRE-SMEAR picture: what the canvas looked like the moment
// the paint landed, before it was dragged. The Image pass (rival_b.glsl)
// smears this buffer along the flow field, so most marks here are simple
// round-ish splats; their streaks come from the smear.
//
// Layers (bottom to top), all in linear RGB:
//   P0 wash     soft colour field: 45-anchor Gaussian blend adapted from
//               Rival A (colourFieldA), lookup jittered by noise.
//               -D WASH_B=1 uses the older 36-anchor wash instead.
//   P1 tear     violet lumps along the tear, torn-edge navy lumps, blue lumps
//               in the lower left, dense dark-violet splats in
//               the tear and the dry-brush zone (the smear turns them into
//               the 35 deg dry-brush streaks)
//   P2 burst    torn Voronoi chunks, orange splatter (thresholded fbm), vertical
//               strokes, the violet smudge and drip, the two leaf chunks
//   P2b warm    coral / magenta lumps, violet streaks above the chain,
//               dark violet blobs at the lower right
//   P2c blotch  balanced coral / deep-magenta blotches in the upper warm half
//   P3 ink      the authored dark slash chain with violet halo, blobs, the
//               dark top-right wedge, the pale flake at the top edge
//   P4 grain    per-pixel value grain (the LIC turns it into fibres)
// Alpha carries the per-pixel "wetness" (0 = resists the drag, 1 = full).

#include "rival_b_common.glsl"

// ---- P0: colour anchors (uv, sRGB hex) ----------------------------------
const int NA = 36;
const vec2 AP[NA] = vec2[NA](
    // night sky
    vec2(0.04, 0.92), vec2(0.12, 0.70), vec2(0.05, 0.45),
    vec2(0.06, 0.20), vec2(0.02, 0.03), vec2(0.14, 0.06),
    vec2(0.22, 0.90), vec2(0.30, 0.72), vec2(0.22, 0.48),
    // violet tear
    vec2(0.38, 0.50), vec2(0.42, 0.30), vec2(0.33, 0.12),
    vec2(0.50, 0.10), vec2(0.50, 0.42), vec2(0.28, 0.28),
    vec2(0.40, 0.90),
    // burst
    vec2(0.52, 0.68), vec2(0.52, 0.90), vec2(0.63, 0.82),
    // warm side
    vec2(0.76, 0.94), vec2(0.94, 0.90), vec2(0.80, 0.70),
    vec2(0.93, 0.60), vec2(0.66, 0.56), vec2(0.72, 0.40),
    vec2(0.92, 0.42), vec2(0.76, 0.26), vec2(0.92, 0.24),
    vec2(0.66, 0.16), vec2(0.86, 0.05), vec2(0.24, 0.12),
    vec2(0.12, 0.30), vec2(0.11, 0.12), vec2(0.98, 0.04), vec2(0.60, 0.95),
    vec2(0.41, 0.72)
);
const int AC[NA] = int[NA](
    0x100c34, 0x100d38, 0x0e0d3a,
    0x0b0d42, 0x0a1470, 0x181878,
    0x24123e, 0x241242, 0x150f44,
    0x5a2276, 0x8a3f95, 0x6a3c9c,
    0x9a58ac, 0x8a2c88, 0x341870,
    0x3a1650,
    0xc8325a, 0x80266a, 0xc23052,
    0xa02470, 0xdc4a70, 0xe6465c,
    0xf0566a, 0xd84874, 0xe85c80,
    0xee6488, 0xe878a8, 0xbc62a8,
    0xb86cb0, 0x8a46a0, 0x34228e,
    0x0e0e48, 0x14125e, 0x6a3088, 0xc8304e,
    0x2e1040
);

vec3 wash(vec2 uv) {
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < NA; i++) {
        vec2 d = (uv - AP[i]) * vec2(1.6, 1.0);
        float w = exp(-dot(d, d) / (2.0 * 0.10 * 0.10));
        acc += w * hexColor(AC[i]);
        wsum += w;
    }
    return acc / max(wsum, 1e-5);
}

// P0 alternative: 45-anchor colour field adapted from Rival A
// (rival_a.glsl colourField). p = aspect-corrected position (y / height),
// anchors given in reference pixels (y down), radius in p units.
vec2 R(float x, float y) { return vec2(x, 816.0 - y) / 816.0; }
vec3 colourFieldA(vec2 p) {
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
#define ANCHOR(x, y, hx, r) { vec2 d = p - R(x, y); float w = exp(-dot(d, d) / (r * r)); acc += w * hexColor(hx); wsum += w; }
    // night sky
    ANCHOR(  60.0,  80.0, 0x0a0d38, 0.30)
    ANCHOR( 250.0, 120.0, 0x120e3c, 0.22)
    ANCHOR(  60.0, 420.0, 0x040b32, 0.25)
    ANCHOR( 300.0, 380.0, 0x060b38, 0.20)
    ANCHOR(  40.0, 790.0, 0x08115e, 0.18)
    ANCHOR( 200.0, 740.0, 0x10125e, 0.16)
    ANCHOR( 450.0, 100.0, 0x1a0c38, 0.14)
    ANCHOR( 560.0, 300.0, 0x220e46, 0.12)
    ANCHOR( 670.0,  70.0, 0x4a1450, 0.09)
    ANCHOR( 650.0, 320.0, 0x3c1462, 0.09)
    ANCHOR( 480.0, 470.0, 0x1c1050, 0.10)
    // tear band, violet
    ANCHOR( 420.0, 780.0, 0x4a2c95, 0.14)
    ANCHOR( 600.0, 770.0, 0x7a46a6, 0.14)
    ANCHOR( 560.0, 650.0, 0x4e2690, 0.12)
    ANCHOR( 680.0, 520.0, 0x8c3294, 0.12)
    ANCHOR( 760.0, 420.0, 0xa02c8e, 0.12)
    ANCHOR( 800.0, 650.0, 0x9a55aa, 0.13)
    ANCHOR( 900.0, 760.0, 0x9558aa, 0.13)
    // warm side
    ANCHOR( 800.0, 240.0, 0xc42a5c, 0.10)
    ANCHOR( 990.0,  70.0, 0xd8304f, 0.12)
    ANCHOR( 790.0,  50.0, 0x501458, 0.07)
    ANCHOR(1100.0, 100.0, 0x8a1660, 0.11)
    ANCHOR(1030.0, 150.0, 0x4a0c58, 0.08)
    ANCHOR(1045.0, 265.0, 0xb02060, 0.05)
    ANCHOR( 900.0, 300.0, 0xe83a6a, 0.05)
    ANCHOR( 545.0, 385.0, 0x4a1a6a, 0.06)
    ANCHOR(1265.0, 130.0, 0x8a1a64, 0.06)
    ANCHOR(1275.0,  40.0, 0x8a1a6a, 0.06)
    ANCHOR(1380.0,  60.0, 0xe03a62, 0.13)
    ANCHOR(1380.0, 230.0, 0xf25562, 0.14)
    ANCHOR(1150.0, 300.0, 0xec4864, 0.13)
    ANCHOR( 950.0, 330.0, 0xd83866, 0.12)
    ANCHOR(1420.0, 400.0, 0xf06a84, 0.12)
    ANCHOR(1150.0, 470.0, 0xee5a78, 0.13)
    ANCHOR( 990.0, 520.0, 0xe06a9e, 0.10)
    ANCHOR( 880.0, 460.0, 0xa42b89, 0.07)
    ANCHOR( 870.0, 570.0, 0xb04ca0, 0.07)
    ANCHOR(1100.0, 600.0, 0xe276ad, 0.12)
    ANCHOR(1380.0, 600.0, 0xd072b0, 0.13)
    ANCHOR(1200.0, 720.0, 0xd474b2, 0.12)
    ANCHOR(1400.0, 790.0, 0x5a2888, 0.10)
    ANCHOR(1445.0, 730.0, 0x6a3090, 0.07)
    ANCHOR(1050.0, 800.0, 0x9a4ea2, 0.10)
    ANCHOR(1170.0, 780.0, 0x9a50a2, 0.10)
    ANCHOR(1300.0, 770.0, 0x8a409a, 0.10)
#undef ANCHOR
    return acc / max(wsum, 1e-6);
}

// P3 slash chain: segment ends (uv) and widths (aspect units) at both ends.
const vec2 SLA[5] = vec2[5](vec2(0.556, 0.540), vec2(0.600, 0.585), vec2(0.665, 0.700), vec2(0.760, 0.840), vec2(0.590, 0.700));
const vec2 SLB[5] = vec2[5](vec2(0.620, 0.600), vec2(0.690, 0.690), vec2(0.780, 0.860), vec2(0.835, 0.960), vec2(0.750, 0.930));
const vec2 SLW[5] = vec2[5](vec2(0.003, 0.006), vec2(0.006, 0.010), vec2(0.010, 0.014), vec2(0.008, 0.003), vec2(0.002, 0.003));

// Voronoi: x = distance to the nearest seed, yz = its cell id.
vec3 voronoi(vec2 p) {
    vec2 g = floor(p);
    vec2 f = fract(p);
    float best = 8.0;
    vec2 id = vec2(0.0);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 o = vec2(i, j);
            vec2 r = o + hash22(g + o) - f;
            float d = dot(r, r);
            if (d < best) { best = d; id = g + o; }
        }
    return vec3(sqrt(best), id);
}

// Jittered-grid round splats: coverage of the nearest splat, id in h.
float splats(vec2 p, float cell, float density, float rmin, float rmax, float seed, out vec3 hh) {
    vec2 g = floor(p / cell);
    float cov = 0.0;
    hh = vec3(0.0);
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 gg = g + vec2(i, j);
            vec3 h = hash33(vec3(gg, seed));
            if (h.z > density) continue;
            vec2 c = (gg + 0.15 + 0.7 * h.xy) * cell;
            float r = cell * mix(rmin, rmax, pow(hash12(gg + seed * 7.0), 2.5));
            vec2 d = p - c;
            float e = length(d) + 0.35 * r * (noise(d / r * 1.7 + h.xy * 13.0) - 0.5);
            float a = 1.0 - smoothstep(r * 0.8, r, e);
            if (a > cov) { cov = a; hh = h; }
        }
    return cov;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float asp = iResolution.x / iResolution.y;
    vec2 p = vec2(uv.x * asp, uv.y);
    float al = dot(p, ALONG);
    float ac = dot(p, ACROSS);
    float td = tearDist(uv, asp);           // 0 on the sky edge, + to the warm side
    vec3 h;

    // P0: wash, looked up through a streak-shaped jitter.
    vec2 jit = vec2(fbm(vec2(al * 2.0, ac * 14.0), 4), fbm(vec2(al * 2.0 + 7.0, ac * 14.0), 4)) - 0.5;
#ifdef WASH_B
    vec3 col = wash(uv + 0.05 * jit);
#else
    vec3 col = colourFieldA(p + 0.05 * jit * vec2(asp, 1.0));
#endif
    float wet = 1.0;

    // P1: violet lumps inside the tear band.
    float band = smoothstep(-0.04, 0.04, td) * (1.0 - smoothstep(0.30, 0.45, td));
    {
        float n = fbm(vec2(al * 5.0, ac * 18.0) + 3.1, 5);
        float m = smoothstep(0.58, 0.62, n) * band;
        float k = fbm(p * 9.0 + 11.0, 3);
        vec3 vio = mix(hexColor(0x5b2689), hexColor(0xaf5bac), smoothstep(0.35, 0.7, k));
        col = mix(col, vio, 0.7 * m);
    }
    // torn edge: dark navy and blue-violet lumps where the sky tears open
    {
        float edge = smoothstep(-0.08, 0.0, td) * (1.0 - smoothstep(0.12, 0.22, td));
        float n = fbm(vec2(al * 9.0, ac * 30.0) + 17.0, 4);
        float k = fbm(vec2(al * 7.0, ac * 26.0) + 29.0, 4);
        col = mix(col, mix(hexColor(0x0c0a32), hexColor(0x1a1258), k), 0.9 * edge * smoothstep(0.55, 0.6, n));
        col = mix(col, mix(hexColor(0x3a2a9a), hexColor(0x6a3ab0), n), 0.8 * edge * smoothstep(0.58, 0.62, k));
    }
    // lower-left: saturated blue lumps the drag pulls into blue streaks
    {
        float bz = win(uv, vec4(-0.1, -0.1, 0.36, 0.30), 0.06);
        float n = fbm(vec2(al * 8.0, ac * 34.0) + 5.0, 4);
        col = mix(col, mix(hexColor(0x101060), hexColor(0x26248e), fbm(p * 20.0, 2)), 0.5 * bz * smoothstep(0.55, 0.6, n));
    }
    // dark violet splats, dense in the tear and the dry-brush zone
    {
        float dry = max(band, win(uv, vec4(0.30, -0.1, 0.80, 0.42), 0.08));
        dry *= 1.0 - win(uv, vec4(0.25, 0.60, 0.60, 1.1), 0.05);
        float s = splats(p, 0.016, 0.55, 0.10, 0.32, 31.0, h) * dry;
        vec3 dc = mix(hexColor(0x1c0c48), hexColor(0x3a1868), h.x);
        col = mix(col, dc, 0.9 * s);
        // bigger dark lumps: they survive the drag as the long dark streaks
        s = splats(vec2(dot(p, ALONG), dot(p, ACROSS) * 2.0), 0.035, 0.6, 0.12, 0.40, 33.0, h) * dry;
        col = mix(col, mix(hexColor(0x140a3a), hexColor(0x2a1050), h.x), 0.95 * s);
        // magenta lumps in the lower middle
        s = splats(p, 0.05, 0.4, 0.15, 0.40, 34.0, h) * dry * win(uv, vec4(0.38, 0.0, 0.62, 0.45), 0.08);
        col = mix(col, mix(hexColor(0x871a62), hexColor(0xc82c66), h.y), 0.8 * s);
        // lighter lilac splats too, so the drag also leaves pale streaks
        float s2 = splats(p, 0.03, 0.25, 0.10, 0.30, 32.0, h) * dry;
        col = mix(col, hexColor(0xb27ad0), 0.5 * s2);
    }

    // P2: burst.
    float burstW = win(uv, vec4(0.28, 0.50, 0.62, 1.05), 0.06);
    {
        // orange splatter: thresholded high-frequency fbm under a patchy mask
        // the hot core (u 0.45-0.6) gets an orange-red wash and most of the
        // splatter; the dark left part of the burst only a little
        float hot = win(uv, vec4(0.48, 0.58, 0.66, 0.90), 0.05);
        float hw = hot * smoothstep(0.35, 0.6, fbm(vec2(al * 6.0, ac * 3.0) + 9.0, 4));
        col = mix(col, mix(hexColor(0xc8283e), hexColor(0xe85a3a), fbm(p * 8.0, 3)), 0.6 * hw);
        float mask = max(hot, 0.3 * burstW) * smoothstep(0.35, 0.65, fbm(p * 5.0 + 4.0, 3));
        float n = fbm(p * 70.0 + 1.3, 4);
        float sp = smoothstep(0.68, 0.70, n + 0.10 * mask) * mask;
        vec3 orange = mix(hexColor(0xd8481e), hexColor(0xf59050), fbm(p * 20.0, 2));
        col = mix(col, orange, sp);
        wet = mix(wet, 0.12, sp);

        // thrown streaks: short vertical strokes of violet and orange; the
        // vertical smear in the burst draws them out further
        {
            float cw = 0.006;
            float cx = floor(uv.x / cw);
            float seg = floor(uv.y / 0.05 + hash11(cx) * 3.0);
            vec3 hv = hash33(vec3(cx, seg, 61.0));
            float x0 = (cx + 0.5 + 0.4 * (hv.x - 0.5)) * cw;
            float wv = 0.0006 + 0.0016 * hv.y;
            float lv = fract(uv.y / 0.05 + hash11(cx) * 3.0);
            float sv = (1.0 - smoothstep(wv, wv * 1.6, abs(uv.x - x0))) * smoothstep(0.0, 0.2, lv) * smoothstep(1.0, 0.5, lv);
            sv *= step(hv.z, 0.15) * burstW * smoothstep(0.30, 0.38, uv.x);
            col = mix(col, hv.x > 0.5 ? hexColor(0x8a4ad8) : hexColor(0xf07a3a), 0.85 * sv);
        }

        // orange flakes: small splats, also at the tear
        float fz = max(0.5 * burstW, 0.2 * exp(-pow(td / 0.08, 2.0)) * step(uv.y, 0.7));
        vec2 pw = p + 0.006 * (vec2(fbm(p * 160.0, 3), fbm(p * 160.0 + 3.7, 3)) - 0.5);   // torn edges
        float f = splats(pw, 0.02, 0.25, 0.10, 0.45, 41.0, h);
        f *= step(fract(h.z * 13.0), 1.4 * fz);           // fz thins them out, full opacity
        col = mix(col, mix(hexColor(0xe8602e), hexColor(0xffa060), h.y), f);
        wet = mix(wet, 0.12, f);

        // torn chunks: ragged Voronoi cells, orange and violet, densest in
        // the hot core; partly wet, so the vertical burst drag gives tails
        {
            float core = win(uv, vec4(0.43, 0.60, 0.56, 0.97), 0.04);
            vec2 q = rot(0.3) * p * 22.0;
            vec3 v = voronoi(q);
            vec3 hc = hash33(vec3(v.yz, 5.0));
            float rag = fbm(p * 110.0 + hc.xy * 7.0, 3);
            float size = 0.10 + 0.22 * hc.y;
            float chunk = 1.0 - smoothstep(size - 0.03, size, v.x + 0.35 * (rag - 0.5));
            float keep = step(hc.x, 0.45 * core + 0.06 * burstW);
            vec3 cc = hc.z > 0.35 ? mix(hexColor(0xe0502a), hexColor(0xf59a52), fract(hc.z * 7.0))
                                  : mix(hexColor(0x6a30a8), hexColor(0xa060c8), fract(hc.z * 7.0));
            col = mix(col, cc, keep * chunk);
            wet = mix(wet, 0.12, keep * chunk);
        }

        // big violet smudge at the very top (u ~ 0.5)
        vec2 d = (uv - vec2(0.497, 0.94)) * vec2(asp, 1.0);
        float e = length(d / vec2(0.045, 0.10)) + 0.5 * (fbm(d * 30.0, 3) - 0.5);
        float vs = 1.0 - smoothstep(0.85, 1.0, e);
        col = mix(col, mix(hexColor(0x5a2ca0), hexColor(0x8a52c8), fbm(d * 50.0, 3)), vs);

        // violet drip curving down at u ~ 0.32
        float x = 0.335 - 0.04 * (uv.y - 0.62) / 0.3 + 0.006 * sin(uv.y * 30.0);
        float drip = (1.0 - smoothstep(0.0025, 0.004, abs(uv.x - x)))
                   * smoothstep(0.60, 0.64, uv.y) * (1.0 - smoothstep(0.82, 0.88, uv.y));
        col = mix(col, hexColor(0x7a3ac0), 0.9 * drip);

        // big orange leaf chunks near u 0.47-0.55, v 0.33
        for (int i = 0; i < 2; i++) {
            vec2 c = i == 0 ? vec2(0.472, 0.36) : vec2(0.545, 0.345);
            vec2 dd = (uv - c) * vec2(asp, 1.0);
            dd = rot(-0.75) * dd;
            // teardrop: blunt at the lower end, a pointed tip up the drag
            float tip = smoothstep(-0.05, 0.05, dd.y);
            float ee = length(dd / vec2(mix(0.026, 0.012, tip), 0.05)) + 0.4 * (fbm(dd * 80.0 + float(i), 3) - 0.5);
            float leaf = 1.0 - smoothstep(0.9, 1.0, ee);
            col = mix(col, mix(hexColor(0xf06a38), hexColor(0xf5b080), smoothstep(-0.01, 0.03, dd.x)), leaf);
            wet = mix(wet, 0.1, leaf);
        }
    }

    // P2c: soft blotches on the warm side. Balanced around the wash colour
    // (one side of the noise pulls to deep magenta, the other to coral;
    // upper warm half only), so the local mean stays put but the field is not flat.
    {
        float warmZ = smoothstep(0.25, 0.40, td);
        float t = fbm(vec2(dot(p, ALONG) * 9.0, dot(p, ACROSS) * 16.0) + 71.0, 4) - 0.5;
        float k = warmZ * smoothstep(0.03, 0.15, abs(t)) * smoothstep(0.38, 0.55, uv.y);
        col = mix(col, t > 0.0 ? hexColor(0xf26a50) : hexColor(0xa01e5e), 0.35 * k);  // coral / magenta
    }

    // P2b: warm-side lumps: coral-orange and deep-magenta paint in the
    // upper right, violet streak lumps above the slash chain, two big dark
    // violet blobs low on the right
    {
        float wz = smoothstep(0.30, 0.45, td) * smoothstep(0.55, 0.75, uv.y);
        float n1 = fbm(vec2(al * 7.0, ac * 22.0) + 21.0, 4);
        col = mix(col, mix(hexColor(0xec4c50), hexColor(0xf26a4a), fbm(p * 15.0, 2)), 0.6 * wz * smoothstep(0.58, 0.62, n1));
        float n2 = fbm(vec2(al * 6.0, ac * 30.0) + 41.0, 4);
        col = mix(col, mix(hexColor(0xc82c66), hexColor(0x871a62), fbm(p * 11.0, 2)), 0.8 * wz * smoothstep(0.62, 0.66, n2));
        float vz = win(uv, vec4(0.55, 0.62, 0.80, 1.02), 0.05) * smoothstep(-0.02, 0.04, dot((uv - vec2(0.556, 0.54)) * vec2(asp, 1.0), vec2(-0.64, 0.77)));
        float n3 = fbm(vec2(al * 5.0, ac * 35.0) + 61.0, 4);
        col = mix(col, mix(hexColor(0x5b2689), hexColor(0xaf5bac), fbm(p * 13.0, 2)), 0.75 * vz * smoothstep(0.55, 0.6, n3));
        for (int i = 0; i < 2; i++) {
            vec2 c = i == 0 ? vec2(0.793, 0.17) : vec2(0.985, 0.14);
            vec2 d = rot(-0.3) * ((uv - c) * vec2(asp, 1.0));
            float e = length(d / (i == 0 ? vec2(0.016, 0.04) : vec2(0.03, 0.05))) + 0.35 * (fbm(d * 50.0 + float(i), 3) - 0.5);
            float blob = 1.0 - smoothstep(0.85, 1.0, e);
            col = mix(col, mix(hexColor(0x3a1250), hexColor(0x6a1a5a), smoothstep(-0.02, 0.02, d.x)), blob);
            wet = mix(wet, 0.2, blob);
        }
    }

    // P3: the dark slash chain (uv 0.56,0.54 -> 0.83,0.96) with its violet
    // halo, a thinner parallel slash, two dark blobs, the dark top-right wedge
    // and the pale flake at the top edge. The smear drags them out.
    {
        float halo = 0.0, ink = 0.0;
        for (int i = 0; i < 5; i++) {
            vec2 a = SLA[i], b = SLB[i];
            vec2 w = SLW[i];
            vec2 pa = (uv - a) * vec2(asp, 1.0), ba = (b - a) * vec2(asp, 1.0);
            float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            float d = length(pa - ba * t);
            float wt = mix(w.x, w.y, t) * (0.6 + 0.8 * fbm(vec2(t * 18.0, float(i) * 3.1), 3));
            d += 0.004 * (fbm(p * 90.0, 3) - 0.5);
            ink = max(ink, 1.0 - smoothstep(wt * 0.8, wt, d));
            halo = max(halo, 1.0 - smoothstep(wt * 1.5, wt * 4.0, d));
        }
        // blobs
        vec2 bd = rot(-0.7) * ((uv - vec2(0.718, 0.69)) * vec2(asp, 1.0));
        ink = max(ink, 1.0 - smoothstep(0.8, 1.0, length(bd / vec2(0.022, 0.009))));
        vec2 bd2 = rot(-0.7) * ((uv - vec2(0.655, 0.61)) * vec2(asp, 1.0));
        float blue = 1.0 - smoothstep(0.75, 1.0, length(bd2 / vec2(0.03, 0.016)) + 0.3 * (fbm(bd2 * 60.0, 3) - 0.5));

        halo *= smoothstep(0.4, 0.6, fbm(vec2(al * 12.0, ac * 40.0), 3) + 0.15);
        col = mix(col, mix(hexColor(0x5b2689), hexColor(0x8b3d9c), fbm(p * 30.0, 2)), 0.65 * halo);
        col = mix(col, hexColor(0x3a2a9a), 0.9 * blue);
        col = mix(col, mix(hexColor(0x0e0624), hexColor(0x200a38), fbm(p * 40.0, 2)), 0.95 * ink);
        wet = mix(wet, 0.55, max(ink, blue));

        // dark wedge top right
        vec2 wc = (uv - vec2(0.865, 0.88)) * vec2(asp, 1.0);
        float wd = abs(dot(wc, ACROSS)) / 0.05 + abs(dot(wc, ALONG)) / 0.12;
        float wedge = 1.0 - smoothstep(0.7, 1.0, wd + 0.5 * (fbm(p * 14.0, 3) - 0.5));
        col = mix(col, hexColor(0x4a1440), 0.85 * wedge);

        // pale flake at the top edge
        vec2 fc = (uv - vec2(0.90, 0.985)) * vec2(asp, 1.0);
        float flake = 1.0 - smoothstep(0.85, 1.0, length(rot(0.2) * fc / vec2(0.05, 0.02)) + 0.3 * (fbm(fc * 70.0, 3) - 0.5));
        col = mix(col, hexColor(0xf4b8d8), flake);
        wet = mix(wet, 0.1, flake);
    }

    // P3b: vertical drips (pale on the warm side, violet in the burst); the
    // smear stretches them further downward
    {
        float cw = 0.012;
        float cx = floor(uv.x / cw);
        vec3 hd = hash33(vec3(cx, 3.0, 51.0));
        float dz = max(win(uv, vec4(0.62, 0.0, 0.95, 0.45), 0.03), win(uv, vec4(0.28, 0.55, 0.50, 1.0), 0.03));
        float x0 = (cx + 0.2 + 0.6 * hd.x) * cw;
        float top = mix(0.15, 0.45, hd.y) + (uv.x > 0.5 ? 0.0 : 0.5);
        float wdt = 0.0008 + 0.0015 * hd.z;
        float drip = (1.0 - smoothstep(wdt, wdt * 1.8, abs(uv.x - x0)))
                   * smoothstep(top, top - 0.03, uv.y) * smoothstep(top - 0.35, top - 0.15, uv.y);
        drip *= step(hd.z, 0.35) * dz;
        vec3 dc = uv.x > 0.5 ? hexColor(0xf08ac0) : hexColor(0x8a4ad0);
        col = mix(col, dc, 0.35 * drip);
    }

    // P4: grain, strongest where the smear is long, so it becomes fibres.
    float gr = hash12(floor(fragCoord * 0.7)) - 0.5;
    col *= 1.0 + 0.5 * gr * (1.0 - 0.6 * smoothstep(0.0, -0.1, td));

    fragColor = vec4(col, wet);
}
