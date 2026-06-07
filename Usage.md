# Meshing automation notes

In openFOAM 2412 wsl, i have been trying to mesh DrivAER model with the references from "https://www.sciencedirect.com/science/article/pii/S0167610524000746#sec3".

Geometry has been imported to blender and stls have been created for the domain without the tire holes at contact patch and exported in ascii batch mode with 1000 scale (in mm).

In openFOAM case directory symlinks have been created in "constat/triSurface" for the stls included.
Inorder to do this with ease, use "for f in source/directory/path/*.stl; do ln -s "$f" target/directory/constant/triSurface/; done" - "for f in ../../../stlGeometry/stlExport/*.stl; do ln -s "$f" ../triSurface/; done"

Created a bash file (bounds_extractor.sh) that calculates the min & max values and write to blockMesh.

The cell sizes are also tuned for the sake of saving my pc from breaking it's back.

Running "blockMesh" should create a basic background mesh with all the above steps followed


SnappyHexMesh has been partly inspired by "https://www.wolfdynamics.com/wiki/meshing_OF_SHM.pdf" and my master thesis at Scania.
