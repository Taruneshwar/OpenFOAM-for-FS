#!/bin/bash

# ============================================================
# STL Bounding Box Extractor
# Extracts overall min/max bounds across all STL files
# in a directory, with keyword exclusion support
# ============================================================

# --- Configuration ---
STL_DIR="./constant/triSurface/"
EXCLUDE_KEYWORD="body"        # files containing this word will be skipped

# --- Initialize min/max trackers ---
GLOBAL_XMIN=1e30;  GLOBAL_XMAX=-1e30
GLOBAL_YMIN=1e30;  GLOBAL_YMAX=-1e30
GLOBAL_ZMIN=1e30;  GLOBAL_ZMAX=-1e30

# --- Check directory exists ---
if [ ! -d "$STL_DIR" ]; then
    echo "ERROR: Directory $STL_DIR not found"
    exit 1
fi

echo "============================================"
echo " STL Bounding Box Extractor"
echo " Directory : $STL_DIR"
echo " Excluding : files containing '$EXCLUDE_KEYWORD'"
echo "============================================"
echo ""

# --- Loop through STL files ---
for f in "$STL_DIR"/*.stl; do

    # Get just the filename without the path
    filename=$(basename "$f")

    # Skip files containing the exclude keyword (case insensitive)
    if echo "$filename" | grep -qi "$EXCLUDE_KEYWORD"; then
        echo "  [SKIPPED] $filename"
        continue
    fi

    echo "  [PROCESSING] $filename"

    # Extract all vertex coordinates from the STL
    # STL vertex lines look like: "vertex x y z"
    # awk pulls out x, y, z columns and tracks min/max
    read XMIN XMAX YMIN YMAX ZMIN ZMAX <<< $(grep -i "vertex" "$f" | awk '
    BEGIN {
        xmin=1e30;  xmax=-1e30
        ymin=1e30;  ymax=-1e30
        zmin=1e30;  zmax=-1e30
    }
    {
        x=$2; y=$3; z=$4
        if (x < xmin) xmin=x
        if (x > xmax) xmax=x
        if (y < ymin) ymin=y
        if (y > ymax) ymax=y
        if (z < zmin) zmin=z
        if (z > zmax) zmax=z
    }
    END {
        print xmin, xmax, ymin, ymax, zmin, zmax
    }')

    # Print per-file bounds
    echo "           X: [$XMIN, $XMAX]"
    echo "           Y: [$YMIN, $YMAX]"
    echo "           Z: [$ZMIN, $ZMAX]"
    echo ""

    # Update global min/max using awk for float comparison
    GLOBAL_XMIN=$(awk "BEGIN {print ($XMIN < $GLOBAL_XMIN) ? $XMIN : $GLOBAL_XMIN}")
    GLOBAL_XMAX=$(awk "BEGIN {print ($XMAX > $GLOBAL_XMAX) ? $XMAX : $GLOBAL_XMAX}")
    GLOBAL_YMIN=$(awk "BEGIN {print ($YMIN < $GLOBAL_YMIN) ? $YMIN : $GLOBAL_YMIN}")
    GLOBAL_YMAX=$(awk "BEGIN {print ($YMAX > $GLOBAL_YMAX) ? $YMAX : $GLOBAL_YMAX}")
    GLOBAL_ZMIN=$(awk "BEGIN {print ($ZMIN < $GLOBAL_ZMIN) ? $ZMIN : $GLOBAL_ZMIN}")
    GLOBAL_ZMAX=$(awk "BEGIN {print ($ZMAX > $GLOBAL_ZMAX) ? $ZMAX : $GLOBAL_ZMAX}")

done

# --- Print global summary ---
echo "============================================"
echo " OVERALL BOUNDING BOX (all processed STLs)"
echo "============================================"
echo "  X: [$GLOBAL_XMIN, $GLOBAL_XMAX]"
echo "  Y: [$GLOBAL_YMIN, $GLOBAL_YMAX]"
echo "  Z: [$GLOBAL_ZMIN, $GLOBAL_ZMAX]"
echo ""
echo "  X size: $(awk "BEGIN {print $GLOBAL_XMAX - $GLOBAL_XMIN}")"
echo "  Y size: $(awk "BEGIN {print $GLOBAL_YMAX - $GLOBAL_YMIN}")"
echo "  Z size: $(awk "BEGIN {print $GLOBAL_ZMAX - $GLOBAL_ZMIN}")"
echo "============================================"
