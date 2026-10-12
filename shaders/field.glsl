// field.glsl - shared by both passes: constants, SDF primitives, the paint-look
// helpers, zone masks and the L0 colour field. Needs common.glsl first.
//
// Coordinates: p = fragCoord / iResolution.y (x in 0..1.78, y in 0..1, origin
// bottom left). R(x, y) converts reference pixel positions (y down) to p.
// PX (one reference pixel in p units) is set at the top of each mainImage.

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
    if (d > amp) return d;                      // far outside: the noise can't reach
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
    float outer = fill(d - 0.7 * edge, soft);
    if (outer <= 0.0) return 0.0;               // cheap early out: no noise
    float inner = fill(d + 0.3 * edge, soft);
    if (inner >= 1.0) return 1.0;
    return max(inner, outer * dryCov(p, amt));
}

// dryFill with the dry streaks along an explicit angle (e.g. vertical runs).
float dryFillA(float d, float soft, vec2 p, float edge, float amt, float ang) {
    float outer = fill(d - 0.7 * edge, soft);
    if (outer <= 0.0) return 0.0;
    float inner = fill(d + 0.3 * edge, soft);
    if (inner >= 1.0) return 1.0;
    return max(inner, outer * dryCovA(p, amt, ang));
}

// Clumpy density: specks gather in loose clouds instead of an even rain.
float clump(vec2 c, float seed) {
    return smoothstep(0.36, 0.70, 0.62 * noise(c * 5.0 + seed) + 0.38 * noise(c * 11.3 + seed * 1.7));
}

// Stamp colour c with coverage a, dry-brush coverage and pigment tone. The
// noise lookups only run where the shape actually covers the pixel.
void paint(inout vec3 col, vec3 c, float a, vec2 p, float dry, float tn) {
    if (a <= 0.0) return;
    over(col, c * (tn > 0.0 ? tone(p, tn) : 1.0), a * (dry > 0.0 ? dryCov(p, dry) : 1.0));
}

// Same with an explicit streak angle for the dry coverage.
void paintA(inout vec3 col, vec3 c, float a, vec2 p, float dry, float tn, float ang) {
    if (a <= 0.0) return;
    over(col, c * (tn > 0.0 ? tone(p, tn) : 1.0), a * dryCovA(p, dry, ang));
}

// Toned stamp without dry coverage (a usually comes from dryFill).
void stamp(inout vec3 col, vec3 c, vec2 p, float tn, float a) {
    if (a <= 0.0) return;
    over(col, c * tone(p, tn), a);
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
    ANCHOR( 200.0, 740.0, 0x141670, 0.16)
    ANCHOR( 450.0, 100.0, 0x1a0c38, 0.14)
    ANCHOR( 560.0, 300.0, 0x220e46, 0.12)
    ANCHOR( 670.0,  70.0, 0x4a1450, 0.09)
    ANCHOR( 420.0, 150.0, 0x3a1448, 0.05)
    ANCHOR( 650.0, 320.0, 0x3c1462, 0.09)
    ANCHOR( 480.0, 470.0, 0x1c1050, 0.10)
    // tear band, violet
    ANCHOR( 420.0, 780.0, 0x3c2ea0, 0.14)
    ANCHOR( 300.0, 790.0, 0x22207f, 0.06)
    ANCHOR( 150.0, 600.0, 0x050b38, 0.12)
    ANCHOR( 380.0, 620.0, 0x1a1660, 0.08)
    ANCHOR( 600.0, 770.0, 0x6a4ab8, 0.14)
    ANCHOR( 560.0, 650.0, 0x4a2aa0, 0.12)
    ANCHOR( 680.0, 520.0, 0x8c3294, 0.12)
    ANCHOR( 760.0, 420.0, 0xa02c8e, 0.12)
    ANCHOR( 800.0, 650.0, 0x9a55aa, 0.13)
    ANCHOR( 900.0, 760.0, 0x9558aa, 0.13)
    // warm side
    ANCHOR( 800.0, 240.0, 0xc42a5c, 0.10)
    ANCHOR( 990.0,  70.0, 0xc82a50, 0.12)
    ANCHOR( 790.0,  50.0, 0x3a1048, 0.07)
    ANCHOR(1100.0, 100.0, 0x8a1660, 0.11)
    ANCHOR(1030.0, 150.0, 0x3a0a4a, 0.085)
    ANCHOR(1060.0, 125.0, 0x5a0c50, 0.05)
    ANCHOR(1150.0,  35.0, 0xc0287a, 0.05)
    ANCHOR(1045.0, 265.0, 0xb02060, 0.05)
    ANCHOR( 910.0, 260.0, 0xf45272, 0.08)
    ANCHOR( 545.0, 385.0, 0x4a1a6a, 0.06)
    ANCHOR(1265.0, 130.0, 0x8a1a64, 0.06)
    ANCHOR(1275.0,  40.0, 0x8a1a6a, 0.06)
    ANCHOR(1380.0,  60.0, 0xe03a62, 0.13)
    ANCHOR(1380.0, 230.0, 0xf25562, 0.14)
    ANCHOR(1150.0, 300.0, 0xec4864, 0.13)
    ANCHOR( 950.0, 330.0, 0xd83866, 0.12)
    ANCHOR(1420.0, 400.0, 0xf06a7a, 0.10)
    ANCHOR(1150.0, 450.0, 0xf0626e, 0.10)
    // the coral runs down into pink along a roughly horizontal front (y ~ 500)
    ANCHOR(1250.0, 470.0, 0xf2646c, 0.06)
    ANCHOR(1400.0, 480.0, 0xf06878, 0.06)
    ANCHOR(1200.0, 570.0, 0xe47cb4, 0.06)
    ANCHOR(1330.0, 545.0, 0xc890d4, 0.05)
    ANCHOR( 990.0, 520.0, 0xe06a9e, 0.10)
    ANCHOR( 880.0, 460.0, 0xa42b89, 0.07)
    ANCHOR( 870.0, 570.0, 0xb04ca0, 0.07)
    ANCHOR(1100.0, 600.0, 0xe880b4, 0.12)
    ANCHOR(1380.0, 600.0, 0xd072b0, 0.13)
    ANCHOR(1200.0, 720.0, 0xdc7cb8, 0.12)
    ANCHOR(1400.0, 790.0, 0x4a2080, 0.10)
    ANCHOR(1445.0, 730.0, 0x6a3090, 0.07)
    ANCHOR(1050.0, 800.0, 0x9a4ea2, 0.10)
    ANCHOR(1170.0, 780.0, 0x9a50a2, 0.10)
    ANCHOR(1300.0, 770.0, 0x8a409a, 0.10)
#undef ANCHOR
    return acc / max(wsum, 1e-6);
}

