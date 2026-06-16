#!/bin/bash

# ============================================================
# OpenFOAM Case Setup Script - Silent Edition
# Steps 1-2 only: triSurface dir + STL symlinks
# All output goes to log file, nothing to console
# ============================================================

# --- Configuration ---
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/00_setup.log"
STL_SOURCE="./../stlGeometry"
TRISURFACE_DIR="./constant/triSurface"

# ============================================================
# --- Logging helper ---
# ============================================================

log() {
    echo "$1" >> "$LOG_FILE"
}

error_exit() {
    log ""
    log "[ERROR] $1"
    log "Finished : $(date)"
    log "============================================"
    exit 1
}

# ============================================================
# --- Initialize log ---
# ============================================================

mkdir -p "$LOG_DIR"

{
    echo "============================================"
    echo " OpenFOAM Case Setup - Silent Edition"
    echo " Started  : $(date)"
    echo " STL Source     : $STL_SOURCE"
    echo " triSurface Dir : $TRISURFACE_DIR"
    echo "============================================"
    echo ""
} > "$LOG_FILE"

# ============================================================
# --- Pre-flight checks ---
# ============================================================

log "--------------------------------------------"
log " Pre-flight Checks"
log "--------------------------------------------"

[ ! -d "$STL_SOURCE" ] && error_exit "STL source directory not found: $STL_SOURCE"
log " [OK] STL source found: $STL_SOURCE"

if ! command -v blockMesh &> /dev/null; then
    error_exit "OpenFOAM not loaded. Run: source /usr/lib/openfoam/openfoam2412/etc/bashrc"
fi
log " [OK] OpenFOAM found: $(blockMesh --version 2>&1 | head -1)"

# ============================================================
# --- Step 1: Create triSurface directory ---
# ============================================================

log ""
log "--------------------------------------------"
log " Step 1: Create triSurface Directory"
log "--------------------------------------------"
log " Started : $(date)"

if [ ! -d "$TRISURFACE_DIR" ]; then
    mkdir -p "$TRISURFACE_DIR"
    if [ $? -eq 0 ]; then
        log " [OK] Created: $TRISURFACE_DIR"
    else
        error_exit "Failed to create directory: $TRISURFACE_DIR"
    fi
else
    log " [SKIPPED] Already exists: $TRISURFACE_DIR"
fi

log " Finished : $(date)"

# ============================================================
# --- Step 2: Create symlinks for STL files ---
# ============================================================

log ""
log "--------------------------------------------"
log " Step 2: Create STL Symlinks"
log "--------------------------------------------"
log " Source  : $STL_SOURCE"
log " Target  : $TRISURFACE_DIR"
log " Started : $(date)"
log ""

linked=0
skipped=0
failed=0

for f in "$STL_SOURCE"/*.stl; do

    filename=$(basename "$f")
    target="$TRISURFACE_DIR/$filename"
    abs_source="$(realpath "$f")"

    if [ -L "$target" ]; then
        log " [SKIPPED - symlink exists] $filename"
        ((skipped++))
    elif [ -f "$target" ]; then
        log " [SKIPPED - file exists]   $filename"
        ((skipped++))
    else
        ln -s "$abs_source" "$target" 2>> "$LOG_FILE"
        if [ $? -eq 0 ]; then
            log " [LINKED]  $filename -> $abs_source"
            ((linked++))
        else
            log " [FAILED]  $filename"
            ((failed++))
        fi
    fi

done

log ""
log " Linked  : $linked"
log " Skipped : $skipped"
log " Failed  : $failed"
log " Finished : $(date)"

[ $failed -gt 0 ] && error_exit "Some symlinks failed to create — check log: $LOG_FILE"

# ============================================================
# --- Done ---
# ============================================================

{
    echo ""
    echo "============================================"
    echo " All steps completed successfully"
    echo " Finished : $(date)"
    echo " Exit     : 0"
    echo "============================================"
} >> "$LOG_FILE"
