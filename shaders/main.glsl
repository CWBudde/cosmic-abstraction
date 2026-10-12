// Cosmic Abstraction - merged final shader.
//
// A dark night sky (upper left) torn open along a ~35 deg diagonal into violet,
// magenta, coral and lavender paint, with an explosion of torn orange/violet
// chunks in the upper middle. Built as a "stamp collage": a hand-authored
// colour field plus SDF stamps with a dry-brush paint look, dragged by a
// bristle comb, then crisp marks and particles on top.
//
// Passes:
//   Buffer A  paint.glsl   the wet background before the drag, linear RGB in a
//                          half-float buffer: L0 colour field, L1d coral front,
//                          L1 washes, L1b warm brush, L1c mottle, L2 dry brush
//                          (sky smears, navy band dashes, hair lines), L2b
//                          smudges, L2c tear chunks, L2d gravity runs
//   Image     main.glsl    S   smear      bristle drag of Buffer A (smear.glsl)
//                          M   marks      background marks (marks.glsl):
//                                         M0 dust haze, M1 slashes + wedge,
//                                         M1b burst chunks, M1c burst runs,
//                                         M2 grit, M3 ink dust, M4 drips,
//                                         M5 top violet streak, pale flakes
//                          P   particles  foreground (particles.glsl):
//                                         P2 burst plume (Rival C, looped),
//                                         P3 sky specks, P4 leaves, P5 ink specks
//                          G   grade      chroma boost, film grain (grade.glsl)
// Shared: field.glsl (constants, SDFs, paint-look helpers, zones, colour field).
//
// Directions follow the reference: 35 deg along the tear, ~50 deg in the warm
// top right, vertical in the burst. iTime drifts the strokes along the tear
// and loops the burst; t = 0 is the scored frame.
//
// Debug defines:
//   -D BG_ONLY=1     background only: no particles, specks, flakes or leaves
//   -D NO_SMEAR=1    skip the bristle drag
//   -D SHOW_FIELD=1  show the L0 colour field alone
//   -D SHOW_PAINT=1  show Buffer A unsmeared

#bufferA "paint.glsl"

#ifndef EXPOSURE
#define EXPOSURE 1.0
#endif

#include "common.glsl"
#include "field.glsl"
#include "smear.glsl"
#include "marks.glsl"
#include "particles.glsl"
#include "grade.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    PX = 1.0 / iResolution.y;
    vec2 p = fragCoord / iResolution.y;
    vec2 pd = p - DIR * 0.004 * iTime;   // slow drift along the tear

#if defined(SHOW_FIELD)
    fragColor = vec4(linearToSrgb(colourField(p)), 1.0);
    return;
#elif defined(SHOW_PAINT)
    fragColor = vec4(linearToSrgb(paintAt(p)), 1.0);
    return;
#endif

    vec3 col = smear(fragCoord, p);      // S
    dustHaze(col, fragCoord, p);         // M0
    slashes(col, p);                     // M1
    burstStreaks(col, pd);               // M1b
    burstRuns(col, pd);                  // M1c
#ifndef BG_ONLY
    burstPlume(col, p, mod(iTime, LOOP));   // P2
    skySpecks(col, pd);                  // P3
#endif
    grit(col, pd);                       // M2
    inkDust(col, pd);                    // M3
#ifndef BG_ONLY
    inkSpecks(col, pd);                  // P5
#endif
    drips(col, p);                       // M4
    bgHeroes(col, p);                    // M5
#ifndef BG_ONLY
    heroChunks(col, p);                  // P4
#endif
    col = grain(boostChroma(col), fragCoord, p);   // G
    fragColor = vec4(linearToSrgb(col * EXPOSURE), 1.0);
}
