# ARGoS3 conda package

A conda recipe to build and install the [ARGoS3 multi-robot simulator](https://www.argos-sim.info) from source.

## What is ARGoS3?

ARGoS (multi-physics multi-robot simulator) is a highly scalable,
parallel multi-robot simulator used widely in swarm-robotics research.
Key features:

- **Modular plug-in architecture** – robots, physics engines, visualisations
  and controllers are all plug-ins.
- **Multiple simultaneous physics engines** – 2D and 3D engines can coexist
  in the same experiment.
- **Lua scripting** – rapid controller prototyping without recompiling.
- **Qt/OpenGL visualisation** – interactive 3-D rendering for debugging.

## Installing

From conda:

```conda install argos3```

From pixi:

```pixi add argos3```

From sources:

```
# Init the pixi environment
pixi install
pixi shell

# Launch the build tool (installed with pixi)
pixi build-beta59 # or 48

# Install locally with conda
conda install --use-local argos3

# Install locally with pixi
pixi add $(pwd)/output/osx-arm64/argos3-3.0.0.0.beta59-h60d57d3_0.conda
```
