# ARGoS3 Anaconda package

An Anaconda recipe to build and install the [ARGoS3 multi-robot simulator](https://www.argos-sim.info).

## Installing from Anaconda repository

From conda:

```bash
conda install pbaldini::argos3[==3.0.0.0.beta48|==3.0.0.0.beta59]
```

From pixi:

```bash
pixi workspace channel add https://conda.anaconda.org/pbaldini
pixi add pbaldini::argos3[==3.0.0.0.beta48|==3.0.0.0.beta59]
```

From sources (for debug purpose):

```bash
# Init the pixi environment
pixi install
pixi shell

# Launch the build tool (installed with pixi)
pixi build-beta59 # or 48

# Install locally with pixi
pixi add $(pwd)/output/osx-arm64/argos3-3.0.0.0.beta59-*.conda

# (OR) Install locally with conda
conda install --use-local argos3
```
