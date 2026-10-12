// Rival C - "ballistic burst"
//
// The reference is read as one physical event: pigment is thrown from a
// source below the frame (MAIN) and flies outwards in a gentle fan along the
// tear, while an explosion (BOOM) in the upper middle throws torn chunks and
// sparks that fall under gravity. Every mark is a particle with a velocity;
// its shape (ellipse stretched by speed + comet tail), size (power law: many
// tiny, few big) and colour (by origin) follow from that.
//
// Layer stack (bottom to top):
//   1.  wash      domain-warped fbm wash: night sky (blue wedge low left) |
//                 violet tear band | coral/pink/lavender warm side; magenta
//                 pools, painterly pigment patches with pooled rims, dark rim
//                 along the tear, brushed streaks, red/orange burst haze
//   1b. drag      bristle drag: 2-9 px bristle lines along the flow each pick
//                 the wash up at a hashed upstream offset (dry-brush striation)
//   2.  drybrush  dark bristle streaks on the band, soft swaths on the sky side;
//                 gravity runs: broken vertical violet smears in the burst zone
//   3.  stream    flow-grid particles: pink specks in the sky (thrown out of
//                 the tear, bent by gravity), dark ink specks on the warm side
//   3b. dust      single-pixel spark dust around the burst
//   4.  burst     polar-grid spray thrown up out of the tear (BURST)
//   4d. explode   jittered Cartesian grid around a smeared emitter (BOOM):
//                 tumbling torn violet chunks + falling orange sparks
//   4c. slashes   fastest ink, long streaks with tails, warm-side corridor
//   4b. flakes    torn violet/magenta/ink sheet streaming along the tear
//   5.  chunks    explicit heavy particles: ink ligaments (Rayleigh-Plateau
//                 beads), dark wedge, orange vesica leaves, violet top streak,
//                 orange puffs, pale/pink flakes, landed ink drops
//   6.  drips     vertical gravity drips with a source blob and end bead
//   7.  grain     pigment granulation + film grain, sRGB out
//
// iTime animates the event on a seamless LOOP: every grid particle lives
// LIFE_RATE times per loop, travelling outwards through its cell and fading
// in/out; heavy chunks wobble along their ballistic arcs. t = 0 is scored.

#include "common.glsl"

#ifndef LOOP
#define LOOP 12.0
#endif

const float ASPECT = 1456.0 / 816.0;
const vec2  AXIS   = vec2(0.81915, 0.57358);   // 35 deg, along the tear
const vec2  PERP   = vec2(-0.57358, 0.81915);  // across, towards the sky
// The main event: a source just below the frame. Everything on the warm side
// flies radially away from it, so streak angles fan out across the image.
#ifndef MAIN_U
#define MAIN_U 0.10
#endif
#ifndef MAIN_V
#define MAIN_V -0.45
#endif
const vec2  MAIN   = vec2(MAIN_U * ASPECT, MAIN_V);

vec2 flowDir(vec2 p) { return normalize(p - MAIN); }
// fan coordinates: x = distance from MAIN (along the flight), y = arc length
// across the fan (at a reference radius of 1.2)
vec2 fanCoord(vec2 p) {
    vec2 d = p - MAIN;
    return vec2(length(d), atan(d.y, d.x) * 1.2);
}
const vec2  EMIT   = vec2(0.50 * ASPECT, 0.72); // chunk emitter (p space)
#ifndef BURST_U
#define BURST_U 0.42
#endif
#ifndef BURST_V
#define BURST_V 0.40
#endif
#ifndef LOBE_X
#define LOBE_X -0.15
#endif
#ifndef LOBE_POW
#define LOBE_POW 3.0
#endif
#ifndef BURST_FALL
#define BURST_FALL 3.0
#endif
#ifndef BURST_DENS
#define BURST_DENS 0.6
#endif
const vec2  BURST  = vec2(BURST_U * ASPECT, BURST_V); // spray emitter, on the tear

// painterly patches in the wash: fbm threshold and opacity
#ifndef PATCH_T
#define PATCH_T 0.56
#endif
#ifndef PATCH_A
#define PATCH_A 0.45
#endif

// the explosion centre in the burst zone
#ifndef BOOM_U
#define BOOM_U 0.44
#endif
#ifndef BOOM_V
#define BOOM_V 0.80
#endif
#ifndef BOOM_FALL
#define BOOM_FALL 5.0
#endif
#ifndef BOOM_DENS
#define BOOM_DENS 0.6
#endif
#ifndef BOOM_G
#define BOOM_G 7.0
#endif
const vec2  BOOM   = vec2(BOOM_U * ASPECT, BOOM_V);

#ifndef INK_DENS
#define INK_DENS 0.6
#endif

#ifndef RUNS
#define RUNS 0.7
#endif

float PX; // one pixel in p units (set in mainImage)

// ---------------------------------------------------------------------------
// region fields
// ---------------------------------------------------------------------------

// Signed distance across the tear (p space): < 0 sky, > 0 warm side.
float tearCoord(vec2 p) {
    // line through p(0.40, 0) and p(0.90, 1): about 63 deg in screen space
    const vec2 N = vec2(0.894, -0.447);
    return dot(p - vec2(0.40, 0.0), N);
}

// ---------------------------------------------------------------------------
// 1. wash
// ---------------------------------------------------------------------------
vec3 wash(vec2 p, vec2 uv, out float s) {
    // domain warp (stretched along the axis so blotches lean at 35 deg)
    vec2 ax = fanCoord(p);
    vec2 wq = vec2(ax.x * 1.8, ax.y * 2.4);
    vec2 warp = vec2(fbm(wq + 3.1, 4), fbm(wq + 11.7, 4)) - 0.5;
    vec2 w = p + 0.16 * warp;

    s = tearCoord(w);
    float v = uv.y;

    // night sky: navy, bluer towards the bottom left corner
    vec3 navy = hexColor(0x0d0d3d);
    vec3 blue = hexColor(0x0c146d);
    // the blue wedge in the lower left leans along the axis as well
    float lowA = dot(p - vec2(0.35, 0.0), PERP);          // < 0 below a 35 deg line
    vec3 night = mix(navy, blue, smoothstep(0.30, 0.08, lowA + 0.08 * warp.x));
    night = mix(night, hexColor(0x241c86), 0.7 * smoothstep(0.18, -0.02, lowA) * smoothstep(0.0, 0.2, uv.x));

    // violet haze drifting in the sky near the tear
    float hz = fbm(p * vec2(3.0, 5.0) + 50.0, 4);
    night = mix(night, hexColor(0x2c1758), 0.35 * smoothstep(0.45, 0.7, hz) * smoothstep(-0.45, -0.05, tearCoord(p)));

    // warm side, by height
    vec3 coral = hexColor(0xec4f63);
    vec3 pink  = hexColor(0xe078b6);
    vec3 lav   = hexColor(0x9658ae);
    float hv = v + 0.12 * (fbm(w * 2.5 + 7.0, 4) - 0.5);
    vec3 warm = mix(lav, pink, smoothstep(0.02, 0.22, hv));
    warm = mix(warm, coral, smoothstep(0.30, 0.52, hv + 0.08 * (uv.x - 0.7)));

    // deep magenta pools, concentrated in the upper middle-right where the
    // slashes cut through the coral
    float mag = fbm(wq * 1.5 + 21.0, 5);
    float magZone = smoothstep(0.35, 0.0, length((uv - vec2(0.70, 0.85)) * vec2(1.0, 1.4)));
    float magF = smoothstep(0.50, 0.62, mag + 0.15 * magZone);
    float magM = mix(0.12 * magF, max(magF, 0.7), magZone);
    warm = mix(warm, hexColor(0xa8246c), 0.85 * magM);

    // bottom edge sinks into violet, darker at the right corner
    warm = mix(warm, hexColor(0x8a4aa2), smoothstep(0.14, 0.0, v) * 0.7);
    warm = mix(warm, hexColor(0x6e3488), smoothstep(0.85, 1.0, uv.x) * smoothstep(0.2, 0.0, v) * 0.7);

    // painterly pigment patches: soft blotches of neighbouring pigments, each
    // with a darker pooled rim (watercolour edge darkening)
    float pn = fbm(wq * 3.5 + 61.0, 5);
    float pc = fbm(wq * 2.0 + 83.0, 3);
    float pm = smoothstep(PATCH_T, PATCH_T + 0.05, pn);
    vec3 pcol = mix(hexColor(0xd8364e), hexColor(0xf06a3e), smoothstep(0.42, 0.58, pc));      // high: red/orange
    vec3 pcolLo = mix(hexColor(0xb04ca0), hexColor(0xf090c0), smoothstep(0.42, 0.58, pc));    // low: violet/pink
    pcol = mix(pcolLo, pcol, smoothstep(0.30, 0.50, v));
    warm = mix(warm, pcol, PATCH_A * pm);
    warm *= 1.0 - 0.18 * pm * (1.0 - pm) * 4.0;

    // violet tear band; reddish-magenta higher up
    vec3 bandLo = mix(hexColor(0x4a2a90), hexColor(0x8b3d9c), smoothstep(0.0, 0.25, s));
    bandLo = mix(bandLo, hexColor(0xaf5bac), smoothstep(0.25, 0.45, s));
    vec3 bandHi = mix(hexColor(0x561f65), hexColor(0x9a2367), smoothstep(0.0, 0.25, s));
    vec3 band = mix(bandLo, bandHi, smoothstep(0.45, 0.85, v));
    float bandW = mix(0.70, 0.30, smoothstep(0.2, 0.9, v));
    // band patches: darker navy-violet and lighter lilac blotches
    float bp = fbm(wq * 4.0 + 17.0, 5);
    band = mix(band, hexColor(0x2a1e6a), 0.6 * smoothstep(0.56, 0.62, bp));
    band = mix(band, hexColor(0xa070c8), 0.4 * smoothstep(0.44, 0.38, bp));
    vec3 hot = mix(band, warm, smoothstep(bandW * 0.55, bandW, s));

    // night -> hot across the tear (soft, torn)
    float edge = smoothstep(-0.03, 0.09, s + 0.05 * (fbm(ax * vec2(4.0, 12.0), 4) - 0.5));
    vec3 col = mix(night, hot, edge);

    // pigment pooling: darker rim where the wash meets the sky and around
    // magenta pools
    float rim = exp(-pow((s - 0.02) / 0.05, 2.0));
    col *= 1.0 - 0.35 * rim;
    col *= 1.0 - 0.15 * (magM * (1.0 - magM) * 4.0) * edge;

    // brushed streaks along the axis in the warm upper half
    float st = noise(vec2(ax.x * 4.0, ax.y * 90.0)) * 0.7 + noise(vec2(ax.x * 9.0, ax.y * 200.0)) * 0.3;
    float stM = edge * smoothstep(0.45, 0.70, v) * smoothstep(0.95, 0.75, uv.x);
    col = mix(col, hexColor(0x8a2a78), stM * 0.6 * smoothstep(0.55, 0.85, st));
    col *= 1.0 + stM * 0.2 * smoothstep(0.4, 0.15, st);

    // orange pigment mist: the hot cloud of the burst, partly over the sky
    vec2 mc = vec2(0.52 * ASPECT, 0.68);
    float mist = exp(-pow(length((p - mc) * vec2(2.0, 0.75)) / 0.16, 2.0));
    float mistN = smoothstep(0.38, 0.6, fbm(w * vec2(6.0, 3.0) + 3.0, 4));
    col = mix(col, hexColor(0xd83a52), 0.45 * mist * smoothstep(-0.10, 0.05, s));   // red haze
    col = mix(col, hexColor(0xe8603a), 0.6 * mist * mistN * smoothstep(-0.18, 0.02, s));

    // large-scale tonal breathing
    col *= 0.85 + 0.3 * fbm(w * 1.8 + 40.0, 3);
    return col;
}

// Particle life cycle for a seamless loop: every grid particle travels
// outwards through its cell (ofs in -0.5..0.5) and fades in/out at the ends,
// LIFE_RATE whole lives per LOOP. Returns the opacity.
#ifndef LIFE_RATE
#define LIFE_RATE 2.0
#endif
float life(float t, float seed, out float ofs) {
    float ph = fract(t / LOOP * LIFE_RATE + seed);
    ofs = ph - 0.5;
    return smoothstep(0.0, 0.06, ph) * smoothstep(1.0, 0.94, ph);
}

// ---------------------------------------------------------------------------
// 1b. bristle drag: the wash was pushed by a brush along the flight. The brush
// is a comb of 2-9 px bristle lines along the flow; every bristle picks paint
// up at its own hashed distance upstream and drags it here, so neighbouring
// lines carry different colours (dry-brush striation, not a blur).
// ---------------------------------------------------------------------------
#ifndef DRAG
#define DRAG 2.0
#endif
float dragLen(vec2 uv, float s) {
    float sky = 1.0 - smoothstep(-0.12, 0.0, s);
    float L = mix(0.035, 0.004, sky);
    L += 0.05 * smoothstep(-0.03, 0.05, s) * smoothstep(0.45, 0.25, s);        // tear band
    L += 0.04 * smoothstep(0.55, 0.3, uv.y) * smoothstep(-0.05, 0.1, s);       // dry brush
    return L * DRAG;
}

vec3 dragWash(vec2 p, vec2 uv, out float s) {
    vec3 c0 = wash(p, uv, s);
    vec2 fq = fanCoord(p);
    float acr = fq.y * iResolution.y;                 // ~pixels across the flow
    float wb = 2.0 + 7.0 * hash11(floor(acr / 24.0) + 0.5);
    float id = floor(acr / wb);
    vec3 hb = hash33(vec3(id, wb, 7.0));
    float L = dragLen(uv, s) * mix(0.3, 1.4, hb.y);
    if (L < 0.003) return c0;
    vec2 dir = flowDir(p);
    float sd;
    vec2 pa = p - dir * L * hb.x;                     // load point
    vec2 pb = p - dir * L * hb.x * 0.45;              // trail
    vec3 ca = wash(pa, vec2(pa.x / ASPECT, pa.y), sd);
    vec3 cb = wash(pb, vec2(pb.x / ASPECT, pb.y), sd);
    return (c0 * 0.6 + ca * 1.0 + cb * 0.5) / 2.1;
}

// ---------------------------------------------------------------------------
// particle primitive
// ---------------------------------------------------------------------------
// rel: pixel - particle head, dir: unit velocity, r: radius,
// stretch: elongation of the head along dir, tail: comet tail length in radii,
// rough: torn edge amount. Returns coverage 0..1.
float drop(vec2 rel, vec2 dir, float r, float stretch, float tail, float rough, float seed) {
    float a = dot(rel, dir);
    float b = dot(rel, vec2(-dir.y, dir.x));
    // head: ellipse
    vec2 q = vec2(a / stretch, b);
    float d = length(q) - r;
    // tail: tapered segment behind the head
    if (tail > 0.0 && a < 0.0) {
        float L = tail * r;
        float h = clamp(-a / L, 0.0, 1.0);
        float dt = length(vec2(a + h * L, b)) - r * 0.55 * (1.0 - h);
        d = min(d, dt);
    }
    if (rough > 0.0) {
        d += rough * r * (fbm(rel / r * 1.3 + seed * 17.0, 3) - 0.5) * 1.4;
    }
    float aa = PX * 0.8;
    return smoothstep(aa, -aa, d);
}

// power-law radius: many tiny, few large
float powerSize(float h, float rmin, float rmax, float alpha) {
    return min(rmin * pow(max(1.0 - h, 1e-4), -1.0 / alpha), rmax);
}

// ---------------------------------------------------------------------------
// 3. stream particles (rotated grid along the 35 deg axis)
// ---------------------------------------------------------------------------
void streamLayer(inout vec3 col, vec2 p, float cell, float seed, float t) {
    vec2 q = vec2(dot(p, AXIS), dot(p, PERP));
    vec2 g = vec2(cell * 2.0, cell);         // cells are longer along the axis
    vec2 qq = q / g;
    vec2 id0 = floor(qq);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        vec3 h = hash33(vec3(id, seed));
        vec3 h2 = hash33(vec3(id, seed + 7.3));
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        vec2 cq = (id + 0.15 + 0.7 * h.xy + vec2(0.7 * ofs, 0.0)) * g;
        vec2 cp = cq.x * AXIS + cq.y * PERP;          // back to p space
        vec2 cuv = vec2(cp.x / ASPECT, cp.y);
        if (cuv.x < -0.05 || cuv.x > 1.05 || cuv.y < -0.05 || cuv.y > 1.05) continue;

        float s = tearCoord(cp);
        float warm = smoothstep(-0.02, 0.10, s);
        // density by origin: sparse in the sky, dense on the warm side,
        // thinner on the coral top right
        float dens = mix(0.07 * (0.3 + 0.7 * smoothstep(0.0, 0.35, cuv.y)), INK_DENS, warm);
        dens *= mix(1.0, 0.55, smoothstep(0.5, 0.9, cuv.y) * smoothstep(0.75, 0.95, cuv.x));
        if (h.z > dens) continue;

        float r = powerSize(h2.x, cell * 0.05, cell * mix(0.30, 0.28, warm), mix(2.0, 2.6, warm));
        // velocity: along the axis with scatter; speed -> stretch + tail
        float ang = (h2.y - 0.5) * mix(1.0, 0.7, warm);
        float speed = h2.z * h2.z;
        // warm side: flying along the axis; sky: thrown out of the tear
        // (perpendicular to it), then bent down by gravity
        vec2 skyV = normalize(rot(ang) * PERP - vec2(0.0, 0.25 + 0.3 * (1.0 - speed)));
        vec2 dir = normalize(mix(skyV, rot(ang) * flowDir(cp), warm));
        // late, slow drops landing on the pink lower right: round, no tail
        float slow = smoothstep(0.45, 0.2, cuv.y) * smoothstep(0.55, 0.75, cuv.x);
        speed *= 1.0 - 0.85 * slow;
        float stretch = 1.0 + mix(0.8, 1.2, warm) * speed;
        float tail = speed > 0.6 ? 6.0 * speed : 0.0;
        float cov = drop(p - cp, dir, r, stretch, tail, 0.6 * step(cell * 0.2, r), h.x);
        if (cov <= 0.0) continue;

        // colour by origin: pink flakes in the sky, dark ink on the warm side
        vec3 skyC = mix(hexColor(0xe8459f), hexColor(0xf27cc4), h.y);
        vec3 inkC = mix(hexColor(0x1e1446), hexColor(0x3a1a62), h.y);
        vec3 pc = mix(skyC, inkC, warm);
        col = mix(col, pc, cov * fade * mix(0.9, 0.85, warm));
    }
}

// ---------------------------------------------------------------------------
// 3b. dust: the finest, unresolved droplets of the burst (single pixels)
// ---------------------------------------------------------------------------
void dustLayer(inout vec3 col, vec2 p, float t) {
    vec2 g = p / 0.0045;
    vec2 id = floor(g);
    vec3 h = hash33(vec3(id, 77.0));
    vec2 c = (id + 0.2 + 0.6 * h.xy) * 0.0045;
    // density: a halo around the burst, a thin sprinkle elsewhere in the sky
    float dB = length((c - BURST - vec2(0.0, 0.25)) * vec2(0.8, 0.9));
    float s = tearCoord(c);
    float dens = 0.10 * exp(-dB * dB / 0.05) + 0.008 * smoothstep(0.1, -0.1, s);
    if (h.z > dens) return;
    float r = PX * mix(0.6, 1.6, fract(h.z * 91.7));
    float cov = smoothstep(r + PX, r - PX * 0.5, length(p - c));
    vec3 dc = fract(h.x * 13.1) > 0.5 ? hexColor(0xf07a3a) : hexColor(0xe58ac0);
    col = mix(col, dc, cov * (0.55 + 0.25 * sin(t * TAU / LOOP * 4.0 + h.y * 30.0)));
}

// ---------------------------------------------------------------------------
// 4. burst particles (polar grid around the emitter)
// ---------------------------------------------------------------------------
// E: emitter, cone: 1 = upward cone only, 0 = isotropic explosion,
// fall: density falloff with distance, densK: density scale,
// rmax: largest droplet radius, core: radius of the unresolved core
void burstLayer(inout vec3 col, vec2 p, vec2 E, float nAng, float nRad, float seed, float t,
                float cone, float fall, float densK, float rmax, float core) {
    vec2 d = p - E;
    float r = max(length(d), 1e-3);
    float a = atan(d.y, d.x);
    float lr = log(r);
    vec2 qq = vec2(a / TAU * nAng, lr * nRad);
    vec2 id0 = floor(qq);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        id.x = mod(id.x, nAng);
        vec3 h = hash33(vec3(id, seed));
        vec3 h2 = hash33(vec3(id, seed + 3.7));
        float pa = (id.x + 0.1 + 0.8 * h.x) / nAng * TAU;
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        float pr = exp((id.y + 0.15 + 0.7 * h.y + 0.7 * ofs) / nRad);
        vec2 dir = vec2(cos(pa), sin(pa));
        vec2 cp = E + pr * dir;

        // emission lobe: mostly up and along the axis, fades with distance
        // emission cone: the spray is thrown upwards out of the tear
        float up = max(dot(dir, normalize(vec2(LOBE_X, 1.0))), 0.0);
        float lobe = mix(1.0, 0.08 + 0.92 * pow(up, LOBE_POW), cone);
        float dens = lobe * exp(-pr * fall) * densK;
        dens *= smoothstep(core * 0.4, core, pr);   // the core is a blur of paint, not dots
        if (h.z > dens) continue;

        float cellSz = pr * TAU / nAng;      // physical size grows with r
        float rad = powerSize(h2.x, min(cellSz * 0.035, 0.0015), min(cellSz * 0.17, rmax), 1.8);
        // ballistic: gravity bends the velocity downwards with flight time
        // (flight time ~ distance), so far particles streak towards vertical
        vec2 vdir = normalize(rot((h2.y - 0.5) * 0.5) * dir - vec2(0.0, 8.0 * pr * pr + 2.0 * pr));
        float speed = h2.z;
        float stretch = 1.0 + 3.0 * speed;
        float tail = speed > 0.5 ? 5.0 * speed : 0.0;
        float rough = step(cellSz * 0.12, rad) * 0.9;
        float cov = drop(p - cp, vdir, rad, stretch, tail, rough, h.x + seed);
        if (cov <= 0.0) continue;

        // colour by origin: hot orange core, violet/pink flakes further out
        float hc = fract(h.x * 7.13 + h.y * 3.1);
        // hot pigment cools from yellow-orange to deep red-orange
        vec3 c = mix(hexColor(0xd8402a), hexColor(0xf8a050), h2.x * h2.x + 0.3 * h.y);
        if (hc > 0.62) c = hexColor(0xf0662a);
        if (hc > 0.80) c = hexColor(0x8b3d9c);
        if (hc > 0.92) c = hexColor(0xe076b0);
        // pigment is uneven inside a flake; hot sparks glow
        float tex = 0.7 + 0.3 * noise((p - cp) / rad * 1.5 + h.xy * 50.0);
        cov *= fade;
        col = mix(col, c, cov * tex * mix(0.6, 0.95, h2.y));
        if (hc <= 0.80) {
            float gl = exp(-length(p - cp) / (rad * 3.0));
            col += c * 0.12 * gl * (1.0 - cov);
        }
    }
}

// ---------------------------------------------------------------------------
// 4d. explosion: torn chunks and sparks in the burst zone. Laid out on a
// jittered Cartesian grid (no visible rings or rays); each particle flies away
// from a smeared emitter BOOM, bent down by gravity; big chunks tumble.
// ---------------------------------------------------------------------------
void explodeLayer(inout vec3 col, vec2 p, float cell, float seed, float t, float densK, float rmax) {
    vec2 id0 = floor(p / cell);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        vec3 h = hash33(vec3(id, seed));
        vec3 h2 = hash33(vec3(id, seed + 4.1));
        // velocity away from a smeared emitter (+-0.08 around BOOM)
        vec2 src = BOOM + (h2.yz - 0.5) * 0.16;
        vec2 base = (id + 0.15 + 0.7 * h.xy) * cell;
        vec2 v0 = normalize(base - src + 1e-4);
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        vec2 cp = base + v0 * ofs * cell * 0.7;

        // explosion envelope: wider than tall, sitting on the upper tear
        vec2 e = (cp - BOOM) * vec2(0.75 / ASPECT * 1.784, 1.0);
        float r = length(e);
        float dens = densK * exp(-r * BOOM_FALL) * smoothstep(0.02, 0.08, r);
        dens *= smoothstep(-0.35, -0.05, tearCoord(cp));        // mostly over the sky side
        if (h.z > dens) continue;

        float rad = powerSize(h2.x, cell * 0.06, rmax, 1.6);
        float big = smoothstep(rmax * 0.4, rmax * 0.8, rad);
        // gravity bends the flight downwards with distance; big chunks tumble
        vec2 vdir = normalize(v0 - vec2(0.0, BOOM_G * r));
        vdir = normalize(mix(vdir, vec2(cos(h.y * TAU), sin(h.y * TAU)), big * 0.8));
        float speed = h2.y;
        float cov = drop(p - cp, vdir, rad, 1.0 + 2.0 * speed * (1.0 - big), (1.0 - big) * step(0.6, speed) * 6.0 * speed,
                         mix(0.4, 1.1, big), h.x + seed);
        if (cov <= 0.0) continue;

        // big, heavy chunks are torn violet sheet; small ones are hot sparks
        float hc = fract(h.x * 5.77 + h.y * 1.3);
        hc = big > 0.25 ? 0.67 + 0.3 * hc : hc;
        vec3 c = mix(hexColor(0xd8402a), hexColor(0xf8a050), h2.x * 0.6 + 0.4 * h.y);   // hot orange
        if (hc > 0.50) c = hexColor(0xf0662a);
        if (hc > 0.66) c = mix(hexColor(0x6a3aa8), hexColor(0x8b3d9c), h.y);          // violet
        if (hc > 0.84) c = hexColor(0xc83c8c);                                          // magenta
        if (hc > 0.94) c = hexColor(0xf08ac0);                                          // pink
        float tex = 0.65 + 0.35 * noise((p - cp) / rad * 1.3 + h.xy * 50.0);
        col = mix(col, c, cov * fade * tex * mix(0.55, 0.95, h2.z));
        if (hc <= 0.66) col += c * 0.10 * exp(-length(p - cp) / (rad * 2.5)) * (1.0 - cov) * fade;
    }
}

// ---------------------------------------------------------------------------
// 5. chunks: explicit heavy ballistic particles
// ---------------------------------------------------------------------------
// launch from the emitter with velocity v (p units per unit time) under weak
// gravity; position at flight time T
vec2 ballistic(vec2 v, float T) {
    return EMIT + v * T + vec2(0.0, -0.05) * T * T;
}

void chunk(inout vec3 col, vec2 p, vec2 pos, vec2 dir, float r, float stretch, float tail,
           float rough, vec3 c, float alpha, float seed) {
    float cov = drop(p - pos, normalize(dir), r, stretch, tail, rough, seed);
    col = mix(col, c, cov * alpha);
}

// A ligament: a fast sheet of ink stretched between two points, breaking up
// into beads (Rayleigh-Plateau). Width w, bead count n.
void jet(inout vec3 col, vec2 p, vec2 a, vec2 b, float w, float n, vec3 c, float alpha, float seed) {
    vec2 ab = b - a;
    float L = length(ab);
    vec2 dir = ab / L;
    vec2 rel = p - a;
    float x = clamp(dot(rel, dir) / L, 0.0, 1.0);
    float y = dot(rel, vec2(-dir.y, dir.x));
    // beads: width oscillates along the ligament, tapering at both ends
    float bead = 0.35 + 0.65 * pow(noise(vec2(x * n, seed)), 1.5) * 1.6;
    float taper = smoothstep(0.0, 0.12, x) * smoothstep(1.0, 0.75, x);
    float ww = w * bead * (0.3 + 0.7 * taper);
    float d = abs(y + 0.25 * w * (noise(vec2(x * n * 3.0, seed + 4.0)) - 0.5)) - ww;
    float along = dot(rel, dir);
    d = max(d, max(-along, along - L));
    float cov = smoothstep(PX, -PX, d);
    col = mix(col, c, cov * alpha);
}

// Vesica distance (Inigo Quilez): a pointed leaf along +y, half-length
// sqrt(r^2 - d^2), half-width r - d.
float sdVesica(vec2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b) ? length(p - vec2(0.0, b)) : length(p - vec2(-d, 0.0)) - r;
}

// A torn orange leaf: a heavy, flat flake tumbling slowly; lit rim, darker
// pigment in the middle, ragged edge.
void leaf(inout vec3 col, vec2 p, vec2 pos, float ang, float len, float wid, float seed) {
    vec2 q = rot(-ang) * (p - pos);
    // vesica with half-length len and half-width wid
    float d0 = (len * len - wid * wid) / (2.0 * wid);
    float r = d0 + wid;
    float d = sdVesica(q, r, d0);
    d += wid * 0.5 * (fbm(q / wid * 1.5 + seed, 3) - 0.5);
    float cov = smoothstep(PX, -PX, d);
    float rim = smoothstep(-wid * 0.6, 0.0, d);
    vec3 c = mix(hexColor(0xe0582c), hexColor(0xf8a070), rim * 0.8 + 0.2 * (q.y / len));
    col = mix(col, c, cov * 0.92);
}

// A puff: a slow, heavy cloud of pigment that smeared along its flight;
// soft gaussian body broken up by fbm.
void puff(inout vec3 col, vec2 p, vec2 pos, vec2 dir, float len, float wid, vec3 c, float alpha, float seed) {
    dir = normalize(dir);
    vec2 rel = p - pos;
    vec2 q = vec2(dot(rel, dir) / len, dot(rel, vec2(-dir.y, dir.x)) / wid);
    float body = exp(-dot(q, q) * 1.5);
    float brk = smoothstep(0.35, 0.65, fbm(vec2(q.x * 2.0, q.y * 5.0) + seed, 4));
    col = mix(col, c, alpha * body * brk);
}

// a heavy particle launched from EMIT with velocity v, seen at flight time T,
// oriented along the main flow
void fling(inout vec3 col, vec2 p, vec2 v, float T, float r, float stretch, float tail,
           float rough, vec3 c, float alpha, float seed) {
    vec2 pos = ballistic(v, T);
    chunk(col, p, pos, flowDir(pos), r, stretch, tail, rough, c, alpha, seed);
}

void chunkLayer(inout vec3 col, vec2 p, float t) {
    float T = 1.0 + 0.04 * sin(t * TAU / LOOP);
    vec3 ink = hexColor(0x140c30);
    vec3 orange = hexColor(0xf07a3a);
    float sh = 0.02 * sin(t * TAU / LOOP);
    // main ligament: the long dark slash through the coral
    jet(col, p, vec2(0.56 * ASPECT + sh, 0.54), vec2(0.86 * ASPECT + sh, 0.97), 0.010, 14.0, ink, 0.9, 1.0);
    jet(col, p, vec2(0.50 * ASPECT, 0.47), vec2(0.66 * ASPECT, 0.66), 0.006, 9.0, hexColor(0x2a1858), 0.8, 2.0);
    jet(col, p, vec2(0.66 * ASPECT, 0.80), vec2(0.80 * ASPECT, 1.02), 0.007, 8.0, hexColor(0x3a1050), 0.7, 3.0);
    // dark wedge in the top right: a heavy, torn chunk
    chunk(col, p, vec2(0.86 * ASPECT, 0.88), flowDir(vec2(0.86 * ASPECT, 0.88)), 0.034, 2.6, 1.5, 0.45, hexColor(0x4a1048), 0.65, 12.0);
    // dark slashes on the warm side: fast, thin ink jets along the axis
    fling(col, p, vec2(0.32, 0.13), T, 0.008, 9.0, 22.0, 0.5, ink, 0.9, 1.0);
    fling(col, p, vec2(0.18, -0.07), T, 0.007, 7.0, 18.0, 0.5, ink, 0.85, 2.0);
    fling(col, p, vec2(0.50, 0.23), T, 0.010, 6.0, 14.0, 0.6, ink, 0.85, 3.0);
    fling(col, p, vec2(0.13, -0.17), T, 0.005, 6.0, 20.0, 0.4, ink, 0.8, 4.0);
    fling(col, p, vec2(0.42, 0.02), T, 0.009, 2.2, 6.0, 0.5, hexColor(0x3a3a9a), 0.8, 10.0);
    // orange leaves below the emitter
    float tumble = 0.15 * sin(t * TAU / LOOP);
    leaf(col, p, ballistic(vec2(-0.05, -0.34), T), -0.85 + tumble, 0.052, 0.024, 5.0);
    leaf(col, p, ballistic(vec2(0.07, -0.33), T), -0.45 - tumble, 0.048, 0.020, 6.0);
    // violet streak at the very top
    chunk(col, p, ballistic(vec2(0.0, 0.28), T), vec2(0.05, 1.0), 0.030, 2.2, 3.0, 0.6, hexColor(0x6a3aa8), 0.85, 7.0);
    // violet comet rising into the sky, long tail behind it
    chunk(col, p, vec2(0.36 * ASPECT, 0.77), vec2(0.25, 1.0), 0.007, 1.8, 36.0, 0.3, hexColor(0x6a35a8), 0.7, 13.0);
    // slow orange puffs drifting out of the burst into the sky
    vec3 hot = hexColor(0xe8602c);
    puff(col, p, vec2(0.345 * ASPECT, 0.80), vec2(0.35, 1.0), 0.07, 0.025, hot, 0.6, 20.0);
    puff(col, p, vec2(0.40 * ASPECT, 0.95), vec2(0.2, 1.0), 0.05, 0.02, hot, 0.7, 22.0);
    puff(col, p, vec2(0.27 * ASPECT, 0.70), vec2(1.0, 0.6), 0.05, 0.015, hot, 0.45, 23.0);
    // pale flake caught at the very top right
    chunk(col, p, vec2(0.905 * ASPECT, 0.99), vec2(1.0, 0.25), 0.022, 2.0, 0.0, 0.4, hexColor(0xf4c0dc), 0.9, 16.0);
    // heavy ink drops that landed on the pink lower right
    chunk(col, p, vec2(0.792 * ASPECT, 0.205), vec2(0.3, 1.0), 0.020, 1.7, 0.0, 0.4, hexColor(0x6a1848), 0.85, 14.0);
    chunk(col, p, vec2(0.985 * ASPECT, 0.15), vec2(0.6, 1.0), 0.030, 1.3, 0.0, 0.4, hexColor(0x241034), 0.9, 15.0);
    // pink flakes in the sky
    chunk(col, p, vec2(0.085 * ASPECT, 0.46), vec2(1.0, 0.3), 0.014, 1.3, 0.0, 1.0, hexColor(0xe87ab8), 0.9, 8.0);
    chunk(col, p, vec2(0.245 * ASPECT, 0.92), vec2(1.0, 0.3), 0.012, 1.2, 0.0, 1.0, hexColor(0xf0a0c8), 0.9, 9.0);
}

// ---------------------------------------------------------------------------
// 4c. slash jets: the fastest ink, torn into long streaks along the flow
// ---------------------------------------------------------------------------
void slashLayer(inout vec3 col, vec2 p, float cell, float seed, float t) {
    vec2 q = fanCoord(p);
    vec2 g = vec2(cell * 4.0, cell);              // long cells along the flight
    vec2 qq = q / g;
    vec2 id0 = floor(qq);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        vec3 h = hash33(vec3(id, seed));
        vec3 h2 = hash33(vec3(id, seed + 2.9));
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        vec2 cq = (id + 0.2 + 0.6 * h.xy + vec2(0.7 * ofs, 0.0)) * g;
        float th = cq.y / 1.2;
        vec2 cp = MAIN + cq.x * vec2(cos(th), sin(th));
        vec2 cuv = vec2(cp.x / ASPECT, cp.y);
        // slash zone: a corridor on the warm side of the tear, upper half
        float sz = tearCoord(cp);
        float zone = smoothstep(0.12, 0.25, sz) * smoothstep(0.65, 0.45, sz)
                   * smoothstep(0.30, 0.55, cuv.y);
        if (h.z > 0.6 * zone) continue;
        float r = powerSize(h2.x, cell * 0.06, cell * 0.30, 1.5);
        vec2 dir = flowDir(cp);
        float cov = drop(p - cp, dir, r, 2.0 + 4.0 * h2.y, 6.0 + 14.0 * h2.z, 0.5, h.x + seed);
        if (cov <= 0.0) continue;
        vec3 c = h2.y > 0.3 ? hexColor(0x150c32) : hexColor(0x3c2a8a);
        col = mix(col, c, cov * fade * mix(0.55, 0.9, h.y));
    }
}

// ---------------------------------------------------------------------------
// 4b. tear flakes: the main sheet of torn pigment streaming along the tear
// ---------------------------------------------------------------------------
void flakeLayer(inout vec3 col, vec2 p, float cell, float seed, float t) {
    vec2 q = vec2(dot(p, AXIS), dot(p, PERP));
    vec2 g = vec2(cell * 2.0, cell);
    vec2 qq = q / g;
    vec2 id0 = floor(qq);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        vec3 h = hash33(vec3(id, seed));
        vec3 h2 = hash33(vec3(id, seed + 5.1));
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        vec2 cq = (id + 0.15 + 0.7 * h.xy + vec2(0.7 * ofs, 0.0)) * g;
        vec2 cp = cq.x * AXIS + cq.y * PERP;
        vec2 cuv = vec2(cp.x / ASPECT, cp.y);
        float s = tearCoord(cp);
        // band around the tear, widening downwards; near the emitter it
        // merges with the burst
        float bw = mix(0.30, 0.16, cuv.y);
        float band = smoothstep(bw * 0.8, 0.0, abs(s - bw * 0.6));
        float dens = 0.9 * band * mix(1.0, 0.3, smoothstep(0.45, 0.7, cuv.y));
        if (h.z > dens) continue;

        float r = powerSize(h2.x, cell * 0.08, cell * 0.42, 1.6);
        vec2 dir = rot((h2.y - 0.5) * 0.35) * flowDir(cp);
        float speed = h2.z;
        float cov = drop(p - cp, dir, r, 1.3 + 2.5 * speed, 4.0 * speed, 1.0, h.x + seed);
        if (cov <= 0.0) continue;

        float hc = fract(h.x * 5.31 + h.y * 2.7);
        // low on the tear the sheet is blue-violet, higher up magenta
        float hi = smoothstep(0.25, 0.65, cuv.y);
        vec3 c = mix(hexColor(0x4a2c98), hexColor(0x5b2689), hi);
        if (hc > 0.40) c = mix(hexColor(0x6a3aa8), hexColor(0x8b3d9c), hi);
        if (hc > 0.62) c = mix(hexColor(0x8a4cb0), hexColor(0xaf5bac), hi);
        if (hc > 0.72) c = mix(hexColor(0x5a3aa0), hexColor(0xc82c66), hi);
        if (hc > 0.78) c = hexColor(0x1c1648);   // dark ink torn from the sky
        if (hc > 0.92) c = hexColor(0x2e2a8a);
        // orange where the sheet passes the burst
        float nearE = smoothstep(0.35, 0.1, length(cp - EMIT));
        if (h2.y < 0.25 * nearE) c = hexColor(0xf0662a);
        col = mix(col, c, cov * fade * mix(0.6, 0.95, h.y) * (0.7 + 0.3 * noise((p - cp) / r * 1.5 + h.xy * 40.0)));
    }
}

// ---------------------------------------------------------------------------
// 6. drips
// ---------------------------------------------------------------------------
// A drip: pigment that landed and ran straight down under gravity.
// (u, v top, length, width px); tint multiplies the paint underneath,
// or, if paint.a > 0, the drip carries its own pigment.
void drip(inout vec3 col, vec2 p, vec4 d, vec3 tint, float alpha, vec4 paint) {
    float x = d.x * ASPECT + 0.004 * sin(p.y * 11.0 + d.x * 40.0);
    float w = PX * d.w * (0.6 + 0.4 * smoothstep(d.y - d.z, d.y, p.y)); // thins downwards
    float m = smoothstep(w, w * 0.3, abs(p.x - x));
    m *= smoothstep(d.y + 0.01, d.y - 0.02, p.y) * smoothstep(d.y - d.z, d.y - d.z + 0.08, p.y);
    // the blob the drip runs out of, and a bead at its lower end
    float hr = PX * d.w * 1.6;
    m = max(m, smoothstep(hr, hr * 0.5, length(p - vec2(x, d.y - 0.01))));
    m = max(m, smoothstep(hr * 0.7, hr * 0.3, length(p - vec2(x, d.y - d.z + 0.07))));
    vec3 target = paint.a > 0.0 ? paint.rgb : col * tint;
    col = mix(col, target, m * alpha);
}

void drip(inout vec3 col, vec2 p, vec4 d, vec3 tint, float alpha) {
    drip(col, p, d, tint, alpha, vec4(0.0));
}

void dripLayer(inout vec3 col, vec2 p, vec2 uv) {
    vec3 light = vec3(1.25, 1.1, 1.35);
    vec3 dark = vec3(0.45, 0.3, 0.6);
    drip(col, p, vec4(0.800, 0.48, 0.45, 3.0), light, 0.7);
    drip(col, p, vec4(0.872, 0.40, 0.42, 4.0), light, 0.6);
    drip(col, p, vec4(0.920, 0.30, 0.30, 2.5), light, 0.5);
    drip(col, p, vec4(0.600, 0.28, 0.28, 3.0), dark, 0.6);
    drip(col, p, vec4(0.553, 0.31, 0.12, 2.5), vec3(1.6, 0.9, 0.5), 0.8);
    drip(col, p, vec4(0.500, 1.00, 0.35, 3.0), vec3(1.6, 1.0, 2.2), 0.5);
    drip(col, p, vec4(0.420, 0.95, 0.30, 2.0), vec3(1.5, 0.8, 0.6), 0.5);
    drip(col, p, vec4(0.700, 0.62, 0.30, 2.0), dark, 0.5);
    drip(col, p, vec4(0.050, 0.90, 0.20, 1.5), vec3(1.0), 0.5, vec4(hexColor(0xc04070), 1.0));
}

// ---------------------------------------------------------------------------
// 2. dry brush: unresolved spray streaks along the axis
// ---------------------------------------------------------------------------
float dryBrush(vec2 p) {
    vec2 q = fanCoord(p);
    float n = noise(vec2(q.x * 4.0, q.y * 110.0)) * 0.6 + noise(vec2(q.x * 10.0, q.y * 300.0)) * 0.4;
    return n;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = vec2(uv.x * ASPECT, uv.y);
    PX = 1.0 / iResolution.y;
    float t = mod(iTime, LOOP);

    // 1. wash
    float s;
    vec3 col = dragWash(p, uv, s);

    // 2. dry brush: dark bristle streaks on both sides of the tear, lower half
    float db = dryBrush(p);
    float dbM = smoothstep(-0.10, 0.0, s) * smoothstep(0.75, 0.25, s) * smoothstep(0.75, 0.25, uv.y);
    float dark = smoothstep(0.55, 0.8, db);
    col = mix(col, hexColor(0x241a5a), dark * dbM * 0.45);
    // on the sky side the same spray is unresolved: broad, soft dark swaths
    vec2 fq = vec2(dot(p, AXIS), dot(p, PERP));
    float sw = noise(vec2(fq.x * 3.0, fq.y * 40.0)) * 0.7 + noise(vec2(fq.x * 7.0, fq.y * 90.0)) * 0.3;
    float swM = smoothstep(-0.45, -0.1, s) * smoothstep(0.02, -0.08, s) * smoothstep(0.6, 0.1, uv.y);
    col *= 1.0 - 0.55 * smoothstep(0.5, 0.75, sw) * swM;
    col *= 1.0 + 0.35 * smoothstep(0.4, 0.2, sw) * swM;
    col *= 1.0 + 0.25 * smoothstep(0.45, 0.2, db) * dbM * smoothstep(-0.05, 0.1, s);

    // 2b. gravity runs: pigment from the burst running down (vertical)
    float run = noise(vec2(p.x * 160.0, p.y * 3.0)) * 0.6 + noise(vec2(p.x * 420.0, p.y * 6.0)) * 0.4;
    float runM = smoothstep(0.12, 0.0, abs(uv.x - 0.38) - 0.12) * smoothstep(0.45, 0.85, uv.y);
    float runF = smoothstep(0.3, 0.7, fbm(p * 3.0 + 9.0, 3));
    col *= 1.0 + 0.3 * (run - 0.5) * runM * runF;
    // where pigment collected, it runs down as violet/magenta streaks
    float runW = noise(vec2(p.x * 70.0, p.y * 2.0 + 5.0));
    float runP = smoothstep(0.66, 0.85, runW) * runM * runF;
    runP *= smoothstep(0.45, 0.7, noise(vec2(p.x * 70.0 + 3.0, p.y * 7.0)));   // broken lengths
    vec3 runC = mix(hexColor(0x4a2a88), hexColor(0x9a3a8a), noise(vec2(p.x * 60.0, 1.0)));
    col = mix(col, runC, RUNS * runP);

    // 3-6. particles
    streamLayer(col, p, 0.035, 1.0, t);
    streamLayer(col, p, 0.016, 2.0, t);
    streamLayer(col, p, 0.009, 3.0, t);
    dustLayer(col, p, t);
    flakeLayer(col, p, 0.06, 21.0, t);
    flakeLayer(col, p, 0.03, 22.0, t);
    flakeLayer(col, p, 0.016, 23.0, t);
    // spray thrown up out of the tear
    burstLayer(col, p, BURST, 22.0, 5.0, 11.0, t, 1.0, BURST_FALL, BURST_DENS, 0.011, 0.28);
    burstLayer(col, p, BURST, 44.0, 10.0, 12.0, t, 1.0, BURST_FALL, BURST_DENS, 0.011, 0.28);
    burstLayer(col, p, BURST, 90.0, 20.0, 13.0, t, 1.0, BURST_FALL, BURST_DENS, 0.011, 0.28);
    // the explosion itself: torn chunks and a dense cloud of sparks
    explodeLayer(col, p, 0.065, 14.0, t, BOOM_DENS * 0.9, 0.026);
    explodeLayer(col, p, 0.022, 15.0, t, BOOM_DENS * 0.4, 0.007);
    explodeLayer(col, p, 0.010, 16.0, t, BOOM_DENS * 0.5, 0.0025);
    slashLayer(col, p, 0.03, 31.0, t);
    chunkLayer(col, p, t);
    dripLayer(col, p, uv);

    // 7. grain
    // paper / pigment granulation, then film grain
    float gran = fbm(fragCoord * 0.35, 3);
    col *= 0.9 + 0.2 * gran;
    col *= 1.0 + 0.08 * (hash12(fragCoord + 0.37) - 0.5);
    fragColor = vec4(linearToSrgb(col), 1.0);
}
