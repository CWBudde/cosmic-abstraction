// Cosmic Abstraction - Rival A: "stamp collage".
//
// The picture is a smooth, hand-authored colour field with explicit SDF shape
// primitives stamped on top, back to front. Scattered stamps live in jittered
// grid cells (mostly in a frame rotated to the 35 deg tear direction); zone
// masks drive their density, size, colour and orientation. A handful of hero
// stamps are placed by hand at the reference landmarks.
//
// Layer stack (back to front):
//   L0  colour field     normalised Gaussian blend of hand-placed colour anchors
//   L1  soft washes      burst glow, torn orange flame masses, hazes
//   L1b warm brush       soft long 52 deg strokes modulating the warm paint
//   L1c mottle           soft medium blotches that dirty the warm paint
//   S   bristle drag     the background (L0-L2c) is dragged along 35 deg (50 deg
//                        top right) by a comb of 2-9 px bristles, each picking
//                        paint at its own hashed upstream offset
//   L2  dry brush        35 deg hair lines + dashes along the tear (steered to
//                        ~50 deg top right), faint blue streaks in the low sky
//   L2b smudges          soft irregular violet/ink blotches in the tear band
//   L2c tear chunks      mid-size torn violet/magenta flakes along the tear
//   L3  slashes          hero dark slashes, dark wedge, elongated dark blobs
//   L4  burst debris     torn orange/violet flakes and sparks in the burst
//   L4b burst streaks    near-vertical torn streaks in the burst (80-110 deg)
//   L5  sky specks       clumped pink flakes (mostly round, a few streaked along
//                        '\'), fine star dust, hair scratches, hand-placed flakes
//   L6  ink specks       two clumped scales (dust + specks with flung tails),
//                        35/50 deg elongated, rounder in the lower right
//   L6a grit             dense 1 px light/dark pigment specks in the tear band
//   L6b drips            faint vertical runs on the lower warm side
//   L7  hero chunks      top violet streak, orange flame leaves, pale flakes,
//                        drips, dark drops (dry fringes, toned interiors)
//   L8  grade + grain    chroma boost (SATURATION) and per-pixel film grain
//
// Paint look: dryCov() (streaky partial coverage), tone() (pigment pooling) and
// dryFill() (solid core + broken dry fringe) turn the SDF stamps into paint;
// their streak direction follows paintAng() (35 deg, 50 deg top right).
//
// Coordinates: p = fragCoord / iResolution.y (x in 0..1.78, y in 0..1, origin
// bottom left). R(x, y) converts reference pixel positions (y down) to p.

#include "common.glsl"

#ifndef SATURATION
#define SATURATION 1.12
#endif
#ifndef EXPOSURE
#define EXPOSURE 1.0
#endif

const float ASPECT = 1456.0 / 816.0;
const float A35 = 0.6109;                 // 35 deg in radians
const vec2 DIR = vec2(0.8192, 0.5736);    // along the tear
float PX;                                 // one reference pixel in p units

vec2 R(float x, float y) { return vec2(x, 816.0 - y) / 816.0; }

// ---- SDF primitives -----------------------------------------------------------
float sdEllipse(vec2 q, vec2 ab) {
    float k0 = length(q / ab);
    float k1 = length(q / (ab * ab));
    return k0 * (k0 - 1.0) / max(k1, 1e-6);
}

// Tapered capsule from a (radius ra) to b (radius rb).
float sdTaper(vec2 p, vec2 a, vec2 b, float ra, float rb) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - mix(ra, rb, h);
}

// Torn flake: ellipse with a hashed angular wobble of the radius.
float sdFlake(vec2 q, vec2 ab, float seed, float amp) {
    float a = atan(q.y, q.x);
    vec3 h = hash33(vec3(seed, seed * 1.7, 3.1)) * TAU;
    float w = 1.0 + amp * (0.5 * sin(3.0 * a + h.x) + 0.3 * sin(5.0 * a + h.y) + 0.2 * sin(9.0 * a + h.z));
    return (length(q / ab) - w) * min(ab.x, ab.y);
}

// Noise-perturbed blob in a rotated local frame.
float sdBlob(vec2 p, vec2 c, vec2 ab, float ang, float rough, float seed) {
    vec2 q = rot(-ang) * (p - c);
    float d = sdEllipse(q, ab);
    return d - rough * min(ab.x, ab.y) * (noise(q / min(ab.x, ab.y) * 2.0 + seed) - 0.5);
}

// Torn edge: two octaves of noise pushed onto a distance.
float torn(float d, vec2 p, float freq, float amp) {
    return d + amp * (noise(p * freq) - 0.5) + 0.5 * amp * (noise(p * freq * 3.1 + 7.0) - 0.5);
}

float fill(float d, float soft) { return smoothstep(soft, -soft, d); }

void over(inout vec3 col, vec3 c, float a) { col = mix(col, c, clamp(a, 0.0, 1.0)); }

// ---- paint look -----------------------------------------------------------------
// Dry-brush coverage: streaky noise stretched along the 35 deg drag, so a
// stroke only partly covers the paint below it. amt = 0 solid, 1 very dry.
float dryCovA(vec2 p, float amt, float ang) {
    vec2 q = rot(-ang) * p;
    float n = 0.55 * noise(q * vec2(18.0, 200.0)) + 0.45 * noise(q * vec2(90.0, 120.0) + 5.0);
    return mix(1.0, smoothstep(0.25, 0.6, n), amt);
}

// Local paint direction: the 35 deg tear, turning to ~50 deg in the warm top
// right as in the reference. Textures are evaluated in both fixed frames and
// blended by this weight (rotating by a varying angle would shear the noise).
float paintW(vec2 p) {
    return smoothstep(0.5, 0.7, p.y) * smoothstep(0.95, 1.15, p.x);
}
float paintAng(vec2 p) { return mix(A35, 0.87, paintW(p)); }

float dryCov(vec2 p, float amt) {
    float w = paintW(p);
    if (w < 0.01) return dryCovA(p, amt, A35);
    if (w > 0.99) return dryCovA(p, amt, 0.87);
    return mix(dryCovA(p, amt, A35), dryCovA(p, amt, 0.87), w);
}

// Streaky tonal variation inside a stroke (pigment pooling), around 1.
float toneA(vec2 p, float ang) {
    vec2 q = rot(-ang) * p;
    return 0.5 * noise(q * vec2(30.0, 90.0)) + 0.5 * noise(p * 140.0) - 0.5;
}
float tone(vec2 p, float amt) {
    float w = paintW(p);
    float n = w < 0.01 ? toneA(p, A35) : (w > 0.99 ? toneA(p, 0.87) : mix(toneA(p, A35), toneA(p, 0.87), w));
    return 1.0 + amt * n;
}

// Solid core plus a dry, broken fringe that reaches 'edge' past the outline.
float dryFill(float d, float soft, vec2 p, float edge, float amt) {
    float inner = fill(d + 0.3 * edge, soft);
    float outer = fill(d - 0.7 * edge, soft) * dryCov(p, amt);
    return max(inner, outer);
}

// Clumpy density: specks gather in loose clouds instead of an even rain.
float clump(vec2 c, float seed) {
    return smoothstep(0.38, 0.72, fbm(c * 5.0 + seed, 3));
}

void paint(inout vec3 col, vec3 c, float a, vec2 p, float dry, float tn) {
    over(col, c * tone(p, tn), a * dryCov(p, dry));
}

// ---- zone masks ------------------------------------------------------------------
// Signed distance-ish coordinate across the tear: < 0 sky, > 0 warm side.
float tearCoord(vec2 p) {
    // The sky/paint transition is curved: shallow near the bottom, steep at
    // the top. x(v) is a quadratic through R(330,770), R(610,457), R(730,50).
    float v = p.y;
    float x = 0.331 + 1.252 * v - 0.694 * v * v;
    float dx = 1.252 - 1.388 * v;
    return (p.x - x) / sqrt(1.0 + dx * dx);
}
float skyMask(vec2 p)   { return 1.0 - smoothstep(-0.12, 0.04, tearCoord(p)); }
float burstMask(vec2 p) {
    vec2 d = (p - R(615.0, 180.0)) / vec2(0.22, 0.25);
    return exp(-dot(d, d));
}
float warmMask(vec2 p)  { return smoothstep(0.0, 0.25, tearCoord(p)); }

// ---- L0: colour field ------------------------------------------------------------
vec3 colourField(vec2 p) {
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
    ANCHOR( 420.0, 150.0, 0x3a1448, 0.05)
    ANCHOR( 650.0, 320.0, 0x3c1462, 0.09)
    ANCHOR( 480.0, 470.0, 0x1c1050, 0.10)
    // tear band, violet
    ANCHOR( 420.0, 780.0, 0x4a2c95, 0.14)
    ANCHOR( 300.0, 790.0, 0x22207f, 0.06)
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
    ANCHOR( 900.0, 300.0, 0xec4068, 0.07)
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
    ANCHOR(1100.0, 600.0, 0xe880b4, 0.12)
    ANCHOR(1380.0, 600.0, 0xd072b0, 0.13)
    ANCHOR(1200.0, 720.0, 0xdc7cb8, 0.12)
    ANCHOR(1400.0, 790.0, 0x5a2888, 0.10)
    ANCHOR(1445.0, 730.0, 0x6a3090, 0.07)
    ANCHOR(1050.0, 800.0, 0x9a4ea2, 0.10)
    ANCHOR(1170.0, 780.0, 0x9a50a2, 0.10)
    ANCHOR(1300.0, 770.0, 0x8a409a, 0.10)
#undef ANCHOR
    return acc / max(wsum, 1e-6);
}

// ---- L1: soft washes ---------------------------------------------------------------
void softWashes(inout vec3 col, vec2 p) {
    // orange glow in the burst
    over(col, hexColor(0xe0603a) * tone(p, 0.5), 0.4 * fill(sdBlob(p, R(515.0, 150.0), vec2(0.016, 0.055), -0.3, 0.8, 3.0), 0.015) * dryCovA(p, 0.4, 1.27));
    over(col, hexColor(0xe0583a), 0.30 * fill(sdBlob(p, R(770.0, 200.0), vec2(0.05, 0.10), 1.35, 0.8, 7.0), 0.04));
    // torn orange flame mass on the burst's right flank
    float fl = sdEllipse(rot(-1.32) * (p - R(760.0, 215.0)), vec2(0.13, 0.03));
    over(col, hexColor(0xe8602c) * tone(p, 0.5), 0.6 * fill(torn(fl, p, 70.0, 0.03), PX * 2.0) * dryCovA(p, 0.6, 1.32));
    float fl2 = sdEllipse(rot(-1.45) * (p - R(712.0, 300.0)), vec2(0.07, 0.016));
    over(col, hexColor(0xd85030) * tone(p, 0.5), 0.5 * fill(torn(fl2, p, 90.0, 0.015), PX * 2.0) * dryCovA(p, 0.6, 1.45));
    // magenta haze near the burst right side
    over(col, hexColor(0xb02a7a), 0.4 * fill(sdBlob(p, R(780.0, 330.0), vec2(0.05, 0.10), 0.9, 0.7, 11.0), 0.05));
    // pink haze lower middle
    over(col, hexColor(0xc0609e), 0.35 * fill(sdBlob(p, R(900.0, 560.0), vec2(0.07, 0.16), 0.61, 0.7, 5.0), 0.06));
}

// ---- L1b: warm brush -- soft long strokes that modulate the warm paint ------------
void warmBrush(inout vec3 col, vec2 p) {
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
            over(col, tint * tone(p, 0.3), 0.35 * fill(sd, wid * 1.5) * dryCovA(p, 0.3, ang));
        }
    }
}

// ---- L4b: burst streaks -- near-vertical torn streaks and drips -------------------
void burstStreaks(inout vec3 col, vec2 p) {
    vec2 cell = vec2(0.018, 0.06);
    vec2 g = floor(p / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 61.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.8) * cell;
            float z = burstMask(c) * smoothstep(0.35, 0.6, c.y);
            z = max(z, smoothstep(0.7, 0.95, c.y) * smoothstep(0.75, 0.85, c.x) * smoothstep(1.15, 1.05, c.x));
            if (h.z > 0.6 * z) continue;
            float len = PX * (8.0 + 35.0 * hash12(id + 1.0));
            float wid = PX * (2.0 + 7.0 * pow(hash12(id + 2.0), 2.0));
            float a = 1.57 + (hash12(id + 3.0) - 0.5) * 0.6;
            vec2 d = vec2(cos(a), sin(a)) * len;
            float sd = torn(sdTaper(p, c + d, c - d, wid * 0.3, wid), p, 300.0, wid * 0.8);
            float k = hash12(id + 4.0);
            vec3 sc = k < 0.35 ? hexColor(0x4a2488) : (k < 0.6 ? hexColor(0x7a40b8) : (k < 0.8 ? hexColor(0xd8582c) : hexColor(0x160a2c)));
            float fade = 0.6 + 0.4 * smoothstep(-1.0, 0.5, dot(p - c, d) / dot(d, d));   // paler tail
            over(col, sc * tone(p, 0.4), 0.65 * fade * fill(sd, PX * 1.5) * dryCovA(p, 0.35, a));
        }
    }
}

// ---- L1c: mottle -- soft medium blotches that dirty the warm paint ---------------
void mottle(inout vec3 col, vec2 p) {
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

// Faint blue 35 deg streaks in the lower-left sky.
void skyBrush(inout vec3 col, vec2 p) {
    vec2 q = rot(-A35) * p;
    vec2 cell = vec2(0.12, 0.01);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 17.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * vec2(0.8, 0.6)) * cell;
            vec2 pc = rot(A35) * c;
            float z = skyMask(pc) * smoothstep(0.55, 0.15, pc.y);
            if (h.z > 0.6 * z) continue;
            float l = cell.x * (0.2 + 0.5 * hash12(id + 1.0));
            float w = PX * (1.0 + 3.0 * hash12(id + 2.0));
            vec2 d = vec2(l, 0.0);
            float sd = sdTaper(q, c - d, c + d, w, w * 0.3);
            vec3 sc = hash12(id + 3.0) < 0.6 ? hexColor(0x26238e) : hexColor(0x070a30);
            paint(col, sc, 0.25 * fill(sd, w), p, 0.5, 0.0);
        }
    }
}

void dryBrush(inout vec3 col, vec2 p) {
    skyBrush(col, p);
    brushPass(col, p, vec2(0.10, 0.008), 11.0, vec2(0.2, 0.6), vec2(0.4, 1.0), 0.32);  // hair lines
    brushPass(col, p, vec2(0.06, 0.016), 13.0, vec2(0.1, 0.5), vec2(0.8, 3.5), 0.55);  // dashes
}

// ---- L2b: smudges -- soft irregular violet/ink blotches in the tear band ------------
void smudges(inout vec3 col, vec2 p) {
    float cs = 0.05;
    vec2 g = floor(p / cs);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 71.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cs;
            float t = tearCoord(c);
            float z = exp(-pow((t - 0.12) / 0.16, 2.0)) * (1.0 - smoothstep(0.6, 0.85, c.y));
            if (h.z > 0.7 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = vec2(0.008 + 0.03 * s, 0.006 + 0.014 * s);
            float ang = hash12(id + 2.0) * PI;
            float sd = sdBlob(p, c, ab, ang, 0.9, hash12(id + 3.0) * 40.0);
            float k = hash12(id + 4.0);
            vec3 sc = k < 0.45 ? hexColor(0x2a1050) : (k < 0.8 ? hexColor(0x7a2a90) : hexColor(0xb05ab0));
            paint(col, sc, 0.5 * fill(sd, ab.y * 0.5), p, 0.45, 0.4);
        }
    }
}

// ---- L2c: tear chunks -- mid-size torn violet/magenta flakes along the tear -------
void tearChunks(inout vec3 col, vec2 p) {
    vec2 q = rot(-A35) * p;
    vec2 cell = vec2(0.05, 0.025);
    vec2 g = floor(q / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 81.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cell;
            vec2 pc = rot(A35) * c;
            float z = exp(-pow((tearCoord(pc) - 0.08) / 0.09, 2.0)) * (1.0 - 0.5 * smoothstep(0.6, 0.9, pc.y)) * smoothstep(0.25, 0.45, pc.y);
            if (h.z > 0.4 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = PX * (3.0 + 12.0 * s * s) * vec2(1.6 + 1.5 * hash12(id + 2.0), 1.0);
            float sd = sdFlake(rot((hash12(id + 3.0) - 0.5) * 0.7) * (q - c), ab, s * 90.0, 0.55);
            sd = torn(sd, p, 90.0, ab.y * 0.25);
            float k = hash12(id + 4.0);
            vec3 cc = k < 0.3 ? hexColor(0x8b3d9c) : (k < 0.55 ? hexColor(0xaf5bac) : (k < 0.8 ? hexColor(0x5b2689) : hexColor(0x2a0f48)));
            over(col, cc * tone(p, 0.4), (0.5 + 0.4 * hash12(id + 5.0)) * dryFill(sd, PX, p, ab.y, 0.7));
        }
    }
}

// ---- L3: dark slashes -------------------------------------------------------------
void slashes(inout vec3 col, vec2 p) {
    vec3 ink = hexColor(0x120828);
    vec3 navy = hexColor(0x2a1868);
    float wob = noise(p * 45.0) - 0.5;
    // violet under-stroke riding above the main slash
    float vb = sdTaper(p, R(870.0, 250.0), R(1060.0, 50.0), 0.03, 0.02);
    paint(col, hexColor(0x6a34b0), 0.6 * fill(torn(vb, p, 50.0, 0.02), PX * 3.0), p, 0.6, 0.4);
    // main long slash band through the warm side: several overlapping strokes
    float d = sdTaper(p, R(815.0, 400.0), R(1140.0, 70.0), 0.004, 0.011);
    d = min(d, sdTaper(p, R(930.0, 285.0), R(1100.0, 115.0), 0.014, 0.008));
    d = min(d, sdTaper(p, R(1060.0, 170.0), R(1220.0, 40.0), 0.006, 0.003));
    over(col, ink * tone(p, 0.6), dryFill(d + 0.008 * wob, PX * 1.2, p, 0.012, 0.8));
    float m = sdEllipse(rot(-0.8) * (p - R(1030.0, 180.0)), vec2(0.085, 0.016));
    over(col, hexColor(0x160828) * tone(p, 0.6), dryFill(torn(m, p, 90.0, 0.009), PX * 1.5, p, 0.014, 0.8));
    // parallel thinner slashes
    float d2 = sdTaper(p, R(800.0, 470.0), R(1000.0, 300.0), 0.002, 0.004);
    d2 = min(d2, sdTaper(p, R(990.0, 140.0), R(1150.0, 10.0), 0.004, 0.002));
    d2 = min(d2, sdTaper(p, R(840.0, 290.0), R(990.0, 150.0), 0.0015, 0.004));
    d2 = min(d2, sdTaper(p, R(560.0, 760.0), R(800.0, 560.0), 0.0015, 0.003));
    d2 = min(d2, sdTaper(p, R(1180.0, 160.0), R(1450.0, -20.0), 0.002, 0.004));
    over(col, ink, 0.8 * dryFill(d2 + 0.004 * (noise(p * 90.0) - 0.5), PX, p, 0.006, 0.8));
    // dark wedge, top right
    float w = sdTaper(p, R(1195.0, 165.0), R(1300.0, 45.0), 0.028, 0.02);
    over(col, hexColor(0x3a0c3c) * tone(p, 0.6), 0.85 * dryFill(torn(w, p, 60.0, 0.014), PX * 1.5, p, 0.016, 0.8));
    float w2 = sdEllipse(rot(-0.75) * (p - R(1150.0, 60.0)), vec2(0.06, 0.016));
    over(col, hexColor(0x5a1060) * tone(p, 0.5), 0.5 * dryFill(torn(w2, p, 70.0, 0.01), PX * 1.5, p, 0.012, 0.8));
    // elongated dark blobs along the slash
    over(col, ink * tone(p, 0.5), dryFill(sdBlob(p, R(1046.0, 254.0), vec2(0.020, 0.009), A35 + 0.2, 0.3, 8.0), PX, p, 0.005, 0.8));
    vec3 nv = mix(navy, hexColor(0x4a3aa0), smoothstep(-0.01, 0.01, dot(p - R(962.0, 322.0), vec2(-0.5, 0.86))));
    over(col, nv * tone(p, 0.5), dryFill(sdBlob(p, R(962.0, 322.0), vec2(0.026, 0.014), A35 + 0.25, 0.3, 6.0), PX, p, 0.006, 0.8));
    over(col, ink * tone(p, 0.5), dryFill(sdBlob(p, R(1185.0, 95.0), vec2(0.03, 0.012), A35, 0.4, 2.0), PX, p, 0.006, 0.8));
}

// ---- L4: burst debris -------------------------------------------------------------
void burstDebris(inout vec3 col, vec2 p) {
    float cs = 0.028;
    vec2 g = floor(p / cs);
    vec2 bc = R(600.0, 190.0);                 // burst centre
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 21.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.9) * cs;
            float z = burstMask(c) * smoothstep(0.45, 0.62, c.y + 0.25 * (c.x - 0.6));
            if (h.z > 0.6 * z) continue;
            float s = hash12(id + 5.0);
            float el = 1.0 + 2.5 * hash12(id + 1.0);
            vec2 ab = PX * mix(1.0, 6.0, s * s * s) * vec2(el, 0.8);
            // elongated radially from the burst centre, with jitter
            vec2 rd = c - bc;
            float ang = hash12(id + 13.0) < 0.5 ? atan(rd.y, rd.x) : 1.57;
            ang += (hash12(id + 9.0) - 0.5) * 0.9;
            float sd = sdFlake(rot(-ang) * (p - c), ab, hash12(id + 2.0) * 100.0, 0.5);
            float pick = hash12(id + 4.0);
            vec3 fc = pick < 0.6 ? hexColor(0xe2582c) : (pick < 0.8 ? hexColor(0xf08848) : hexColor(0x9a4ab0));
            over(col, fc, (0.6 + 0.4 * hash12(id + 12.0)) * fill(sd, PX * 0.7));
        }
    }
    // sparks: tiny dots
    float cs2 = 0.008;
    vec2 g2 = floor(p / cs2);
    vec3 h2 = hash33(vec3(g2, 23.0));
    vec2 c2 = (g2 + 0.2 + 0.6 * h2.xy) * cs2;
    float z2 = burstMask(c2) * (0.2 + 1.4 * clump(c2, 23.0));
    if (h2.z < 0.45 * z2) {
        float r = PX * (0.5 + 1.0 * hash12(g2));
        vec3 sc = hash12(g2 + 1.0) < 0.7 ? hexColor(0xf07a3a) : hexColor(0xe076b0);
        over(col, sc, (0.5 + 0.5 * hash12(g2 + 4.0)) * fill(length(p - c2) - r, PX * 0.6));
    }
}

// ---- L5: sky specks ---------------------------------------------------------------
void skySpecks(inout vec3 col, vec2 p) {
    float cs = 0.024;
    vec2 g = floor(p / cs);
    vec3 h = hash33(vec3(g, 31.0));
    vec2 c = (g + 0.2 + 0.6 * h.xy) * cs;
    float z = skyMask(c) * smoothstep(0.0, 0.5, c.y) * (0.7 + 0.6 * smoothstep(0.5, 1.0, c.y));
    z *= 0.3 + 1.4 * clump(c, 31.0);
    if (h.z < 0.22 * z) {
        float s = hash12(g + 2.0);
        float el = 1.0 + 2.2 * pow(hash12(g + 5.0), 2.5);   // mostly round, a few streaked
        vec2 ab = PX * mix(vec2(1.0), vec2(3.5, 2.5), s * s * s) * vec2(el, 1.0);
        float ang = 2.1 + (hash12(g) - 0.5) * 1.4;     // mostly '\', ~120 deg
        float sd = sdFlake(rot(-ang) * (p - c), ab, s * 50.0, 0.3);
        vec3 pc = mix(hexColor(0xd85aa8), hexColor(0xff88c8), hash12(g + 3.0));
        over(col, pc, (0.5 + 0.5 * hash12(g + 7.0)) * fill(sd, PX * 0.6));
    }
    // fine star dust, clumped, densest towards the burst
    float cs2 = 0.007;
    vec2 g2 = floor(p / cs2);
    vec3 h2 = hash33(vec3(g2, 35.0));
    vec2 c2 = (g2 + 0.2 + 0.6 * h2.xy) * cs2;
    float z2 = skyMask(c2) * (0.2 + 1.2 * clump(c2, 36.0)) * (0.4 + burstMask(c2));
    if (h2.z < 0.18 * z2) {
        vec3 dc = hash12(g2) < 0.6 ? hexColor(0xd070b8) : hexColor(0xf0a0d0);
        over(col, dc, (0.3 + 0.6 * hash12(g2 + 1.0)) * fill(length(p - c2) - PX * (0.4 + 0.7 * hash12(g2 + 2.0)), PX * 0.6));
    }
    // hair streaks: faint thin '\' scratches
    vec2 q = rot(-2.2) * p;
    vec2 cell = vec2(0.06, 0.03);
    vec2 gq = floor(q / cell);
    vec3 hq = hash33(vec3(gq, 33.0));
    vec2 cq = (gq + 0.5 + (hq.xy - 0.5) * 0.6) * cell;
    if (hq.z < 0.25 * skyMask(rot(2.2) * cq)) {
        vec2 d = vec2(cell.x * (0.15 + 0.3 * hash12(gq)), 0.0);
        float sd = sdTaper(q, cq - d, cq + d, PX * 0.3, PX * 0.7);
        over(col, hexColor(0x5a2a80), 0.5 * fill(sd, PX * 0.6));
    }
    // red vertical scratch, top left
    over(col, hexColor(0xb02a50), 0.8 * fill(sdTaper(p, R(76.0, 112.0), R(74.0, 176.0), PX * 1.2, PX * 0.6), PX * 0.7));
    // larger pink flakes, hand placed
    over(col, hexColor(0xe070b0), fill(sdFlake(rot(-1.2) * (p - R(133.0, 440.0)), vec2(0.022, 0.011), 4.0, 0.45), PX));
    over(col, hexColor(0xf096c8), fill(sdFlake(rot(0.2) * (p - R(360.0, 75.0)), vec2(0.012, 0.010), 7.0, 0.3), PX));
    over(col, hexColor(0xe878b8), fill(sdFlake(p - R(232.0, 233.0), vec2(0.007, 0.006), 9.0, 0.3), PX));
    over(col, hexColor(0xe878b8), fill(sdFlake(p - R(372.0, 543.0), vec2(0.006, 0.005), 3.0, 0.3), PX));
    over(col, hexColor(0xe878b8), fill(sdFlake(p - R(303.0, 167.0), vec2(0.006, 0.006), 13.0, 0.3), PX));
    over(col, hexColor(0xe878b8), fill(sdFlake(p - R(462.0, 550.0), vec2(0.005, 0.004), 17.0, 0.3), PX));
}

// ---- L6: ink specks on the warm side ---------------------------------------------
// One scale of ink specks. size: (min, max) radius in px, dens: peak density.
void inkScale(inout vec3 col, vec2 p, float cs, float seed, vec2 size, float dens, float tailP) {
    vec2 q = rot(-A35) * p;
    vec2 g = floor(q / cs);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, seed));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.95) * cs;
            vec2 pc = rot(A35) * c;
            // densest in the lower middle / lower right, sparse in the orange top
            float z = warmMask(pc) * (0.25 + 0.75 * smoothstep(0.65, 0.25, pc.y));
            z *= 0.35 + 1.3 * clump(pc, seed);
            if (h.z > dens * z) continue;
            float s = hash12(id + 6.0);
            float lr = smoothstep(1.15, 1.35, pc.x) * smoothstep(0.55, 0.35, pc.y);   // lower right
            float el = 1.0 + 2.0 * hash12(id + 8.0) * (1.0 - 0.7 * lr);
            float r = PX * mix(size.x, size.y, pow(s, 4.0));
            vec2 ab = r * vec2(el, 1.0);
            float sa = (hash12(id + 9.0) - 0.5) * mix(0.9, PI, lr) - (paintAng(pc) - A35);
            vec2 lq = rot(sa) * (q - c);
            float sd = sdFlake(lq, ab, s * 70.0, 0.25);
            // some specks trail a thin tail behind them (flung paint)
            if (hash12(id + 11.0) < tailP)
                sd = min(sd, sdTaper(lq, vec2(0.0), vec2(-ab.x * (3.0 + 4.0 * hash12(id + 12.0)), 0.0), ab.y * 0.6, 0.0));
            float k = hash12(id + 3.0);
            vec3 ic = k < 0.55 ? hexColor(0x1c1048) : (k < 0.85 ? hexColor(0x3a2278) : hexColor(0x6a1a5a));
            float soft = PX * mix(0.5, 1.3, hash12(id + 13.0) * hash12(id + 15.0));
            over(col, ic, mix(0.6, 1.0, hash12(id + 14.0)) * fill(sd, soft));
        }
    }
}

void inkSpecks(inout vec3 col, vec2 p) {
    inkScale(col, p, 0.007, 41.0, vec2(0.5, 1.4), 0.25, 0.0);   // dust
    inkScale(col, p, 0.016, 43.0, vec2(0.9, 6.0), 0.30, 0.25);  // specks and flung drops
}

// ---- L6b: drips -- faint vertical runs on the lower warm side -------------------
void drips(inout vec3 col, vec2 p) {
    float cs = 0.035;
    float gx = floor(p.x / cs);
    for (int i = -1; i <= 1; i++) {
        float id = gx + float(i);
        vec3 h = hash33(vec3(id, 101.0, 7.0));
        float x = (id + 0.2 + 0.6 * h.x) * cs;
        float top = 0.15 + 0.4 * h.y;
        float len = 0.08 + 0.25 * h.z;
        vec2 a = vec2(x, top), b = vec2(x + 0.004 * (h.x - 0.5), top - len);
        float z = warmMask(vec2(x, top - 0.5 * len)) * smoothstep(1.0, 1.2, x);
        if (hash11(id * 3.7) > 0.25 * z) continue;
        float w = PX * (0.6 + 1.6 * hash11(id + 1.3));
        float sd = sdTaper(p, a, b, w * 0.5, w);
        vec3 dc = hash11(id + 2.1) < 0.5 ? hexColor(0xf4a0c8) : hexColor(0x8a3088);
        paint(col, dc, 0.35 * fill(sd, PX), p, 0.7, 0.0);
    }
}

// ---- L7: hero chunks ---------------------------------------------------------------
void heroChunks(inout vec3 col, vec2 p) {
    // orange leaves (long axis falls to the lower right)
    // painted with a lighter core and a translucent, darker rim
    // flame-like teardrops: sharp tip up-left, round body down-right
    float l1 = sdTaper(p, R(662.0, 482.0), R(700.0, 532.0), 0.004, 0.026);
    float l2 = sdTaper(p, R(765.0, 502.0), R(795.0, 540.0), 0.004, 0.022);
    float l = torn(min(l1, l2), p, 160.0, 0.006);
    vec3 leaf = mix(hexColor(0xd85a30), hexColor(0xf8a070), smoothstep(0.0, -0.008, l) * (0.6 + 0.4 * noise(p * 150.0)));
    over(col, leaf * tone(p, 0.35), 0.92 * dryFill(l, PX * 1.5, p, 0.008, 0.85));
    // top violet streak at u ~ 0.5: vertical, darker at the top edge
    vec2 tv = p - R(726.0, 30.0);
    float ts = torn(sdEllipse(rot(-0.08) * tv, vec2(0.056, 0.095)), p, 50.0, 0.012);
    vec3 tc = mix(hexColor(0x48228a), hexColor(0x7448b0), smoothstep(0.05, -0.07, tv.y) * smoothstep(-0.06, 0.0, -abs(tv.x)));
    over(col, tc * tone(p, 0.5), 0.9 * dryFill(ts, PX * 1.5, p, 0.01, 0.8));
    // pale flakes: top edge, beside the leaves
    over(col, hexColor(0xf4a8d8), fill(sdFlake(p - R(1310.0, 14.0), vec2(0.05, 0.016), 2.0, 0.25), PX));
    over(col, hexColor(0xe8a0e0), fill(sdFlake(p - R(818.0, 26.0), vec2(0.006, 0.02), 6.0, 0.2), PX));
    over(col, hexColor(0xc0a8e0), fill(sdFlake(rot(0.6) * (p - R(605.0, 590.0)), vec2(0.022, 0.011), 3.0, 0.3), PX));
    // big dark drops bottom right
    over(col, hexColor(0x5a1650) * tone(p, 0.5), dryFill(sdBlob(p, R(1155.0, 683.0), vec2(0.016, 0.042), 0.12, 0.3, 1.0), PX, p, 0.006, 0.8));
    over(col, hexColor(0x3a1250) * tone(p, 0.5), dryFill(sdBlob(p, R(1438.0, 680.0), vec2(0.022, 0.04), 0.35, 0.3, 2.0), PX, p, 0.006, 0.8));
    // vertical drips under the leaves, on the right and under the top streak
    over(col, hexColor(0x7a2a6a), 0.7 * fill(sdTaper(p, R(712.0, 560.0), R(728.0, 650.0), 0.0035, 0.001), PX));
    over(col, hexColor(0xb05090), 0.35 * fill(sdTaper(p, R(1190.0, 480.0), R(1205.0, 700.0), 0.003, 0.002), PX));
    float vs = min(sdTaper(p, R(505.0, 160.0), R(462.0, 300.0), 0.0015, 0.004), length(p - R(458.0, 312.0)) - 0.009);
    over(col, hexColor(0x8a4ac0) * tone(p, 0.4), 0.8 * dryFill(torn(vs, p, 120.0, 0.003), PX * 1.5, p, 0.004, 0.7));
    over(col, hexColor(0x7a2a7a), 0.5 * fill(sdTaper(p, R(840.0, 600.0), R(855.0, 790.0), 0.002, 0.004), PX * 1.5));
}

// ---- L8: grain (the chroma grade is applied inline in mainImage) -----------------
vec3 grain(vec3 col, vec2 fragCoord, vec2 p) {
    float n = hash12(fragCoord + 0.37) - 0.5;
    float t = tearCoord(p);
    // quieter in the sky, grittiest in the tear band
    float amp = mix(0.06, 0.10, smoothstep(-0.1, 0.0, t)) + 0.08 * exp(-pow((t - 0.12) / 0.15, 2.0));
    return col * (1.0 + amp * n);
}

// Grit: dense 1 px pigment specks, light and dark, in the tear band.
void grit(inout vec3 col, vec2 p) {
    float cs = 0.0045;
    vec2 g = floor(p / cs);
    vec3 h = hash33(vec3(g, 111.0));
    vec2 c = (g + 0.2 + 0.6 * h.xy) * cs;
    float t = tearCoord(c);
    float z = smoothstep(-0.03, 0.05, t) * smoothstep(0.45, 0.2, t) * (0.3 + 1.2 * clump(c, 111.0));
    z = max(z, 0.6 * burstMask(c) * smoothstep(0.0, 0.1, t));
    if (h.z < 0.45 * z) {
        vec3 gc = hash12(g) < 0.75 ? hexColor(0x2a1450) : hexColor(0x9a78c8);
        over(col, gc, (0.4 + 0.5 * hash12(g + 1.0)) * fill(length(p - c) - PX * (0.4 + 0.8 * hash12(g + 2.0)), PX * 0.6));
    }
}

// ---- background: everything that is wet paint and gets dragged ----------------
vec3 background(vec2 p, vec2 pd) {
    vec3 col = colourField(p);
    softWashes(col, p);
    warmBrush(col, p);
    mottle(col, p);
    dryBrush(col, pd);
    smudges(col, p);
    tearChunks(col, pd);
    return col;
}

// Drag length in p units: none in the sky, long in the tear band and the
// dry-brush lower middle, short in the top right (keeps its ~50 deg strokes).
float dragLen(vec2 p) {
    float t = tearCoord(p);
    float band = smoothstep(-0.02, 0.10, t);
    float topRight = smoothstep(0.55, 0.8, p.y) * smoothstep(0.95, 1.2, p.x);
    return band * mix(70.0, 40.0, topRight) * PX;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    PX = 1.0 / iResolution.y;
    vec2 p = fragCoord / iResolution.y;
    // gentle drift of the scattered debris along the tear
    vec2 pd = p - DIR * 0.004 * iTime;

    // S: bristle drag. A comb of 2-9 px bristles parallel to the tear; each
    // bristle shows the paint picked up at its own hashed distance upstream,
    // so neighbouring bristles carry different colours (striation, not blur).
    vec3 col = background(p, pd);
    float L = dragLen(p);
    if (L > 0.5 * PX) {
        // the drag turns from 35 to ~50 deg in the warm top right, in two
        // discrete frames so the bristle comb never shears
        float tr = smoothstep(0.55, 0.75, p.y) * smoothstep(0.95, 1.15, p.x);
        vec2 dir = tr > 0.5 ? vec2(0.6428, 0.7660) : DIR;
        float lc = dot(fragCoord, vec2(-dir.y, dir.x)) * (816.0 / iResolution.y);
        float wb = 2.0 + 7.0 * hash11(floor(lc / 24.0) + 0.5);
        vec3 hb = hash33(vec3(floor(lc / wb), wb, 7.0));
        float wet = hb.y * hb.y * smoothstep(0.1, 0.5, noise(p * vec2(6.0, 9.0) + hb.z));
        if (wet > 0.02) {
            vec3 picked = background(p - dir * L * (0.2 + 0.8 * hb.x), pd - dir * L * (0.2 + 0.8 * hb.x));
            col = mix(col, picked, 0.85 * wet);
        }
    }

    slashes(col, p);
    burstStreaks(col, pd);
    burstDebris(col, pd);
    skySpecks(col, pd);
    grit(col, pd);
    inkSpecks(col, pd);
    drips(col, p);
    heroChunks(col, p);
    // L8 grade: a touch more chroma (linear blends lose saturation)
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = max(mix(vec3(lum), col, SATURATION), 0.0);
    col = grain(col, fragCoord, p);

    fragColor = vec4(linearToSrgb(col * EXPOSURE), 1.0);
}
