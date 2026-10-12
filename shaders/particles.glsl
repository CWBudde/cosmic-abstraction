// particles.glsl - foreground particles, skipped with -D BG_ONLY=1:
//   P2  burst plume    Rival C's ballistic chunks, flakes and sparks (looped)
//   P3  sky specks     clumped pink flakes, hair scratches, hand-placed flakes
//   P4  hero chunks    orange glow, orange flame leaves, violet burst streak,
//                      dark drop
//   P5  ink specks     larger flung ink specks (inkSpecks, in marks.glsl)

// ---- P2: burst plume (particle model from Rival C) -------------------------------
// Every chunk and spark is a particle flying away from a smeared emitter BOOM,
// bent down by gravity; big chunks tumble. Shapes are comet-tailed ellipses
// with torn edges (drop), sizes follow a power law (many tiny, few big) and
// every particle lives LIFE_RATE times per LOOP, so the plume loops seamlessly.
#ifndef LOOP
#define LOOP 12.0
#endif
#ifndef LIFE_RATE
#define LIFE_RATE 2.0
#endif
#ifndef BOOM_DENS
#define BOOM_DENS 1.3
#endif
#ifndef BOOM_FALL
#define BOOM_FALL 7.0
#endif
#ifndef BOOM_G
#define BOOM_G 14.0
#endif
const vec2 BOOM = vec2(0.785, 0.80);         // explosion centre, R(640, 163)

// Seamless particle life: travel offset ofs in -0.5..0.5, fade at both ends.
float life(float t, float seed, out float ofs) {
    float ph = fract(t / LOOP * LIFE_RATE + seed);
    ofs = ph - 0.5;
    return smoothstep(0.0, 0.06, ph) * smoothstep(1.0, 0.94, ph);
}

// rel: pixel - particle head, dir: unit velocity, r: radius, stretch: head
// elongation along dir, tail: comet tail length in radii, rough: torn edge.
float drop(vec2 rel, vec2 dir, float r, float stretch, float tail, float rough, float seed) {
    float a = dot(rel, dir);
    float b = dot(rel, vec2(-dir.y, dir.x));
    float d = length(vec2(a / stretch, b)) - r;
    if (tail > 0.0 && a < 0.0) {
        float L = tail * r;
        float h = clamp(-a / L, 0.0, 1.0);
        d = min(d, length(vec2(a + h * L, b)) - r * 0.55 * (1.0 - h));
    }
    if (rough > 0.0 && d < r * 0.8)
        d += rough * r * (0.65 * noise(rel / r * 1.3 + seed * 17.0) + 0.35 * noise(rel / r * 2.9 + seed * 5.0) - 0.5) * 1.4;
    return smoothstep(PX * 0.8, -PX * 0.8, d);
}

// Power-law radius: many tiny, few large.
float powerSize(float h, float rmin, float rmax, float alpha) {
    return min(rmin * pow(max(1.0 - h, 1e-4), -1.0 / alpha), rmax);
}

void explodeLayer(inout vec3 col, vec2 p, float cell, float seed, float t, float densK, float rmax) {
    vec2 id0 = floor(p / cell);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        vec2 id = id0 + vec2(i, j);
        vec3 h = hash33(vec3(id, seed));
        vec2 base = (id + 0.15 + 0.7 * h.xy) * cell;
        // cheap envelope reject on the rest position (the particle moves < 1 cell)
        if (h.z > densK * exp(-max(length((base - BOOM) * vec2(0.75, 1.0)) - cell, 0.0) * BOOM_FALL)) continue;
        vec3 h2 = hash33(vec3(id, seed + 4.1));
        vec2 src = BOOM + (h2.yz - 0.5) * 0.16;           // smeared emitter
        vec2 v0 = normalize(base - src + 1e-4);
        float ofs;
        float fade = life(t, fract(h.x * 31.7 + h.z * 7.3), ofs);
        vec2 cp = base + v0 * ofs * cell * 0.7;

        // envelope: wider than tall, on the sky side of the upper tear
        vec2 e = (cp - BOOM) * vec2(0.75, 1.0);
        float r = length(e);
        float dens = densK * exp(-r * BOOM_FALL) * smoothstep(0.02, 0.08, r);
        float tc = tearCoord(cp);
        dens *= smoothstep(-0.35, -0.02, tc) * smoothstep(0.2, -0.05, tc);
        if (h.z > dens) continue;

        float rad = powerSize(h2.x, cell * 0.06, rmax, 1.6);
        float big = smoothstep(rmax * 0.4, rmax * 0.8, rad);
        vec2 vdir = normalize(v0 - vec2(0.0, BOOM_G * r));          // gravity
        vdir = normalize(mix(vdir, vec2(cos(h.y * TAU), sin(h.y * TAU)), big * 0.8));  // tumble
        float speed = h2.y;
        float stretch = 1.0 + 4.0 * speed * (1.0 - big);           // slivers
        float tail = (1.0 - big) * step(0.6, speed) * 6.0 * speed;
        if (length(p - cp) > rad * (stretch + tail + 1.5) + 2.0 * PX) continue;
        float cov = drop(p - cp, vdir, rad, stretch, tail, mix(0.4, 1.1, big), h.x + seed);
        if (cov <= 0.0) continue;

        // big heavy chunks are torn violet sheet, small ones hot orange sparks
        float hc = fract(h.x * 5.77 + h.y * 1.3);
        hc = big > 0.25 ? 0.67 + 0.3 * hc : hc;
        vec3 c = mix(hexColor(0xd8402a), hexColor(0xf8a050), h2.x * 0.6 + 0.4 * h.y);
        if (hc > 0.50) c = hexColor(0xf0662a);
        if (hc > 0.66) c = mix(hexColor(0x6a3aa8), hexColor(0x8b3d9c), h.y);
        if (hc > 0.84) c = hexColor(0xc83c8c);
        if (hc > 0.94) c = hexColor(0xf08ac0);
        float tex = 0.65 + 0.35 * noise((p - cp) / rad * 1.3 + h.xy * 50.0);
        col = mix(col, c, cov * fade * tex * mix(0.55, 0.95, h2.z));
    }
}

void burstPlume(inout vec3 col, vec2 p, float t) {
    if (length((p - BOOM) * vec2(0.75, 1.0)) > 0.75) return;
    explodeLayer(col, p, 0.065, 14.0, t, BOOM_DENS * 0.9, 0.026);   // torn chunks
    explodeLayer(col, p, 0.022, 15.0, t, BOOM_DENS * 0.8, 0.007);   // flakes
    explodeLayer(col, p, 0.010, 16.0, t, BOOM_DENS * 1.0, 0.0025);  // sparks
}

// ---- L5: sky specks ---------------------------------------------------------------
void skySpecks(inout vec3 col, vec2 p) {
    float cs = 0.024;
    vec2 g = floor(p / cs);
    vec3 h = hash33(vec3(g, 31.0));
    vec2 c = (g + 0.2 + 0.6 * h.xy) * cs;
    float z = skyMask(c) * smoothstep(0.0, 0.5, c.y) * (0.7 + 0.6 * smoothstep(0.5, 1.0, c.y));
    if (h.z < 0.22 * 1.7 * z) z *= 0.3 + 1.4 * clump(c, 31.0);
    if (h.z < 0.22 * z) {
        float s = hash12(g + 2.0);
        float el = 1.0 + 2.2 * pow(hash12(g + 5.0), 2.5);   // mostly round, a few streaked
        vec2 ab = PX * mix(vec2(1.0), vec2(3.5, 2.5), s * s * s) * vec2(el, 1.0);
        float ang = 2.1 + (hash12(g) - 0.5) * 1.4;     // mostly '\', ~120 deg
        float sd = sdFlake(rot(-ang) * (p - c), ab, s * 50.0, 0.3);
        vec3 pc = mix(hexColor(0xd85aa8), hexColor(0xff88c8), hash12(g + 3.0));
        over(col, pc, (0.5 + 0.5 * hash12(g + 7.0)) * fill(sd, PX * 0.6));
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

// ---- P4: hero chunks ------------------------------------------------------------
void heroChunks(inout vec3 col, vec2 p) {
    // orange glow smear in the burst
    paintA(col, hexColor(0xe0603a), 0.4 * fill(sdBlob(p, R(515.0, 150.0), vec2(0.016, 0.055), -0.3, 0.8, 3.0), 0.015), p, 0.4, 0.5, 1.27);
    // flame-like orange leaves: sharp tip up-left, round body down-right,
    // lighter core and a translucent, darker rim
    float l1 = sdTaper(p, R(662.0, 482.0), R(700.0, 532.0), 0.004, 0.026);
    float l2 = sdTaper(p, R(765.0, 502.0), R(795.0, 540.0), 0.004, 0.022);
    float l = torn(min(l1, l2), p, 160.0, 0.006);
    vec3 leaf = mix(hexColor(0xd85a30), hexColor(0xf8a070), smoothstep(0.0, -0.008, l) * (0.6 + 0.4 * noise(p * 150.0)));
    stamp(col, leaf, p, 0.35, 0.92 * dryFill(l, PX * 1.5, p, 0.008, 0.85));
    // violet streak with a bulb, left part of the burst
    float vs = min(sdTaper(p, R(505.0, 160.0), R(462.0, 300.0), 0.0015, 0.004), length(p - R(458.0, 312.0)) - 0.009);
    stamp(col, hexColor(0x8a4ac0), p, 0.4, 0.8 * dryFill(torn(vs, p, 120.0, 0.003), PX * 1.5, p, 0.004, 0.7));
    // dark drop, lower right
    stamp(col, hexColor(0x5a1650), p, 0.5, dryFill(sdBlob(p, R(1155.0, 683.0), vec2(0.016, 0.042), 0.12, 0.3, 1.0), PX, p, 0.006, 0.8));
}
