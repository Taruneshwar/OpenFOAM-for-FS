#!/bin/bash

# ============================================================
# Local Mesh Script - Silent Edition
# Steps: surfaceFeatureExtract -> blockMesh -> decomposePar
#        -> snappyHexMesh -> reconstructParMesh -> renumberMesh
#        -> transformPoints -> checkMesh
# All output suppressed to console, saved to individual logs
# ============================================================

# --- Configuration ---
LOG_DIR="./logs"
N_PROCS=2

# ============================================================
# --- Logging helpers ---
# ============================================================

LOG_MAIN="$LOG_DIR/mesh_run.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_MAIN"
}

error_exit() {
    log "[ERROR] $1"
    log "[ERROR] Check: $2"
    log "Aborted : $(date)"
    exit 1
}

# Run a command silently — stdout+stderr to individual log
# Usage: run_step "name" "logfile.log" command args...
run_step() {
    local step_name="$1"
    local log_file="$LOG_DIR/$2"
    shift 2

    log ">>> Starting : $step_name"
    log "    Command  : $@"
    log "    Log      : $log_file"

    # Write header to step log
    {
        echo "============================================"
        echo " Step    : $step_name"
        echo " Command : $@"
        echo " Started : $(date)"
        echo "============================================"
        echo ""
    } > "$log_file"

    # Run — stdout and stderr both go to step log only, nothing to console
    "$@" >> "$log_file" 2>&1
    local exit_code=$?

    # Write footer to step log
    {
        echo ""
        echo "============================================"
        echo " Finished  : $(date)"
        echo " Exit code : $exit_code"
        echo "============================================"
    } >> "$log_file"

    if [ $exit_code -ne 0 ]; then
        error_exit "$step_name failed (exit $exit_code)" "$log_file"
    else
        log "    [OK] $step_name completed"
    fi

    return $exit_code
}

# ============================================================
# --- Initialize ---
# ============================================================

mkdir -p "$LOG_DIR"

{
    echo "============================================"
    echo " Local Mesh Run - Silent Edition"
    echo " Started : $(date)"
    echo " Procs   : $N_PROCS"
    echo "============================================"
    echo ""
} > "$LOG_MAIN"

# ============================================================
# --- Pre-flight checks ---
# ============================================================

log "--- Pre-flight Checks ---"

if ! command -v blockMesh &> /dev/null; then
    error_exit "OpenFOAM not loaded. Run: source /usr/lib/openfoam/openfoam2412/etc/bashrc" "$LOG_MAIN"
fi
log " [OK] OpenFOAM found"

if [ ! -f "system/surfaceFeatureExtractDict" ]; then
    error_exit "system/surfaceFeatureExtractDict not found" "$LOG_MAIN"
fi
log " [OK] surfaceFeatureExtractDict found"

if [ ! -f "system/blockMeshDict" ]; then
    error_exit "system/blockMeshDict not found" "$LOG_MAIN"
fi
log " [OK] blockMeshDict found"

if [ ! -f "system/snappyHexMeshDict" ]; then
    error_exit "system/snappyHexMeshDict not found" "$LOG_MAIN"
fi
log " [OK] snappyHexMeshDict found"

if [ ! -f "system/decomposeParDict" ]; then
    error_exit "system/decomposeParDict not found" "$LOG_MAIN"
fi
log " [OK] decomposeParDict found"

# ============================================================
# --- Step 4: surfaceFeatureExtract ---
# ============================================================

run_step "surfaceFeatureExtract" "04_surfaceFeatureExtract.log" \
    surfaceFeatureExtract

# ============================================================
# --- Step 5: blockMesh ---
# ============================================================

# Clean stale dynamicCode silently
if [ -d "dynamicCode" ]; then
    rm -rf dynamicCode
    log " [OK] Removed stale dynamicCode directory"
fi

run_step "blockMesh" "05_blockMesh.log" \
    blockMesh

# ============================================================
# --- Step 6: decomposePar ---
# ============================================================

run_step "decomposePar" "06_decomposePar.log" \
    decomposePar

# ============================================================
# --- Step 7: snappyHexMesh (parallel) ---
# ============================================================

run_step "snappyHexMesh" "07_snappyHexMesh.log" \
    mpirun -np "$N_PROCS" snappyHexMesh -overwrite -parallel

# ============================================================
# --- Step 8: reconstructParMesh ---
# ============================================================

run_step "reconstructParMesh" "08_reconstructParMesh.log" \
    reconstructParMesh -constant

# ============================================================
# --- Step 9: renumberMesh ---
# ============================================================

run_step "renumberMesh" "09_renumberMesh.log" \
    renumberMesh -overwrite

# ============================================================
# --- Step 10: transformPoints ---
# ============================================================

run_step "transformPoints" "10_transformPoints.log" \
    transformPoints -scale 0.001

# ============================================================
# --- Step 11: checkMesh ---
# ============================================================

run_step "checkMesh" "11_checkMesh.log" \
    checkMesh -writeAllFields

# ============================================================
# --- Summary ---
# ============================================================

{
    echo ""
    echo "============================================"
    echo " All steps completed successfully"
    echo " Finished : $(date)"
    echo ""
    echo " Individual logs:"
    for f in "$LOG_DIR"/*.log; do
        lines=$(wc -l < "$f")
        echo "   $(basename $f)  ($lines lines)"
    done
    echo "============================================"
} >> "$LOG_MAIN"

exit 0
