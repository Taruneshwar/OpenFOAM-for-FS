#!/bin/bash -l
# The -l above is required to get the full environment with modules

#SBATCH --time=120
#SBATCH --propagate=NONE
#SBATCH --output=./logs/slurm-%j.out
#SBATCH --error=./logs/slurm-errors-%j.out
#SBATCH --kill-on-invalid-dep=yes


# Running surfaceFeatureExtract

srun --ntasks=1 surfaceFeatureExtract

# Running bloackMesh

if [ -d "dynamicCode" ]; then
    print_warning "Removing stale dynamicCode directory"
    rm -rf dynamicCode
fi

srun --ntasks=2 blockMesh

#sed -i "s/\(^numberOfSubdomains\s\+\) .*/\1 512;/g" system/decomposeParDict
#logFile="./logs/decomposeParMesh.log" srun --ntasks=1 decomposePar -no-fields -force
#
#srun --ntasks=512 snappyHexMesh -parallel -overwrite

exit 0
