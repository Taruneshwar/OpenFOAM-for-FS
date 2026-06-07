#!/bin/bash

# ============================================================
# STL Bounding Box Extractor v3
# - Full bounds (all STLs except excluded) -> blockMeshDict
# - Geometry bounds (explicit include list) -> snappyHexMeshDict
# Writes each variable ONCE by targeting specific line numbers
# ============================================================

# --- Configuration ---
STL_DIR="./constant/triSurface/"
BLOCKMESH="./system/blockMeshDict"
SNAPPYHEXMESH="./system/snappyHexMeshDict"

# Keywords excluded from blockMesh bounds
EXCLUDE_BLOCKMESH="body"

# Explicit list of STLs for snappyHexMesh geometry bounds
SNAPPY_INCLUDE=(
    "drivaerBody.stl"
    "frontLeftTire.stl"
    "frontRightTire.stl"
    "rearLeftTire.stl"
    "rearRightTire.stl"
)

# ============================================================
# --- DO NOT EDIT BELOW THIS LINE ---
# ============================================================

# --- Initialize bounds ---
GLOBAL_XMIN=999999999;  GLOBAL_XMAX=-999999999
GLOBAL_YMIN=999999999;  GLOBAL_YMAX=-999999999
GLOBAL_ZMIN=999999999;  GLOBAL_ZMAX=-999999999

GEO_XMIN=999999999;  GEO_XMAX=-999999999
GEO_YMIN=999999999;  GEO_YMAX=-999999999
GEO_ZMIN=999999999;  GEO_ZMAX=-999999999

# --- Helper: case-insensitive include check ---
in_snappy_include() {
    local target="${1,,}"
    for item in "${SNAPPY_INCLUDE[@]}"; do
        if [ "${item,,}" == "$target" ]; then
            return 0
        fi
    done
    return 1
}

# --- Helper: extract bounds from single STL ---
extract_bounds() {
    grep -i "vertex" "$1" | awk '
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
    }'
}

# --- Helper: write a variable to FIRST occurrence only ---
# Usage: write_first_occurrence "varname" "value" "file"
write_first_occurrence() {
    local varname="$1"
    local value="$2"
    local file="$3"

    # Find the line number of the FIRST occurrence
    local lineno
    lineno=$(grep -n "\b${varname}\b" "$file" | head -1 | cut -d: -f1)

    if [ -z "$lineno" ]; then
        echo "  [WARNING] '$varname' not found in $file"
        return 1
    fi

    # Replace only that specific line number
    sed -i "${lineno}s/.*/$(grep -m1 "\b${varname}\b" "$file" | sed "s/\b${varname}\b.*/${varname} ${value};/" | sed 's/[[:space:]]*//')/" "$file"

    # Simpler and more reliable — use awk to replace only line N
    awk -v n="$lineno" -v name="$varname" -v val="$value" \
        'NR==n { 
            # preserve leading whitespace
            match($0, /^[[:space:]]*/); 
            indent=substr($0, RSTART, RLENGTH);
            print indent name " " val ";"
            next
        } 
        { print }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ============================================================
# --- Sanity checks ---
# ============================================================

if [ ! -d "$STL_DIR" ]; then
    echo "ERROR: STL directory not found: $STL_DIR"
    exit 1
fi

if [ ! -f "$BLOCKMESH" ]; then
    echo "ERROR: blockMeshDict not found: $BLOCKMESH"
    exit 1
fi

if [ ! -f "$SNAPPYHEXMESH" ]; then
    echo "ERROR: snappyHexMeshDict not found: $SNAPPYHEXMESH"
    exit 1
fi

shopt -s nullglob
stl_files=("$STL_DIR"/*.stl)
if [ ${#stl_files[@]} -eq 0 ]; then
    echo "ERROR: No STL files found in $STL_DIR"
    exit 1
fi

if ! grep -q "bbox_xmin" "$BLOCKMESH"; then
    echo "ERROR: bbox_xmin not found in $BLOCKMESH"
    exit 1
fi

if ! grep -q "bbox_xmin" "$SNAPPYHEXMESH"; then
    echo "ERROR: bbox_xmin not found in $SNAPPYHEXMESH"
    exit 1
fi

if ! grep -q "geo_xmin" "$SNAPPYHEXMESH"; then
    echo "ERROR: geo_xmin not found in $SNAPPYHEXMESH"
    exit 1
fi

# ============================================================
# --- Header ---
# ============================================================

echo ""
echo "============================================"
echo " STL Bounding Box Extractor v3"
echo "============================================"
echo " STL Dir    : $STL_DIR"
echo " BlockMesh  : $BLOCKMESH"
echo " SnappyHex  : $SNAPPYHEXMESH"
echo " BM Exclude : '$EXCLUDE_BLOCKMESH'"
echo " SHM Include: ${#SNAPPY_INCLUDE[@]} files"
echo "--------------------------------------------"
echo " SnappyHexMesh include list:"
for item in "${SNAPPY_INCLUDE[@]}"; do
    echo "   + $item"
done
echo "============================================"
echo ""

# ============================================================
# --- Main loop ---
# ============================================================

processed_blockmesh=0
processed_snappy=0

for f in "$STL_DIR"/*.stl; do

    filename=$(basename "$f")

    # Skip binary STLs
    if ! grep -qi "vertex" "$f"; then
        echo "  [BINARY - SKIPPED]    $filename"
        continue
    fi

    # Determine flags
    use_blockmesh=false
    use_snappy=false

    if ! echo "$filename" | grep -qiE "$EXCLUDE_BLOCKMESH"; then
        use_blockmesh=true
    fi

    if in_snappy_include "$filename"; then
        use_snappy=true
    fi

    # Skip if neither
    if ! $use_blockmesh && ! $use_snappy; then
        echo "  [SKIPPED - BOTH]      $filename"
        continue
    fi

    # Status label
    if $use_blockmesh && $use_snappy; then
        label="[BOTH]               "
    elif $use_blockmesh; then
        label="[BLOCKMESH ONLY]     "
    else
        label="[SNAPPY ONLY]        "
    fi

    echo "  $label $filename"

    # Extract bounds
    read XMIN XMAX YMIN YMAX ZMIN ZMAX <<< $(extract_bounds "$f")

    if [ -z "$XMIN" ] || [ -z "$XMAX" ]; then
        echo "  [WARNING] Could not extract bounds from $filename, skipping"
        continue
    fi

    echo "             X: [$XMIN, $XMAX]"
    echo "             Y: [$YMIN, $YMAX]"
    echo "             Z: [$ZMIN, $ZMAX]"
    echo ""

    # Update blockMesh bounds
    if $use_blockmesh; then
        GLOBAL_XMIN=$(awk "BEGIN {print ($XMIN < $GLOBAL_XMIN) ? $XMIN : $GLOBAL_XMIN}")
        GLOBAL_XMAX=$(awk "BEGIN {print ($XMAX > $GLOBAL_XMAX) ? $XMAX : $GLOBAL_XMAX}")
        GLOBAL_YMIN=$(awk "BEGIN {print ($YMIN < $GLOBAL_YMIN) ? $YMIN : $GLOBAL_YMIN}")
        GLOBAL_YMAX=$(awk "BEGIN {print ($YMAX > $GLOBAL_YMAX) ? $YMAX : $GLOBAL_YMAX}")
        GLOBAL_ZMIN=$(awk "BEGIN {print ($ZMIN < $GLOBAL_ZMIN) ? $ZMIN : $GLOBAL_ZMIN}")
        GLOBAL_ZMAX=$(awk "BEGIN {print ($ZMAX > $GLOBAL_ZMAX) ? $ZMAX : $GLOBAL_ZMAX}")
        ((processed_blockmesh++))
    fi

    # Update snappy bounds
    if $use_snappy; then
        GEO_XMIN=$(awk "BEGIN {print ($XMIN < $GEO_XMIN) ? $XMIN : $GEO_XMIN}")
        GEO_XMAX=$(awk "BEGIN {print ($XMAX > $GEO_XMAX) ? $XMAX : $GEO_XMAX}")
        GEO_YMIN=$(awk "BEGIN {print ($YMIN < $GEO_YMIN) ? $YMIN : $GEO_YMIN}")
        GEO_YMAX=$(awk "BEGIN {print ($YMAX > $GEO_YMAX) ? $YMAX : $GEO_YMAX}")
        GEO_ZMIN=$(awk "BEGIN {print ($ZMIN < $GEO_ZMIN) ? $ZMIN : $GEO_ZMIN}")
        GEO_ZMAX=$(awk "BEGIN {print ($ZMAX > $GEO_ZMAX) ? $ZMAX : $GEO_ZMAX}")
        ((processed_snappy++))
    fi

done

# ============================================================
# --- Validate ---
# ============================================================

if [ "$processed_blockmesh" -eq 0 ]; then
    echo "WARNING: No STLs processed for blockMesh"
    echo "         Check EXCLUDE_BLOCKMESH: '$EXCLUDE_BLOCKMESH'"
fi

if [ "$processed_snappy" -eq 0 ]; then
    echo "WARNING: No STLs matched SNAPPY_INCLUDE list"
    echo "         Actual files found:"
    for f in "$STL_DIR"/*.stl; do echo "           $(basename $f)"; done
    echo "         Your include list:"
    for item in "${SNAPPY_INCLUDE[@]}"; do echo "           $item"; done
    exit 1
fi

# ============================================================
# --- Print summaries ---
# ============================================================

echo "============================================"
echo " BLOCKMESH BOUNDS ($processed_blockmesh files)"
echo "============================================"
echo "  X: [$GLOBAL_XMIN, $GLOBAL_XMAX]  size: $(awk "BEGIN {print $GLOBAL_XMAX - $GLOBAL_XMIN}")"
echo "  Y: [$GLOBAL_YMIN, $GLOBAL_YMAX]  size: $(awk "BEGIN {print $GLOBAL_YMAX - $GLOBAL_YMIN}")"
echo "  Z: [$GLOBAL_ZMIN, $GLOBAL_ZMAX]  size: $(awk "BEGIN {print $GLOBAL_ZMAX - $GLOBAL_ZMIN}")"
echo ""
echo "============================================"
echo " SNAPPYHEXMESH BOUNDS ($processed_snappy files)"
echo "============================================"
echo "  X: [$GEO_XMIN, $GEO_XMAX]  size: $(awk "BEGIN {print $GEO_XMAX - $GEO_XMIN}")"
echo "  Y: [$GEO_YMIN, $GEO_YMAX]  size: $(awk "BEGIN {print $GEO_YMAX - $GEO_YMIN}")"
echo "  Z: [$GEO_ZMIN, $GEO_ZMAX]  size: $(awk "BEGIN {print $GEO_ZMAX - $GEO_ZMIN}")"
echo "============================================"
echo ""

# ============================================================
# --- Write to blockMeshDict (first occurrence only) ---
# ============================================================

echo " Writing to $BLOCKMESH ..."

write_first_occurrence "bbox_xmin" "$GLOBAL_XMIN" "$BLOCKMESH"
write_first_occurrence "bbox_xmax" "$GLOBAL_XMAX" "$BLOCKMESH"
write_first_occurrence "bbox_ymin" "$GLOBAL_YMIN" "$BLOCKMESH"
write_first_occurrence "bbox_ymax" "$GLOBAL_YMAX" "$BLOCKMESH"
write_first_occurrence "bbox_zmin" "$GLOBAL_ZMIN" "$BLOCKMESH"
write_first_occurrence "bbox_zmax" "$GLOBAL_ZMAX" "$BLOCKMESH"

echo " Verification — blockMeshDict:"
grep "bbox_" "$BLOCKMESH"
echo ""

# ============================================================
# --- Write to snappyHexMeshDict (first occurrence only) ---
# ============================================================

echo " Writing to $SNAPPYHEXMESH ..."

write_first_occurrence "bbox_xmin" "$GLOBAL_XMIN" "$SNAPPYHEXMESH"
write_first_occurrence "bbox_xmax" "$GLOBAL_XMAX" "$SNAPPYHEXMESH"
write_first_occurrence "bbox_ymin" "$GLOBAL_YMIN" "$SNAPPYHEXMESH"
write_first_occurrence "bbox_ymax" "$GLOBAL_YMAX" "$SNAPPYHEXMESH"
write_first_occurrence "bbox_zmin" "$GLOBAL_ZMIN" "$SNAPPYHEXMESH"
write_first_occurrence "bbox_zmax" "$GLOBAL_ZMAX" "$SNAPPYHEXMESH"

write_first_occurrence "geo_xmin" "$GEO_XMIN" "$SNAPPYHEXMESH"
write_first_occurrence "geo_xmax" "$GEO_XMAX" "$SNAPPYHEXMESH"
write_first_occurrence "geo_ymin" "$GEO_YMIN" "$SNAPPYHEXMESH"
write_first_occurrence "geo_ymax" "$GEO_YMAX" "$SNAPPYHEXMESH"
write_first_occurrence "geo_zmin" "$GEO_ZMIN" "$SNAPPYHEXMESH"
write_first_occurrence "geo_zmax" "$GEO_ZMAX" "$SNAPPYHEXMESH"

echo " Verification — snappyHexMeshDict bbox_:"
grep "bbox_" "$SNAPPYHEXMESH"
echo ""
echo " Verification — snappyHexMeshDict geo_:"
grep "geo_" "$SNAPPYHEXMESH"
echo ""
echo "============================================"
echo " Done."
echo "============================================"
