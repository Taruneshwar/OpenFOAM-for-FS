#!/bin/bash
# Silence all subsequent outputs inside this script
exec > /dev/null 2>&1

# ============================================================
# STL Bounding Box Extractor
# Extracts overall min/max bounds across all STL files
# and writes them into blockMeshDict bx/by/bz min/max values
# ============================================================

# --- Configuration ---
STL_DIR="./constant/triSurface/"
EXCLUDE_KEYWORD="body"
BLOCKMESH="./system/blockMeshDict"
PADDING=0.0          # extra buffer added around the bounding box

# --- Initialize min/max trackers ---
GLOBAL_XMIN=999999999;  GLOBAL_XMAX=-999999999
GLOBAL_YMIN=999999999;  GLOBAL_YMAX=-999999999
GLOBAL_ZMIN=999999999;  GLOBAL_ZMAX=-999999999

# --- Checks ---
if [ ! -d "$STL_DIR" ]; then
    echo "ERROR: Directory $STL_DIR not found"
    exit 1
fi

if [ ! -f "$BLOCKMESH" ]; then
    echo "ERROR: blockMeshDict not found at $BLOCKMESH"
    exit 1
fi

echo "============================================"
echo " STL Bounding Box Extractor"
echo " Directory : $STL_DIR"
echo " Excluding : files containing '$EXCLUDE_KEYWORD'"
echo " BlockMesh : $BLOCKMESH"
echo " Padding   : $PADDING"
echo "============================================"
echo ""

# --- Loop through STL files ---
for f in "$STL_DIR"/*.stl; do

    filename=$(basename "$f")

    # Skip excluded files
    if echo "$filename" | grep -qi "$EXCLUDE_KEYWORD"; then
        echo "  [SKIPPED] $filename"
        continue
    fi

    # Skip binary STLs
    if ! grep -qi "vertex" "$f"; then
        echo "  [WARNING] $filename appears to be binary STL, skipping"
        continue
    fi

    echo "  [PROCESSING] $filename"

    read XMIN XMAX YMIN YMAX ZMIN ZMAX <<< $(grep -i "vertex" "$f" | awk '
    BEGIN {
        xmin=999999999;  xmax=-999999999
        ymin=999999999;  ymax=-999999999
        zmin=999999999;  zmax=-999999999
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

    echo "           X: [$XMIN, $XMAX]"
    echo "           Y: [$YMIN, $YMAX]"
    echo "           Z: [$ZMIN, $ZMAX]"
    echo ""

    GLOBAL_XMIN=$(awk "BEGIN {print ($XMIN < $GLOBAL_XMIN) ? $XMIN : $GLOBAL_XMIN}")
    GLOBAL_XMAX=$(awk "BEGIN {print ($XMAX > $GLOBAL_XMAX) ? $XMAX : $GLOBAL_XMAX}")
    GLOBAL_YMIN=$(awk "BEGIN {print ($YMIN < $GLOBAL_YMIN) ? $YMIN : $GLOBAL_YMIN}")
    GLOBAL_YMAX=$(awk "BEGIN {print ($YMAX > $GLOBAL_YMAX) ? $YMAX : $GLOBAL_YMAX}")
    GLOBAL_ZMIN=$(awk "BEGIN {print ($ZMIN < $GLOBAL_ZMIN) ? $ZMIN : $GLOBAL_ZMIN}")
    GLOBAL_ZMAX=$(awk "BEGIN {print ($ZMAX > $GLOBAL_ZMAX) ? $ZMAX : $GLOBAL_ZMAX}")

done

# --- Apply padding to global bounds ---
GLOBAL_XMIN=$(awk "BEGIN {print $GLOBAL_XMIN - $PADDING}")
GLOBAL_XMAX=$(awk "BEGIN {print $GLOBAL_XMAX + $PADDING}")
GLOBAL_YMIN=$(awk "BEGIN {print $GLOBAL_YMIN - $PADDING}")
GLOBAL_YMAX=$(awk "BEGIN {print $GLOBAL_YMAX + $PADDING}")
GLOBAL_ZMIN=$(awk "BEGIN {print $GLOBAL_ZMIN - $PADDING}")
GLOBAL_ZMAX=$(awk "BEGIN {print $GLOBAL_ZMAX + $PADDING}")

# --- Print global summary ---
echo "============================================"
echo " OVERALL BOUNDING BOX (with padding)"
echo "============================================"
echo "  X: [$GLOBAL_XMIN, $GLOBAL_XMAX]"
echo "  Y: [$GLOBAL_YMIN, $GLOBAL_YMAX]"
echo "  Z: [$GLOBAL_ZMIN, $GLOBAL_ZMAX]"
echo ""
echo "  X size: $(awk "BEGIN {print $GLOBAL_XMAX - $GLOBAL_XMIN}")"
echo "  Y size: $(awk "BEGIN {print $GLOBAL_YMAX - $GLOBAL_YMIN}")"
echo "  Z size: $(awk "BEGIN {print $GLOBAL_ZMAX - $GLOBAL_ZMIN}")"
echo "============================================"
echo ""

# --- Write values into blockMeshDict using sed ---
echo " Writing bounds to $BLOCKMESH ..."

sed -i \
    -e "s/^bx_min .*/bx_min $GLOBAL_XMIN;/" \
    -e "s/^bx_max .*/bx_max $GLOBAL_XMAX;/" \
    -e "s/^by_min .*/by_min $GLOBAL_YMIN;/" \
    -e "s/^by_max .*/by_max $GLOBAL_YMAX;/" \
    -e "s/^bz_min .*/bz_min $GLOBAL_ZMIN;/" \
    -e "s/^bz_max .*/bz_max $GLOBAL_ZMAX;/" \
    "$BLOCKMESH"

echo " Done. blockMeshDict updated:"
echo ""
grep -E "^b[xyz]_(min|max)" "$BLOCKMESH"
echo ""
echo "============================================"
