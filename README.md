# Cosmic Abstraction

A GLSL recreation of `reference/reference.png`: a dark, speckled night sky in the
upper left, torn open along a diagonal into violet, magenta and orange paint.

The runner, `cmd/imgstat` and the tooling are copied from
[imperfection](https://github.com/CWBudde/imperfection); see its README for the full
flag, multipass (`#bufferA`) and `imgstat` documentation.

## Layout

| Path                                                                 | Content                                                                                      |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `shaders/main.glsl`                                                  | Image pass: bristle drag, marks, particles, grade; header lists all layers and debug defines |
| `shaders/paint.glsl`                                                 | Buffer A: the wet background before the drag                                                 |
| `shaders/field.glsl`                                                 | shared constants, shape and paint helpers, zone masks, colour field                          |
| `shaders/smear.glsl`, `marks.glsl`, `particles.glsl`, `grade.glsl`   | the Image-pass layers                                                                        |
| `shaders/rival_{a,b,c}*.glsl`                                        | the three competing prototypes (record, still renderable); A won and became the base         |
| `shaders/common.glsl`                                                | hashes, noise, colour helpers                                                                |
| `reference/reference.png`                                            | the target image (1456x816, not versioned)                                                   |
| `reference/reference_less.png`                                       | the same image without sparks, flakes and specks (background target)                         |
| `docs/reference-stats.txt`, `docs/reference-less-stats.txt`          | `imgstat analyze` output for both references                                                 |
| `main.go`, `render.go`, `pipeline.go`, `preprocess.go`, `compare.go` | the Shadertoy-compatible runner                                                              |
| `cmd/imgstat/`                                                       | image analysis and style scoring tool                                                        |

## Usage

```sh
just run                  # window with hot reload (Space pauses, P saves a PNG)
just compare              # out/shot.png + out/shot_cmp.png against the reference
just score                # imgstat style score (lower = better)
just score-bg             # background only (-D BG_ONLY=1) against reference_less.png
just bundle               # Shadertoy export into out/shadertoy.glsl
```

Go needs `-buildvcs=false` here (stray `/mnt/projekte/Code/.git`); the justfile sets it.
