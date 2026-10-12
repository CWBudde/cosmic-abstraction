// paint.glsl - the wet background before the bristle drag, in LINEAR colour.
//
// Everything here is paint that smear.glsl drags along the tear: background()
// is evaluated at the pixel and, where the drag is wet, once more upstream.
// Layers, back to front:
//   L0  colour field   normalised Gaussian blend of ~50 hand-placed anchors
//   L1  soft washes    burst glow, torn orange flame masses, hazes
//   L1d coral front    sharp, drippy coral/pink front on the right (y ~ 500)
//   L1b warm brush     soft long 52 deg strokes modulating the warm paint
//   L1c mottle         soft medium blotches that dirty the warm paint
//   L2  dry brush      soft blue sky smears low left, navy teardrop dashes in
//                      the lower band, 35 deg hair lines + dashes
//                      along the tear (steered to ~50 deg top right)
//   L2b smudges        35 deg violet/magenta/ink smears in the tear band
//   L2c tear chunks    mid-size torn violet/magenta flakes along the tear

#include "common.glsl"
#include "field.glsl"

// ---- L1: soft washes ---------------------------------------------------------------
void softWashes(inout vec3 col, vec2 p) {
    over(col, hexColor(0xe0583a), 0.30 * fill(sdBlob(p, R(770.0, 200.0), vec2(0.05, 0.10), 1.35, 0.8, 7.0), 0.04));
    // torn orange flame mass on the burst's right flank
    float fl = sdEllipse(rot(-1.32) * (p - R(772.0, 215.0)), vec2(0.14, 0.035));
    paintA(col, hexColor(0xf06a30), 0.75 * fill(torn(fl, p, 70.0, 0.03), PX * 2.0), p, 0.5, 0.5, 1.32);
    float fl2 = sdEllipse(rot(-1.45) * (p - R(735.0, 300.0)), vec2(0.07, 0.016));
    paintA(col, hexColor(0xe85a30), 0.45 * fill(torn(fl2, p, 90.0, 0.015), PX * 2.0), p, 0.6, 0.5, 1.45);
    // magenta haze near the burst right side
    over(col, hexColor(0xb02a7a), 0.4 * fill(sdBlob(p, R(780.0, 330.0), vec2(0.05, 0.10), 0.9, 0.7, 11.0), 0.05));
    // pink haze lower middle
    over(col, hexColor(0xc0609e), 0.35 * fill(sdBlob(p, R(900.0, 560.0), vec2(0.07, 0.16), 0.61, 0.7, 5.0), 0.06));
}

// ---- L1d: coral front -- on the right the coral runs down into the pink along
// a near-horizontal front (y ~ 500 px) with a ragged, drippy lower edge. The
// field is sampled above and below the front so the transition gets sharp.
vec3 coralFront(vec3 col, vec2 p) {
    if (p.x < 1.2 || p.y < 0.2 || p.y > 0.5) return col;
    float x = p.x * 816.0;
    float yf = 495.0 + 18.0 * (noise(vec2(x * 0.01, 1.0)) - 0.5)
             + 45.0 * pow(noise(vec2(x * 0.06, 3.0)), 4.0);        // drips hang down
    float yPx = 816.0 - p.y * 816.0;
    float m = smoothstep(yf - 45.0, yf + 45.0, yPx);
    vec3 above = colourField(p + vec2(0.0, 0.07));
    vec3 below = colourField(p - vec2(0.0, 0.07));
    // fade out well inside the early-out box, so it leaves no seams
    float w = smoothstep(1.2, 1.35, p.x) * smoothstep(0.2, 0.26, p.y) * smoothstep(0.5, 0.44, p.y);
    return mix(col, mix(above, below, m), 0.5 * w);
}

// ---- L1b: warm brush -- soft long strokes that modulate the warm paint ------------
void warmBrush(inout vec3 col, vec2 p) {
    if (p.y < 0.25 || tearCoord(p) < -0.1) return;
    float ang = 0.9;                           // ~52 deg, as in the warm top right
    vec2 q = rot(-ang) * p;
    vec2 cell = vec2(0.16, 0.022);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 51.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * vec2(0.8, 0.7)) * cell;
            vec2 pc = rot(ang) * c;
            float z = warmMask(pc) * smoothstep(0.35, 0.6, pc.y);
            if (h.z > 0.8 * z) continue;
            float len = cell.x * (0.3 + 0.5 * hash12(id + 2.0));
            float wid = cell.y * (0.3 + 0.5 * hash12(id + 3.0));
            vec2 d = rot((hash12(id + 4.0) - 0.5) * 0.4) * vec2(len, 0.0);
            float sd = sdTaper(q, c - d, c + d, wid, wid * 0.4);
            float k = hash12(id + 6.0);
            vec3 tint = k < 0.4 ? hexColor(0xf26a3c) : (k < 0.75 ? hexColor(0xb8205a) : hexColor(0xf47a8a));
            paintA(col, tint, 0.35 * fill(sd, wid * 1.5), p, 0.3, 0.3, ang);
        }
    }
}

// ---- L1c: mottle -- soft medium blotches that dirty the warm paint ---------------
void mottle(inout vec3 col, vec2 p) {
    if (tearCoord(p) < -0.04) return;
    float cs = 0.04;
    vec2 g = floor(p / cs);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 91.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cs;
            float z = warmMask(c);
            if (h.z > 0.8 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = vec2(0.006 + 0.022 * s, 0.004 + 0.01 * s);
            float ang = 0.85 + (hash12(id + 2.0) - 0.5) * 1.0;
            float sd = sdBlob(p, c, ab, ang, 0.8, hash12(id + 3.0) * 30.0);
            float k = hash12(id + 4.0);
            vec3 mc = k < 0.35 ? hexColor(0xb82850) : (k < 0.65 ? hexColor(0xf2703e) : (k < 0.85 ? hexColor(0x8a1c5c) : hexColor(0xf48aa0)));
            if (c.y < 0.45 && k < 0.65) mc = mix(mc, hexColor(0xc070b8), 0.6);
            paint(col, mc, 0.32 * fill(sd, ab.y * 0.7), p, 0.35, 0.3);
        }
    }
}

// ---- L2: dry brush streaks ----------------------------------------------------------
// One pass of 35 deg strokes. len/wid: (min, range) of the half length in cell
// units and of the half width in pixels.
void brushPass(inout vec3 col, vec2 p, vec2 cell, float seed, vec2 len, vec2 wid, float alpha) {
    float tp = tearCoord(p);
    if (tp < -0.16 || tp > 0.62) return;      // outside the zone (+ stroke reach)
    vec2 q = rot(-A35) * p;                    // x along the tear
    vec2 g = floor(q / cell);
    for (int j = -2; j <= 2; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, seed));
            vec2 c = (id + vec2(0.5) + (h.xy - 0.5) * vec2(0.8, 0.6)) * cell;
            vec2 pc = rot(A35) * c;            // centre back in p space
            float t = tearCoord(pc);
            float zone = smoothstep(-0.10, 0.02, t) * (1.0 - smoothstep(0.30, 0.55, t));
            zone *= 1.0 - 0.7 * smoothstep(0.5, 0.75, pc.y);
            if (h.z > 0.7 * zone) continue;
            float l = cell.x * (len.x + len.y * hash12(id + 3.1));
            float w = PX * (wid.x + wid.y * hash12(id + 7.7));
            float steer = 0.3 * smoothstep(0.45, 0.75, pc.y) * smoothstep(0.8, 1.05, pc.x);
            vec2 d = rot(steer + (hash12(id + 5.5) - 0.5) * 0.6) * vec2(l, 0.0);
            float sd = sdTaper(q, c - d, c + d, w, w * 0.2);
            float pick = hash12(id + 1.3);
            vec3 sc = pick < 0.6 ? hexColor(0x2a0f48) : (pick < 0.88 ? hexColor(0x4a2088) : hexColor(0x9a6ac0));
            if (pick >= 0.88 && t > 0.25) sc = hexColor(0x8a1c5a);
            float near = exp(-pow((t - 0.08) / 0.12, 2.0));
            paint(col, sc, alpha * (0.6 + 0.5 * near) * fill(sd, PX * 0.8), p, 0.3, 0.2);
        }
    }
}

// Soft blue smears in the lower-left sky: wide, low-contrast 35 deg brush
// swaths (lighter blue and near-black), not hard lines.
void skyBrush(inout vec3 col, vec2 p) {
    if (p.y > 0.62 || tearCoord(p) > 0.1) return;
    vec2 q = rot(-A35) * p;
    vec2 cell = vec2(0.14, 0.02);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 17.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * vec2(0.8, 0.6)) * cell;
            vec2 pc = rot(A35) * c;
            float z = skyMask(pc) * smoothstep(0.55, 0.1, pc.y);
            if (h.z > 0.7 * z) continue;
            float l = cell.x * (0.25 + 0.45 * hash12(id + 1.0));
            float w = PX * (6.0 + 12.0 * hash12(id + 2.0));
            vec2 d = rot((hash12(id + 4.0) - 0.5) * 0.15) * vec2(l, 0.0);
            float sd = sdTaper(q, c - d, c + d, w, w * 0.4);
            vec3 sc = hash12(id + 3.0) < 0.55 ? hexColor(0x24249a) : hexColor(0x080a34);
            paint(col, sc, 0.2 * fill(sd, w), p, 0.15, 0.3);
        }
    }
}

// Dark navy teardrop dashes: the dense dry-brush flicks of the lower tear band.
void bandDashes(inout vec3 col, vec2 p) {
    float tp = tearCoord(p);
    if (tp < -0.12 || tp > 0.45 || p.y > 0.62) return;
    vec2 q = rot(-A35) * p;
    vec2 cell = vec2(0.04, 0.009);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 19.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * vec2(0.9, 0.5)) * cell;
            vec2 pc = rot(A35) * c;
            float t = tearCoord(pc);
            float z = smoothstep(-0.08, 0.0, t) * smoothstep(0.32, 0.12, t) * smoothstep(0.5, 0.25, pc.y);
            if (h.z > 0.45 * z) continue;
            z *= 0.4 + 1.2 * clump(pc, 19.0);
            if (h.z > 0.45 * z) continue;
            float l = PX * (5.0 + 14.0 * hash12(id + 1.0));
            float w = PX * (1.3 + 2.6 * pow(hash12(id + 2.0), 1.5));
            vec2 d = rot((hash12(id + 4.0) - 0.5) * 0.25) * vec2(l, 0.0);
            float sd = sdTaper(q, c - d, c + d, w * 0.25, w);   // teardrop: head down-left
            vec3 sc = hash12(id + 3.0) < 0.75 ? hexColor(0x1a1052) : hexColor(0x3a2490);
            over(col, sc, 0.75 * fill(sd, PX * 0.7));
        }
    }
}

void dryBrush(inout vec3 col, vec2 p) {
    skyBrush(col, p);
    bandDashes(col, p);
    brushPass(col, p, vec2(0.10, 0.008), 11.0, vec2(0.2, 0.6), vec2(0.4, 1.0), 0.22);  // hair lines
    brushPass(col, p, vec2(0.06, 0.016), 13.0, vec2(0.1, 0.5), vec2(0.8, 3.5), 0.55);  // dashes
}

// ---- L2b: smudges -- soft irregular violet/ink blotches in the tear band ------------
void smudges(inout vec3 col, vec2 p) {
    float tp = tearCoord(p);
    if (tp < -0.3 || tp > 0.55 || p.y > 0.9) return;
    float cs = 0.05;
    vec2 g = floor(p / cs);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 71.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cs;
            float t = tearCoord(c);
            float z = exp(-pow((t - 0.15) / 0.14, 2.0)) * (1.0 - smoothstep(0.6, 0.85, c.y)) * smoothstep(0.05, 0.25, c.y);
            if (h.z > 0.7 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = vec2(0.015 + 0.05 * s, 0.005 + 0.012 * s);   // long along the tear
            float ang = A35 + (hash12(id + 2.0) - 0.5) * 0.4;
            float sd = sdBlob(p, c, ab, ang, 0.9, hash12(id + 3.0) * 40.0);
            float k = hash12(id + 4.0);
            vec3 sc = k < 0.35 ? hexColor(0x2a1050) : (k < 0.6 || t < 0.05 ? hexColor(0x5e2a9e) : hexColor(0x8a1c78));
            paint(col, sc, 0.55 * fill(sd, ab.y * 0.4), p, 0.45, 0.4);
        }
    }
}

// ---- L2c: tear chunks -- mid-size torn violet/magenta flakes along the tear -------
void tearChunks(inout vec3 col, vec2 p) {
    float tp = tearCoord(p);
    if (tp < -0.18 || tp > 0.34 || p.y < 0.36) return;
    vec2 q = rot(-A35) * p;
    vec2 cell = vec2(0.05, 0.025);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 81.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cell;
            vec2 pc = rot(A35) * c;
            float z = exp(-pow((tearCoord(pc) - 0.08) / 0.09, 2.0)) * (1.0 - 0.5 * smoothstep(0.6, 0.9, pc.y)) * smoothstep(0.4, 0.55, pc.y);
            if (h.z > 0.4 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = PX * (3.0 + 12.0 * s * s) * vec2(1.6 + 1.5 * hash12(id + 2.0), 1.0);
            float sd = sdFlake(rot((hash12(id + 3.0) - 0.5) * 0.7) * (q - c), ab, s * 90.0, 0.55);
            sd = torn(sd, p, 90.0, ab.y * 0.25);
            float k = hash12(id + 4.0);
            vec3 cc = k < 0.3 ? hexColor(0x8b3d9c) : (k < 0.55 ? hexColor(0xaf5bac) : (k < 0.8 ? hexColor(0x5b2689) : hexColor(0x2a0f48)));
            stamp(col, cc, p, 0.4, (0.5 + 0.4 * hash12(id + 5.0)) * dryFill(sd, PX, p, ab.y, 0.7));
        }
    }
}

// ---- the wet background -------------------------------------------------------
// pd: p shifted by the slow drift of the scattered strokes along the tear.
// The upstream copy the bristle drag picks up skips the two finest (and most
// expensive) layers, mottle and dry brush: they only show in dry bristles.
vec3 background(vec2 p, vec2 pd, bool upstream) {
    vec3 col = coralFront(colourField(p), p);
    softWashes(col, p);
    warmBrush(col, p);
    if (!upstream) {
        mottle(col, p);
        dryBrush(col, pd);
    }
    smudges(col, p);
    tearChunks(col, pd);
    return col;
}

vec3 paintAt(vec2 p, bool upstream) {
    return background(p, p - DIR * 0.004 * iTime, upstream);
}
