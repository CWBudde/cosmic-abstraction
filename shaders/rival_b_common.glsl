// rival_b_common.glsl - helpers shared by both passes of Rival B.

#include "common.glsl"

const vec2 ALONG = vec2(0.8192, 0.5736);       // the drag direction, 35 deg
const vec2 ACROSS = vec2(0.5736, -0.8192);     // towards the warm side

// Soft box window in uv: box = (u0, v0, u1, v1).
float win(vec2 uv, vec4 box, float soft) {
    vec2 a = smoothstep(box.xy - soft, box.xy + soft, uv);
    vec2 b = 1.0 - smoothstep(box.zw - soft, box.zw + soft, uv);
    return a.x * a.y * b.x * b.y;
}

// Signed distance (aspect-corrected units) from the night-sky edge of the
// tear: negative in the sky, positive towards the violet band and the warm
// side. The edge runs steeper than the streaks: u ~ 0.22 + 0.28 v, wobbled.
float tearDist(vec2 uv, float asp) {
    vec2 p = vec2(uv.x * asp, uv.y);
    vec2 n = vec2(0.894, -0.447);
    float d = dot(p - vec2(0.22 * asp, 0.0), n);
    return d + 0.06 * (fbm(vec2(dot(p, ALONG) * 4.0, dot(p, ACROSS) * 10.0), 4) - 0.5);
}
