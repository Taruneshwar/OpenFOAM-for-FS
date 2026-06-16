#!/bin/bash

# ============================================================
# OpenFOAM Pre-Mesh + STL Bounds Script - Silent Edition
# Combines:
#   1) _preMesh.sh
#      - create constant/triSurface
#      - create STL symlinks from ../stlGeometry
#   2) _extract_bounds.sh
#      - extract STL bounding boxes
#      - write bbox_* values to system/blockMeshDict
#      - write bbox_* and geo_* values to system/snappyHexMeshDict
#
# Console output:
#   - none during normal operation
#   - all stdout/stderr goes to logs/00_preMesh_extract_bounds.log
# ============================================================

# --- Configuration ---
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/00_preMesh_extract_bounds.log"

STL_SOURCE="./../stlGeometry"
TRISURFACE_DIR="./constant/triSurface"
STL_DIR="$TRISURFACE_DIR"

BLOCKMESH="./system/blockMeshDict"
SNAPPYHEXMESH="./system/snappyHexMeshDict"

# Keywords excluded from blockMesh bounds.
# Example: body means any STL with "body" in the filename is excluded from blockMesh bounds.
EXCLUDE_BLOCKMESH="body"

# Explicit list of STLs used for snappyHexMesh geometry bounds.
SNAPPY_INCLUDE=(
    "drivaerBody.stl"
    "frontLeftTire.stl"
    "frontRightTire.stl"
    "rearLeftTire.stl"
    "rearRightTire.stl"
)

# ============================================================
# --- Silent logging setup ---
# ============================================================

mkdir -p "$LOG_DIR"
exec > "$LOG_FILE" 2>&1

log() {
    echo "$1"
}

error_exit() {
    log ""
    log "[ERROR] $1"
    log "Finished : $(date)"
    log "Exit     : 1"
    log "============================================"
    exit 1
}

log "============================================"
log " OpenFOAM Pre-Mesh + Bounds - Silent Edition"
log " Started        : $(date)"
log " STL Source     : $STL_SOURCE"
log " triSurface Dir : $TRISURFACE_DIR"
log " BlockMeshDict  : $BLOCKMESH"
log " SnappyDict     : $SNAPPYHEXMESH"
log "============================================"
log ""

# ============================================================
# --- Pre-flight checks ---
# ============================================================

log "--------------------------------------------"
log " Pre-flight Checks"
log "--------------------------------------------"


if ! command -v blockMesh >/dev/null 2>&1; then
    error_exit "OpenFOAM not loaded. Run: source /usr/lib/openfoam/openfoam2412/etc/bashrc"
fi
log "[OK] OpenFOAM found: $(blockMesh --version 2>&1 | head -1)"

[ ! -f "$BLOCKMESH" ] && error_exit "blockMeshDict not found: $BLOCKMESH"
[ ! -f "$SNAPPYHEXMESH" ] && error_exit "snappyHexMeshDict not found: $SNAPPYHEXMESH"
log "[OK] Dictionary files found"

# ============================================================
# --- Bounds helper functions ---
# ============================================================

in_snappy_include() {
    local target="${1,,}"
    local item
    for item in "${SNAPPY_INCLUDE[@]}"; do
        if [ "${item,,}" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

extract_bounds() {
    grep -i "vertex" "$1" | awk '
    BEGIN {
        xmin=999999999; xmax=-999999999
        ymin=999999999; ymax=-999999999
        zmin=999999999; zmax=-999999999
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

write_first_occurrence() {
    local varname="$1"
    local value="$2"
    local file="$3"
    local lineno

    lineno=$(grep -n "\b${varname}\b" "$file" | head -1 | cut -d: -f1)

    if [ -z "$lineno" ]; then
        log "[WARNING] '$varname' not found in $file"
        return 1
    fi

    awk -v n="$lineno" -v name="$varname" -v val="$value" '
        NR==n {
            match($0, /^[[:space:]]*/)
            indent=substr($0, RSTART, RLENGTH)
            print indent name " " val ";"
            next
        }
        { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ============================================================
# --- Step 3: Sanity checks before bounds extraction ---
# ============================================================

log ""
log "--------------------------------------------"
log " Step 3: Bounds Extraction Checks"
log "--------------------------------------------"

stl_files=("$STL_DIR"/*.stl "$STL_DIR"/*.STL)
[ ${#stl_files[@]} -eq 0 ] && error_exit "No STL files found in $STL_DIR"

if ! grep -q "bbox_xmin" "$BLOCKMESH"; then
    error_exit "bbox_xmin not found in $BLOCKMESH"
fi

if ! grep -q "bbox_xmin" "$SNAPPYHEXMESH"; then
    error_exit "bbox_xmin not found in $SNAPPYHEXMESH"
fi

if ! grep -q "geo_xmin" "$SNAPPYHEXMESH"; then
    error_exit "geo_xmin not found in $SNAPPYHEXMESH"
fi

log "[OK] STL and dictionary markers found"

# ============================================================
# --- Step 4: Extract bounds ---
# ============================================================

log ""
log "--------------------------------------------"
log " Step 4: Extract STL Bounds"
log "--------------------------------------------"
log "BlockMesh exclude pattern : $EXCLUDE_BLOCKMESH"
log "Snappy include count      : ${#SNAPPY_INCLUDE[@]}"

GLOBAL_XMIN=999999999; GLOBAL_XMAX=-999999999
GLOBAL_YMIN=999999999; GLOBAL_YMAX=-999999999
GLOBAL_ZMIN=999999999; GLOBAL_ZMAX=-999999999

GEO_XMIN=999999999; GEO_XMAX=-999999999
GEO_YMIN=999999999; GEO_YMAX=-999999999
GEO_ZMIN=999999999; GEO_ZMAX=-999999999

processed_blockmesh=0
processed_snappy=0
skipped_binary=0
skipped_other=0

for f in "${stl_files[@]}"; do
    filename=$(basename "$f")

    if ! grep -qi "vertex" "$f"; then
        log "[BINARY - SKIPPED] $filename"
        ((skipped_binary++))
        continue
    fi

    use_blockmesh=false
    use_snappy=false

    if ! echo "$filename" | grep -qiE "$EXCLUDE_BLOCKMESH"; then
        use_blockmesh=true
    fi

    if in_snappy_include "$filename"; then
        use_snappy=true
    fi

    if ! $use_blockmesh && ! $use_snappy; then
        log "[SKIPPED - BOTH] $filename"
        ((skipped_other++))
        continue
    fi

    read XMIN XMAX YMIN YMAX ZMIN ZMAX <<< "$(extract_bounds "$f")"

    if [ -z "$XMIN" ] || [ -z "$XMAX" ]; then
        log "[WARNING] Could not extract bounds from $filename, skipping"
        ((skipped_other++))
        continue
    fi

    log "[PROCESSED] $filename"
    log "  X: [$XMIN, $XMAX]"
    log "  Y: [$YMIN, $YMAX]"
    log "  Z: [$ZMIN, $ZMAX]"

    if $use_blockmesh; then
        GLOBAL_XMIN=$(awk "BEGIN {print ($XMIN < $GLOBAL_XMIN) ? $XMIN : $GLOBAL_XMIN}")
        GLOBAL_XMAX=$(awk "BEGIN {print ($XMAX > $GLOBAL_XMAX) ? $XMAX : $GLOBAL_XMAX}")
        GLOBAL_YMIN=$(awk "BEGIN {print ($YMIN < $GLOBAL_YMIN) ? $YMIN : $GLOBAL_YMIN}")
        GLOBAL_YMAX=$(awk "BEGIN {print ($YMAX > $GLOBAL_YMAX) ? $YMAX : $GLOBAL_YMAX}")
        GLOBAL_ZMIN=$(awk "BEGIN {print ($ZMIN < $GLOBAL_ZMIN) ? $ZMIN : $GLOBAL_ZMIN}")
        GLOBAL_ZMAX=$(awk "BEGIN {print ($ZMAX > $GLOBAL_ZMAX) ? $ZMAX : $GLOBAL_ZMAX}")
        ((processed_blockmesh++))
    fi

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

[ "$processed_blockmesh" -eq 0 ] && log "[WARNING] No STLs processed for blockMesh"

if [ "$processed_snappy" -eq 0 ]; then
    log "[ERROR] No STLs matched SNAPPY_INCLUDE list"
    log "Actual files found:"
    for f in "${stl_files[@]}"; do log "  $(basename "$f")"; done
    log "Configured SNAPPY_INCLUDE list:"
    for item in "${SNAPPY_INCLUDE[@]}"; do log "  $item"; done
    error_exit "No STLs matched SNAPPY_INCLUDE list"
fi

log ""
log "BlockMesh STLs processed : $processed_blockmesh"
log "Snappy STLs processed    : $processed_snappy"
log "Binary STLs skipped      : $skipped_binary"
log "Other STLs skipped       : $skipped_other"

log ""
log "BLOCKMESH BOUNDS"
log "X: [$GLOBAL_XMIN, $GLOBAL_XMAX] size: $(awk "BEGIN {print $GLOBAL_XMAX - $GLOBAL_XMIN}")"
log "Y: [$GLOBAL_YMIN, $GLOBAL_YMAX] size: $(awk "BEGIN {print $GLOBAL_YMAX - $GLOBAL_YMIN}")"
log "Z: [$GLOBAL_ZMIN, $GLOBAL_ZMAX] size: $(awk "BEGIN {print $GLOBAL_ZMAX - $GLOBAL_ZMIN}")"

log ""
log "SNAPPYHEXMESH GEOMETRY BOUNDS"
log "X: [$GEO_XMIN, $GEO_XMAX] size: $(awk "BEGIN {print $GEO_XMAX - $GEO_XMIN}")"
log "Y: [$GEO_YMIN, $GEO_YMAX] size: $(awk "BEGIN {print $GEO_YMAX - $GEO_YMIN}")"
log "Z: [$GEO_ZMIN, $GEO_ZMAX] size: $(awk "BEGIN {print $GEO_ZMAX - $GEO_ZMIN}")"

# ============================================================
# --- Step 5: Write bounds to dictionaries ---
# ============================================================

log ""
log "--------------------------------------------"
log " Step 5: Write Bounds to Dictionaries"
log "--------------------------------------------"

log "Writing bbox_* to $BLOCKMESH"
write_first_occurrence "bbox_xmin" "$GLOBAL_XMIN" "$BLOCKMESH"
write_first_occurrence "bbox_xmax" "$GLOBAL_XMAX" "$BLOCKMESH"
write_first_occurrence "bbox_ymin" "$GLOBAL_YMIN" "$BLOCKMESH"
write_first_occurrence "bbox_ymax" "$GLOBAL_YMAX" "$BLOCKMESH"
write_first_occurrence "bbox_zmin" "$GLOBAL_ZMIN" "$BLOCKMESH"
write_first_occurrence "bbox_zmax" "$GLOBAL_ZMAX" "$BLOCKMESH"

log "Writing bbox_* and geo_* to $SNAPPYHEXMESH"
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

log ""
log "Verification - blockMeshDict bbox_:"
grep "bbox_" "$BLOCKMESH" || true

log ""
log "Verification - snappyHexMeshDict bbox_:"
grep "bbox_" "$SNAPPYHEXMESH" || true

log ""
log "Verification - snappyHexMeshDict geo_:"
grep "geo_" "$SNAPPYHEXMESH" || true

log ""
log "============================================"
log " All pre-mesh and bounds steps completed"
log " Finished : $(date)"
log " Exit     : 0"
log "============================================"

exit 0
