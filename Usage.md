<div align="left">

# Meshing Automation Progress


![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL-lightgrey?style=flat-square)
![OpenFOAM](https://img.shields.io/badge/OpenFOAM-v2412-blue?style=flat-square)
![Language](https://img.shields.io/badge/scripts-Bash-89e051?style=flat-square)

![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat-square)



[Getting Started](#getting-started) •
[Usage](#usage) •
[Configuration](#configuration) •
[Troubleshooting](#troubleshooting)

</div>

## Overview

In openFOAM 2412 wsl, i have been trying to mesh DrivAER model with the references from "https://www.sciencedirect.com/science/article/pii/S0167610524000746#sec3".


> [!NOTE]
> This case was developed and tested on OpenFOAM v2412 running
> on Ubuntu 24 (WSL). Other versions may require minor adjustments.

---

Geometry has been imported to blender and stls have been created for the domain without the tire holes at contact patch and exported in ascii batch mode with 1000 scale (in mm).


- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Logs](#logs)
- [Troubleshooting](#troubleshooting)

---

```

In openFOAM case directory symlinks have been created in "constat/triSurface" for the stls included.
Inorder to do this with ease, use "for f in source/directory/path/*.stl; do ln -s "$f" target/directory/constant/triSurface/; done" - "for f in ../../../stlGeometry/stlExport/*.stl; do ln -s "$f" ../triSurface/; done"

```

### 1. Clone the Repository

Created a bash file (bounds_extractor.sh) that calculates the min & max values and write to blockMesh.

The cell sizes are also tuned for the sake of saving my pc from breaking it's back.

Running "blockMesh" should create a basic background mesh with all the above steps followed

> [!IMPORTANT]
> STL files must be in **ASCII format**. Binary STLs will be
> detected and skipped automatically. Convert with:
> ```bash
> surfaceMeshConvert input.stl output.stl
> ```

SnappyHexMesh has been partly inspired by "https://www.wolfdynamics.com/wiki/meshing_OF_SHM.pdf" and my master thesis at Scania.


## References

- [OpenFOAM Documentation](https://www.openfoam.com/documentation)
- [snappyHexMesh User Guide](https://www.openfoam.com/documentation/guides/latest/doc/guide-meshing-snappyhexmesh.html)
- [DrivAer Benchmark Geometry](https://www.aer.mw.tum.de/en/research-groups/automotive/drivaer/)
- [shields.io — Badge Generator](https://shields.io)
- 
