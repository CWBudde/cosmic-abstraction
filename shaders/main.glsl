// Cosmic Abstraction - merged final shader.
//
// A dark night sky (upper left) torn open along a ~35 deg diagonal into violet,
// magenta, coral and lavender paint, with an orange burst in the upper middle.
// Target: reference/reference_less.png (no sparks, flakes or specks). Built as
// a "stamp collage": a hand-authored colour field plus SDF stamps with a
// dry-brush paint look, dragged by a bristle comb, then crisp marks on top.
//
// Single pass, back to front:
//   B  paint.glsl   the wet background, linear RGB: L0 colour field, L1d coral
//                   front, L1 washes, L1b warm brush, L1c mottle, L2 dry brush
//                   (sky smears, navy band dashes, hair lines), L2b smudges,
//                   L2c tear chunks
//   S  smear.glsl   bristle drag: B is evaluated again upstream where wet
//   M  marks.glsl   crisp marks: M0 dust haze, M1 slashes + wedge, M2 grit,
//                   M3 ink dust, M4 drips, M5 top violet streak, pale flakes
//   G  grade.glsl   chroma boost, film grain
// Shared: field.glsl (constants, SDFs, paint-look helpers, zones, colour field).
//
// Directions follow the reference: 35 deg along the tear, ~50 deg in the warm
// top right, vertical in the burst. iTime drifts the strokes slowly along the
// tear and lets the dust dots drift and twinkle; t = 0 is the scored frame.
//
// Debug defines:
//   -D NO_SMEAR=1    skip the bristle drag
//   -D SHOW_FIELD=1  show the L0 colour field alone
//   -D SHOW_PAINT=1  show the background unsmeared

#ifndef EXPOSURE
#define EXPOSURE 1.0
#endif

#include "common.glsl"
#include "field.glsl"
#include "paint.glsl"
#include "smear.glsl"
#include "marks.glsl"
#include "grade.glsl"

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    PX = 1.0 / iResolution.y;
    vec2 p = fragCoord / iResolution.y;
    vec2 pd = p - DIR * 0.004 * iTime;   // slow drift along the tear

#if defined(SHOW_FIELD)
    fragColor = vec4(linearToSrgb(colourField(p)), 1.0);
    return;
#elif defined(SHOW_PAINT)
    fragColor = vec4(linearToSrgb(paintAt(p, false)), 1.0);
    return;
#endif

    vec3 col = smear(fragCoord, p);      // S
    dustHaze(col, p);                    // M0
    slashes(col, p);                     // M1
    grit(col, pd);                       // M2
    inkDust(col, pd);                    // M3
    drips(col, p);                       // M4
    bgHeroes(col, p);                    // M5
    col = grain(boostChroma(col), fragCoord, p);   // G
    fragColor = vec4(linearToSrgb(col * EXPOSURE), 1.0);
}
