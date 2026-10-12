// marks.glsl - crisp background marks drawn over the smeared paint. These are
// part of the background (they stay with -D BG_ONLY=1):
//   M0  dust haze    unresolved 1-2 px pigment dust over the burst and sky
//   M1  slashes      hero dark slashes, violet under-stroke, dark wedge, blobs
//   M1b burst chunks soft translucent upright violet sheets in the burst
//   M1c burst runs   thin near-vertical torn runs (gravity) in the burst
//   M2  grit         dense 1 px light/dark pigment specks in the tear band
//   M3  ink dust     fine clumped ink dust (inkScale; the larger flung specks
//                    are particle P5)
//   M4  drips        pale runs down the pink lower right
//   M5  heroes       top violet streak, pale flakes, leaf drips, dark drop

// ---- M1: dark slashes -------------------------------------------------------------
void slashes(inout vec3 col, vec2 p) {
    if (p.x < 0.95 || p.y < 0.38) return;      // all slashes live in the warm top
    vec3 ink = hexColor(0x120828);
    vec3 navy = hexColor(0x2a1868);
    // violet under-stroke riding above the main slash
    float vb = sdTaper(p, R(870.0, 250.0), R(1060.0, 50.0), 0.03, 0.02);
    paint(col, hexColor(0x6a34b0), 0.45 * fill(torn(vb, p, 50.0, 0.02), PX * 3.0), p, 0.6, 0.4);
    // main long slash band through the warm side: several overlapping strokes
    float d = sdTaper(p, R(815.0, 400.0), R(1140.0, 70.0), 0.004, 0.011);
    d = min(d, sdTaper(p, R(930.0, 285.0), R(1100.0, 115.0), 0.014, 0.008));
    d = min(d, sdTaper(p, R(1060.0, 170.0), R(1220.0, 40.0), 0.006, 0.003));
    stamp(col, ink, p, 0.6, dryFill(d < 0.02 ? d + 0.008 * (noise(p * 45.0) - 0.5) : d, PX * 1.2, p, 0.012, 0.8));
    float m = sdEllipse(rot(-0.8) * (p - R(1030.0, 180.0)), vec2(0.085, 0.016));
    stamp(col, hexColor(0x160828), p, 0.6, dryFill(torn(m, p, 90.0, 0.009), PX * 1.5, p, 0.014, 0.8));
    // parallel thinner slashes
    float d2 = sdTaper(p, R(800.0, 470.0), R(1000.0, 300.0), 0.002, 0.004);
    d2 = min(d2, sdTaper(p, R(990.0, 140.0), R(1150.0, 10.0), 0.004, 0.002));
    d2 = min(d2, sdTaper(p, R(840.0, 290.0), R(990.0, 150.0), 0.0015, 0.004));
    d2 = min(d2, sdTaper(p, R(1180.0, 160.0), R(1450.0, -20.0), 0.002, 0.004));
    over(col, ink, 0.8 * dryFill(d2 < 0.01 ? d2 + 0.004 * (noise(p * 90.0) - 0.5) : d2, PX, p, 0.006, 0.8));
    // dark wedge, top right
    float w = sdTaper(p, R(1195.0, 165.0), R(1300.0, 45.0), 0.028, 0.02);
    stamp(col, hexColor(0x3a0c3c), p, 0.6, 0.85 * dryFill(torn(w, p, 60.0, 0.014), PX * 1.5, p, 0.016, 0.8));
    float w2 = sdEllipse(rot(-0.75) * (p - R(1150.0, 60.0)), vec2(0.06, 0.016));
    stamp(col, hexColor(0x5a1060), p, 0.5, 0.2 * dryFill(torn(w2, p, 70.0, 0.01), PX * 1.5, p, 0.012, 0.8));
    // elongated dark blobs along the slash
    stamp(col, ink, p, 0.5, dryFill(sdBlob(p, R(1046.0, 254.0), vec2(0.020, 0.009), A35 + 0.2, 0.3, 8.0), PX, p, 0.005, 0.8));
    vec3 nv = mix(navy, hexColor(0x4a3aa0), smoothstep(-0.01, 0.01, dot(p - R(962.0, 322.0), vec2(-0.5, 0.86))));
    stamp(col, nv, p, 0.5, dryFill(sdBlob(p, R(962.0, 322.0), vec2(0.026, 0.014), A35 + 0.25, 0.3, 6.0), PX, p, 0.006, 0.8));
    stamp(col, ink, p, 0.5, dryFill(sdBlob(p, R(1185.0, 95.0), vec2(0.03, 0.012), A35, 0.4, 2.0), PX, p, 0.006, 0.8));
}

// Grit: dense 1 px pigment specks, light and dark, in the tear band.
void grit(inout vec3 col, vec2 p) {
    if (tearCoord(p) < -0.05) return;
    float cs = 0.0045;
    vec2 g = floor(p / cs);
    vec3 h = hash33(vec3(g, 111.0));
    vec2 c = (g + 0.2 + 0.6 * h.xy) * cs;
    float t = tearCoord(c);
    float z = smoothstep(-0.03, 0.05, t) * smoothstep(0.45, 0.2, t);
    if (h.z < 0.45 * 1.5 * z) z *= 0.3 + 1.2 * clump(c, 111.0);
    z = max(z, 0.6 * burstMask(c) * smoothstep(0.0, 0.1, t));
    if (h.z < 0.45 * z) {
        vec3 gc = hash12(g) < 0.9 ? hexColor(0x2a1450) : hexColor(0x8a6ab8);
        over(col, gc, (0.4 + 0.5 * hash12(g + 1.0)) * fill(length(p - c) - PX * (0.4 + 0.8 * hash12(g + 2.0)), PX * 0.6));
    }
}

// ---- L6: ink specks on the warm side ---------------------------------------------
// One scale of ink specks. size: (min, max) radius in px, dens: peak density.
void inkScale(inout vec3 col, vec2 p, float cs, float seed, vec2 size, float dens, float tailP) {
    if (tearCoord(p) < -0.03) return;
    vec2 q = rot(-A35) * p;
    vec2 g = floor(q / cs);
    // tiny marks (no tails) only reach the 2x2 cells around the pixel
    int lo = tailP > 0.0 ? -1 : 0;
    if (tailP <= 0.0) g += step(0.5, fract(q / cs)) - 1.0;
    for (int j = lo; j <= 1; j++) {
        for (int i = lo; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, seed));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.95) * cs;
            vec2 pc = rot(A35) * c;
            // densest in the lower middle / lower right, sparse in the orange top
            float z = warmMask(pc) * (0.25 + 0.75 * smoothstep(0.65, 0.25, pc.y));
            if (h.z > dens * z * 1.65) continue;   // cheap reject before the noise
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

// Fine ink dust is background texture; the resolved specks are particles.
void inkDust(inout vec3 col, vec2 p) {
    float lr = smoothstep(1.1, 1.35, p.x) * smoothstep(0.6, 0.4, p.y);
    inkScale(col, p, 0.007, 41.0, vec2(0.5, 1.4), 0.25 * (1.0 - 0.6 * lr), 0.0);
}
void inkSpecks(inout vec3 col, vec2 p) {
    inkScale(col, p, 0.016, 43.0, vec2(0.9, 6.0), 0.30, 0.25);  // specks and flung drops
}

// ---- M4: drips -- pale runs down the pink lower right -----------------------------
void drip(inout vec3 col, vec2 p, vec2 top, float len, float w, vec3 c, float a) {
    vec2 bot = top - vec2(0.004, len);
    float sd = sdTaper(p, top, bot, w, w * 0.5);
    if (sd > 3.0 * PX) return;
    float fade = smoothstep(top.y - len, top.y - 0.7 * len, p.y);   // dries out at the end
    paintA(col, c, a * fade * fill(sd, w), p, 0.5, 0.2, 1.5708);
}

void drips(inout vec3 col, vec2 p) {
    if (p.x < 1.1 || p.y > 0.55) return;
    vec3 pale = hexColor(0xf8b8d8);
    drip(col, p, R(1185.0, 470.0), 0.30, 3.5 * PX, pale, 0.45);
    drip(col, p, R(1280.0, 560.0), 0.32, 4.0 * PX, hexColor(0xf290b8), 0.45);
    drip(col, p, R(1215.0, 600.0), 0.18, 1.2 * PX, pale, 0.3);
    drip(col, p, R(1365.0, 520.0), 0.15, 1.2 * PX, hexColor(0x9a4a9a), 0.3);
}

// ---- M5: background heroes ----------------------------------------------------
void bgHeroes(inout vec3 col, vec2 p) {
    // top violet streak at u ~ 0.5: vertical, darker at the top edge
    vec2 tv = p - R(726.0, 30.0);
    float ts = torn(sdEllipse(rot(-0.08) * tv, vec2(0.056, 0.095)), p, 50.0, 0.012);
    vec3 tc = mix(hexColor(0x5a3498), hexColor(0x8a62cc), smoothstep(0.05, -0.07, tv.y) * smoothstep(-0.06, 0.0, -abs(tv.x)));
    stamp(col, tc, p, 0.5, 0.9 * dryFillA(ts, PX * 1.5, p, 0.014, 0.8, 1.5708));
    // pale flakes: top edge, lavender flake left of the leaves
    over(col, hexColor(0xf4a8d8), fill(sdFlake(p - R(1310.0, 14.0), vec2(0.05, 0.016), 2.0, 0.25), PX));
    over(col, hexColor(0xe8a0e0), fill(sdFlake(p - R(818.0, 26.0), vec2(0.006, 0.02), 6.0, 0.2), PX));
    over(col, hexColor(0xc0a8e0), fill(sdFlake(rot(0.6) * (p - R(605.0, 590.0)), vec2(0.022, 0.011), 3.0, 0.3), PX));
    // big dark drop at the right edge
    stamp(col, hexColor(0x3a1250), p, 0.5, dryFill(sdBlob(p, R(1438.0, 680.0), vec2(0.022, 0.04), 0.35, 0.3, 2.0), PX, p, 0.006, 0.8));
    // vertical drips under the leaves and on the right
    over(col, hexColor(0x7a2a6a), 0.7 * fill(sdTaper(p, R(712.0, 560.0), R(728.0, 650.0), 0.0035, 0.001), PX));
    over(col, hexColor(0xb05090), 0.35 * fill(sdTaper(p, R(1190.0, 480.0), R(1205.0, 700.0), 0.003, 0.002), PX));
    over(col, hexColor(0x7a2a7a), 0.5 * fill(sdTaper(p, R(840.0, 600.0), R(855.0, 790.0), 0.002, 0.004), PX * 1.5));
}

// ---- M0: dust haze -- the unresolved spray left over the night sky -------------
// Per-pixel speckle (not stamps): red-orange and violet pigment dust, densest
// around the burst and along the upper tear, thin over the rest of the sky.
void dustHaze(inout vec3 col, vec2 fragCoord, vec2 p) {
    float t = tearCoord(p);
    float sky = 1.0 - smoothstep(-0.02, 0.08, t);
    float dens = sky * (0.003 + 0.10 * burstMask(p) * smoothstep(0.35, 0.6, p.y)
                        + 0.03 * smoothstep(0.4, 0.9, p.y) * smoothstep(0.1, 0.5, p.x));
    vec2 cell = floor(fragCoord * (816.0 / iResolution.y) / 1.5);
    vec3 h = hash33(vec3(cell, 131.0));
    if (h.z > dens) return;
    vec3 dc = h.x < 0.5 ? hexColor(0xb83a38) : (h.x < 0.8 ? hexColor(0x6a2a90) : hexColor(0xd06aa8));
    over(col, dc, 0.25 + 0.5 * h.y);
}

// ---- M1b: burst chunks -- soft translucent violet sheets hanging in the burst ----
// Torn, mostly upright violet/magenta chunks (the paint that the explosion tore
// off the tear), overlapping and translucent, with dry fringes.
void burstStreaks(inout vec3 col, vec2 p) {
    if (burstMask(p) < 0.004 && p.y < 0.65) return;
    vec2 cell = vec2(0.045, 0.075);     // > half the largest chunk: no clipping
    vec2 g = floor(p / cell);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 id = g + vec2(i, j);
            vec3 h = hash33(vec3(id, 61.0));
            vec2 c = (id + 0.5 + (h.xy - 0.5) * 0.8) * cell;
            float t = tearCoord(c);
            float z = burstMask(c) * smoothstep(0.35, 0.55, c.y) * smoothstep(-0.22, -0.06, t) * smoothstep(0.06, -0.02, t);
            if (h.z > 0.8 * z) continue;
            float s = hash12(id + 1.0);
            vec2 ab = PX * (6.0 + 14.0 * s * s) * vec2(1.0, 1.3 + 1.2 * hash12(id + 2.0));
            float a = (hash12(id + 3.0) - 0.5) * 0.5;               // upright, +-15 deg
            float sd = sdFlake(rot(-a) * (p - c), ab, h.x * 70.0, 0.45);
            sd = torn(sd, p, 120.0, ab.x * 0.25);
            float k = hash12(id + 4.0);
            vec3 sc = k < 0.45 ? hexColor(0x6a3ab0) : (k < 0.75 ? hexColor(0x8a48c0) : (k < 0.9 ? hexColor(0xa04aa0) : hexColor(0x2a1050)));
            stamp(col, sc, p, 0.4, (0.25 + 0.25 * hash12(id + 5.0)) * dryFillA(sd, PX * 1.5, p, ab.y * 0.6, 0.8, 1.5708 + a));
        }
    }
}

// ---- M1c: burst runs -- thin near-vertical torn runs and drips in the burst ----
void burstRuns(inout vec3 col, vec2 p) {
    if (burstMask(p) < 0.004 && p.y < 0.65) return;
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
            vec3 sc = k < 0.35 ? hexColor(0x3a1c78) : (k < 0.6 ? hexColor(0x6a38a8) : (k < 0.8 ? hexColor(0xd8582c) : hexColor(0x160a2c)));
            float fade = 0.6 + 0.4 * smoothstep(-1.0, 0.5, dot(p - c, d) / dot(d, d));   // paler tail
            paintA(col, sc, 0.65 * fade * fill(sd, PX * 1.5), p, 0.35, 0.4, a);
        }
    }
}

