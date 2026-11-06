# ARGoS3 Anaconda package

An Anaconda recipe to build and install the [ARGoS3 multi-robot simulator](https://www.argos-sim.info).

Anaconda link: [https://anaconda.org/channels/pbaldini/packages/argos3/overview](https://anaconda.org/channels/pbaldini/packages/argos3/overview)

## Variants

Each version is published in two _builds_:

| Build     | Recipe               | Contents                                                                                                 |
|-----------|----------------------|----------------------------------------------------------------------------------------------------------|
| default   | `recipe/betaXX.yaml` | Simulator + Qt-OpenGL visualization (Qt6 for beta59, Qt5 for beta48)                                     |
| headless  | `recipe/betaXX-headless.yaml` | Simulator only, no Qt dependency (e.g. for clusters/CI). Experiments must not use `<qt-opengl>` |

The GUI build is preferred by the solver; ask for the headless one explicitly.

The repository currently contains data to build the following _versions_ of the package:

| Version | Label            |
|---------|------------------|
| beta 59 | `3.0.0.0.beta59` |
| beta 48 | `3.0.0.0.beta48` |

## Installing from Anaconda repository

From conda:

```bash
conda install pbaldini::argos3[==$VERSION[="headless*"]]
```

From pixi:

```bash
pixi workspace channel add https://conda.anaconda.org/pbaldini
pixi add pbaldini::argos3[==$VERSION[="headless*"]]
```

From sources (for debug purpose):

```bash
# Init the pixi environment
pixi install
pixi shell

# Launch the build tool (installed with pixi)
pixi run build-beta59 # or build-beta48, build-beta59-headless, build-beta48-headless, build-all

# Install locally with pixi
pixi add $(pwd)/output/osx-arm64/argos3-3.0.0.0.beta59-*.conda

# (OR) Install locally with conda
conda install --use-local argos3
```

## Troubleshooting

**The visualization does not start on Linux / WSL** (`QOpenGLWidget: Failed to create context`):

- The GUI needs a system OpenGL driver (e.g. Mesa). Check it **outside** the environment with `glxinfo -B` (package `mesa-utils` on Debian/Ubuntu); it should print a renderer instead of an error.
- On WSL the GUI build uses X11 (XWayland) by default, because Qt's Wayland backend often has no EGL there. Setting `QT_QPA_PLATFORM` explicitly (e.g. `QT_QPA_PLATFORM=wayland argos3 -c ...`) overrides this default.

## For contributors

Whenever you work on a change in the following repository, keep in mind that a push to master will trigger a GitHub action that compiles and uploads the package to Anaconda.

Before the upload, every package is tested on each platform (`.github/workflows/test.yml`): it is installed in a fresh environment, the `footbot_diffusion` controller of [argos3-examples](https://github.com/ilpincy/argos3-examples) is built against it, and `diffusion_1.argos` is run without visualization.
The upload only happens if all tests pass.
