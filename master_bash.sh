#!/bin/bash

# ============================================================
# OpenFOAM Case Setup and Run Script
# Runs all steps in series with individual log files
# ============================================================

# --- Configuration ---
LOG_DIR="./logs"
STL_SOURCE="./../stlGeometry"
TRISURFACE_DIR="./constant/triSurface"
BOUNDS_SCRIPT="./extract_bounds.sh"

# --- Colors for terminal output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# --- Helper functions ---
# ============================================================

# Print section header
print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# Print success
print_success() {
    echo -e "${GREEN} [OK] $1${NC}"
}

# Print error and exit
print_error() {
    echo -e "${RED} [ERROR] $1${NC}"
    echo -e "${RED} Check log: $2${NC}"
    exit 1
}

# Print warning
print_warning() {
    echo -e "${YELLOW} [WARNING] $1${NC}"
}

# Print step info
print_step() {
    echo -e "\n${YELLOW} >>> $1${NC}"
}

# Run a command, save output to log, check exit code
# Usage: run_step "Step Name" "log_filename.log" command args...
run_step() {
    local step_name="$1"
    local log_file="$LOG_DIR/$2"
    shift 2
    local cmd="$@"

    print_step "$step_name"
    echo " Command : $cmd"
    echo " Log     : $log_file"
    echo ""

    # Write header to log file
    {
        echo "============================================"
        echo " Step     : $step_name"
        echo " Command  : $cmd"
        echo " Started  : $(date)"
        echo "============================================"
        echo ""
    } > "$log_file"

    # Run command, append output to log, also stream to terminal
    "$@" 2>&1 | tee -a "$log_file"
    local exit_code=${PIPESTATUS[0]}

    # Write footer to log
    {
        echo ""
        echo "============================================"
        echo " Finished : $(date)"
        echo " Exit code: $exit_code"
        echo "============================================"
    } >> "$log_file"

    if [ $exit_code -ne 0 ]; then
        print_error "$step_name failed with exit code $exit_code" "$log_file"
    else
        print_success "$step_name completed successfully"
    fi

    return $exit_code
}

# ============================================================
# --- Pre-flight checks ---
# ============================================================

print_header "Pre-flight Checks"

# Check STL source exists
if [ ! -d "$STL_SOURCE" ]; then
    echo -e "${RED} [ERROR] STL source directory not found: $STL_SOURCE${NC}"
    exit 1
fi
print_success "STL source found: $STL_SOURCE"

# Check bounds script exists
if [ ! -f "$BOUNDS_SCRIPT" ]; then
    echo -e "${RED} [ERROR] extract_bounds.sh not found at: $BOUNDS_SCRIPT${NC}"
    exit 1
fi
print_success "extract_bounds.sh found"

# Check OpenFOAM is loaded
if ! command -v blockMesh &> /dev/null; then
    echo -e "${RED} [ERROR] OpenFOAM not loaded. Source your OpenFOAM bashrc first:${NC}"
    echo "         source /usr/lib/openfoam/openfoam2412/etc/bashrc"
    exit 1
fi
print_success "OpenFOAM found: $(blockMesh --version 2>&1 | head -1)"

# ============================================================
# --- Create log directory ---
# ============================================================

print_header "Creating Directories"

if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    print_success "Created log directory: $LOG_DIR"
else
    print_warning "Log directory already exists: $LOG_DIR"
fi

# ============================================================
# --- Step 1: Create triSurface directory ---
# ============================================================

print_header "Step 1: Create triSurface Directory"

if [ ! -d "$TRISURFACE_DIR" ]; then
    mkdir -p "$TRISURFACE_DIR"
    print_success "Created: $TRISURFACE_DIR"
else
    print_warning "Already exists: $TRISURFACE_DIR"
fi

# Log the directory creation
{
    echo "============================================"
    echo " Step     : Create triSurface directory"
    echo " Started  : $(date)"
    echo "============================================"
    echo " Directory: $TRISURFACE_DIR"
    if [ -d "$TRISURFACE_DIR" ]; then
        echo " Status   : exists"
    fi
    echo " Finished : $(date)"
    echo "============================================"
} > "$LOG_DIR/01_mkdir_triSurface.log"

# ============================================================
# --- Step 2: Create symlinks for STL files ---
# ============================================================

print_header "Step 2: Create STL Symlinks"
print_step "Linking STL files from $STL_SOURCE"

{
    echo "============================================"
    echo " Step     : Create STL symlinks"
    echo " Source   : $STL_SOURCE"
    echo " Target   : $TRISURFACE_DIR"
    echo " Started  : $(date)"
    echo "============================================"
    echo ""
} > "$LOG_DIR/02_symlinks.log"

linked=0
skipped=0
failed=0

for f in "$STL_SOURCE"/*.stl; do

    filename=$(basename "$f")
    target="$TRISURFACE_DIR/$filename"
    abs_source="$(realpath "$f")"

    if [ -L "$target" ]; then
        echo " [SKIPPED - exists] $filename"
        echo " [SKIPPED] $filename" >> "$LOG_DIR/02_symlinks.log"
        ((skipped++))
    elif [ -f "$target" ]; then
        echo " [SKIPPED - file exists] $filename"
        echo " [SKIPPED - real file] $filename" >> "$LOG_DIR/02_symlinks.log"
        ((skipped++))
    else
        ln -s "$abs_source" "$target"
        if [ $? -eq 0 ]; then
            echo " [LINKED] $filename"
            echo " [LINKED] $filename -> $abs_source" >> "$LOG_DIR/02_symlinks.log"
            ((linked++))
        else
            echo -e "${RED} [FAILED] $filename${NC}"
            echo " [FAILED] $filename" >> "$LOG_DIR/02_symlinks.log"
            ((failed++))
        fi
    fi

done

{
    echo ""
    echo "============================================"
    echo " Linked  : $linked"
    echo " Skipped : $skipped"
    echo " Failed  : $failed"
    echo " Finished: $(date)"
    echo "============================================"
} >> "$LOG_DIR/02_symlinks.log"

if [ $failed -gt 0 ]; then
    print_error "Some symlinks failed to create" "$LOG_DIR/02_symlinks.log"
fi

print_success "Symlinks: $linked created, $skipped skipped, $failed failed"

# ============================================================
# --- Step 3: Run extract_bounds.sh ---
# ============================================================

print_header "Step 3: Extract Bounds"

chmod +x "$BOUNDS_SCRIPT"
run_step "Extract Bounds" "03_extract_bounds.log" bash "$BOUNDS_SCRIPT"

# ============================================================
# --- Step 4: surfaceFeatureExtract ---
# ============================================================

print_header "Step 4: Surface Feature Extract"

run_step "surfaceFeatureExtract" "04_surfaceFeatureExtract.log" surfaceFeatureExtract

# ============================================================
# --- Step 5: blockMesh ---
# ============================================================

print_header "Step 5: blockMesh"

# Clean stale dynamicCode before blockMesh
if [ -d "dynamicCode" ]; then
    print_warning "Removing stale dynamicCode directory"
    rm -rf dynamicCode
fi

run_step "blockMesh" "05_blockMesh.log" blockMesh

# ============================================================
# --- Step 6: decomposePar Mesh (KaHIP) ---
# ============================================================

print_header "Step 6: decomposePar"

run_step "decomposePar" "06_decomposeParMesh.log" decomposePar

# ============================================================
# --- Step 7: snappyHexMesh (parallel) ---
# ============================================================

print_header "Step 7: snappyHexMesh"

run_step "snappyHexMesh" "07_snappyHexMesh.log" mpirun -np 2 snappyHexMesh -overwrite -parallel

# ============================================================
# --- Step 8: reconstructParMesh ---
# ============================================================

print_header "Step 8: reconstructParMesh"

run_step "reconstructParMesh" "08_reconstructParMesh.log" reconstructParMesh -constant

# ============================================================
# --- Step 9: renumberMesh ---
# ============================================================

print_header "Step 9: renumberMesh"

run_step "renumberMesh" "09_renumberMesh.log" renumberMesh -overwrite

# ============================================================
# --- Step 10: transformpoints ---
# ============================================================

print_header "Step 10: transformPoints"

run_step "transformPoints" "10_transformPoints.log" transformPoints -scale 0.001

# ============================================================
# --- Step 11: checkMesh ---
# ============================================================

print_header "Step 11: checkMesh"

run_step "checkMesh" "11_checkMesh.log" checkMesh -writeAllFields


## ============================================================
## --- Step 7: checkMesh ---
## ============================================================
#
#print_header "Step 7: checkMesh"
#
#run_step "checkMesh" "07_checkMesh.log" checkMesh

# ============================================================
# --- Summary ---
# ============================================================

print_header "Run Complete"

echo ""
echo " Log files saved in: $LOG_DIR"
echo ""
echo " Individual logs:"
for log in "$LOG_DIR"/*.log; do
    size=$(wc -l < "$log")
    echo "   $(basename $log)  ($size lines)"
done
echo ""

print_success "All steps completed successfully"
echo ""
