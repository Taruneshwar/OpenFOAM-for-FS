#!/bin/bash

# ============================================================
# KaHIP Installation and OpenFOAM Integration Script
# Installs KaHIP and builds the kahipDecomp library
# for OpenFOAM v2412
# ============================================================

# --- Configuration ---
KAHIP_INSTALL_DIR="$HOME/KaHIP/install"
KAHIP_SOURCE_DIR="$HOME/KaHIP"
OPENFOAM_BASHRC="/usr/lib/openfoam/openfoam2412/etc/bashrc"
OPENFOAM_KAHIP_SRC="/usr/lib/openfoam/openfoam2412/src/parallel/decompose/kahipDecomp"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# --- Helper functions ---
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN} [OK] $1${NC}"
}

print_error() {
    echo -e "${RED} [ERROR] $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW} [WARNING] $1${NC}"
}

print_step() {
    echo -e "\n${YELLOW} >>> $1${NC}"
}

# ============================================================
# --- Pre-flight checks ---
# ============================================================

print_header "Pre-flight Checks"

# Check OpenFOAM is available
if [ ! -f "$OPENFOAM_BASHRC" ]; then
    print_error "OpenFOAM not found at $OPENFOAM_BASHRC"
fi
print_success "OpenFOAM found at $OPENFOAM_BASHRC"

# Check required tools
for tool in git cmake make g++ ldconfig; do
    if ! command -v "$tool" &> /dev/null; then
        print_warning "$tool not found — will attempt to install"
        NEED_DEPS=true
    else
        print_success "$tool found"
    fi
done

# ============================================================
# --- Step 1: Install dependencies ---
# ============================================================

print_header "Step 1: Install Dependencies"

if [ "$NEED_DEPS" = true ]; then
    print_step "Installing build dependencies"
    sudo apt update && sudo apt install -y \
        cmake \
        g++ \
        git \
        libopenmpi-dev \
        openmpi-bin \
        build-essential
    if [ $? -ne 0 ]; then
        print_error "Failed to install dependencies"
    fi
    print_success "Dependencies installed"
else
    print_success "All dependencies already present"
fi

# ============================================================
# --- Step 2: Clone KaHIP ---
# ============================================================

print_header "Step 2: Clone KaHIP"

if [ -d "$KAHIP_SOURCE_DIR/.git" ]; then
    print_warning "KaHIP already cloned at $KAHIP_SOURCE_DIR"
    print_step "Pulling latest changes"
    cd "$KAHIP_SOURCE_DIR"
    git pull
else
    print_step "Cloning KaHIP from GitHub"
    git clone https://github.com/KaHIP/KaHIP.git "$KAHIP_SOURCE_DIR"
    if [ $? -ne 0 ]; then
        print_error "Failed to clone KaHIP"
    fi
    print_success "KaHIP cloned to $KAHIP_SOURCE_DIR"
fi

# ============================================================
# --- Step 3: Build KaHIP ---
# ============================================================

print_header "Step 3: Build KaHIP"

cd "$KAHIP_SOURCE_DIR"

# Clean previous build if exists
if [ -d "build" ]; then
    print_warning "Removing previous build directory"
    rm -rf build
fi

mkdir build && cd build

print_step "Running cmake"
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$KAHIP_INSTALL_DIR" \
    -DBUILD_SHARED_LIBS=ON

if [ $? -ne 0 ]; then
    print_error "cmake configuration failed"
fi
print_success "cmake configured"

print_step "Building KaHIP (using $(nproc) cores)"
make -j$(nproc)
if [ $? -ne 0 ]; then
    print_error "KaHIP build failed"
fi
print_success "KaHIP built"

print_step "Installing KaHIP to $KAHIP_INSTALL_DIR"
make install
if [ $? -ne 0 ]; then
    print_error "KaHIP installation failed"
fi
print_success "KaHIP installed"

# ============================================================
# --- Step 4: Verify KaHIP library ---
# ============================================================

print_header "Step 4: Verify KaHIP Library"

echo " Contents of $KAHIP_INSTALL_DIR/lib:"
ls -la "$KAHIP_INSTALL_DIR/lib/" 2>/dev/null

# Check for shared library
if ls "$KAHIP_INSTALL_DIR/lib/libkahip"*.so* &>/dev/null; then
    KAHIP_LIB=$(ls "$KAHIP_INSTALL_DIR/lib/libkahip"*.so* | head -1)
    print_success "Shared library found: $KAHIP_LIB"
else
    print_warning "Shared library (.so) not found"
    print_warning "Checking for static library..."

    if ls "$KAHIP_INSTALL_DIR/lib/libkahip"*.a* &>/dev/null; then
        print_warning "Only static library found — rebuilding with shared library flag"

        cd "$KAHIP_SOURCE_DIR/build"
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$KAHIP_INSTALL_DIR" \
            -DBUILD_SHARED_LIBS=ON \
            -DKAHIP_BUILD_SHARED_LIBRARY=ON

        make -j$(nproc) && make install

        if ls "$KAHIP_INSTALL_DIR/lib/libkahip"*.so* &>/dev/null; then
            print_success "Shared library built successfully"
        else
            print_error "Could not build shared library — check CMakeLists.txt"
        fi
    else
        print_error "No KaHIP library found at all"
    fi
fi

# ============================================================
# --- Step 5: Set environment variables ---
# ============================================================

print_header "Step 5: Set Environment Variables"

# Check if already in bashrc
if grep -q "KAHIP_ARCH_PATH" ~/.bashrc; then
    print_warning "KaHIP variables already in ~/.bashrc — updating"
    # Remove old entries
    sed -i '/# KaHIP/,/# End KaHIP/d' ~/.bashrc
fi

print_step "Writing environment variables to ~/.bashrc"

cat >> ~/.bashrc << EOF

# KaHIP
export KAHIP_ARCH_PATH=$KAHIP_INSTALL_DIR
export LD_LIBRARY_PATH=$KAHIP_INSTALL_DIR/lib:\$LD_LIBRARY_PATH
# End KaHIP
EOF

print_success "Environment variables written to ~/.bashrc"

# Apply to current session
export KAHIP_ARCH_PATH=$KAHIP_INSTALL_DIR
export LD_LIBRARY_PATH=$KAHIP_INSTALL_DIR/lib:$LD_LIBRARY_PATH

# Verify linker can find it
ldconfig -p | grep kahip
if [ $? -eq 0 ]; then
    print_success "Library visible to linker"
else
    print_warning "Library not yet visible to ldconfig — may need sudo ldconfig"
    sudo ldconfig "$KAHIP_INSTALL_DIR/lib"
fi

# ============================================================
# --- Step 6: Source OpenFOAM ---
# ============================================================

print_header "Step 6: Source OpenFOAM"

source "$OPENFOAM_BASHRC"
if [ $? -ne 0 ]; then
    print_error "Failed to source OpenFOAM"
fi
print_success "OpenFOAM sourced"
print_success "WM_PROJECT_USER_DIR: $WM_PROJECT_USER_DIR"
print_success "FOAM_USER_LIBBIN: $FOAM_USER_LIBBIN"

# ============================================================
# --- Step 7: Copy kahipDecomp to user directory ---
# ============================================================

print_header "Step 7: Copy kahipDecomp Source to User Directory"

USER_KAHIP_DIR="$WM_PROJECT_USER_DIR/src/parallel/decompose/kahipDecomp"

# Check system source exists
if [ ! -d "$OPENFOAM_KAHIP_SRC" ]; then
    print_error "kahipDecomp source not found at $OPENFOAM_KAHIP_SRC"
fi

# Create user directory
mkdir -p "$WM_PROJECT_USER_DIR/src/parallel/decompose/"

# Copy source
if [ -d "$USER_KAHIP_DIR" ]; then
    print_warning "User kahipDecomp directory already exists — removing and recopying"
    rm -rf "$USER_KAHIP_DIR"
fi

cp -r "$OPENFOAM_KAHIP_SRC" "$USER_KAHIP_DIR"
if [ $? -ne 0 ]; then
    print_error "Failed to copy kahipDecomp source"
fi
print_success "Copied to $USER_KAHIP_DIR"

# Verify ownership
echo " File ownership:"
ls -la "$USER_KAHIP_DIR"

# ============================================================
# --- Step 8: Build kahipDecomp ---
# ============================================================

print_header "Step 8: Build kahipDecomp OpenFOAM Library"

cd "$USER_KAHIP_DIR"

print_step "Running wmake"
wmake 2>&1

if [ $? -ne 0 ]; then
    echo ""
    print_error "wmake failed — check output above for details"
fi

print_success "kahipDecomp built successfully"

# ============================================================
# --- Step 9: Verify final build ---
# ============================================================

print_header "Step 9: Final Verification"

echo " Checking FOAM_USER_LIBBIN for kahipDecomp library:"
ls -la "$FOAM_USER_LIBBIN" | grep kahip

if ls "$FOAM_USER_LIBBIN/libkahipDecomp"* &>/dev/null; then
    print_success "libkahipDecomp found in $FOAM_USER_LIBBIN"
else
    print_error "libkahipDecomp not found — wmake may have failed silently"
fi

echo ""
echo " Checking LD_LIBRARY_PATH:"
echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -i kahip

# ============================================================
# --- Summary ---
# ============================================================

print_header "Installation Complete"

echo ""
echo " KaHIP installed at  : $KAHIP_INSTALL_DIR"
echo " Library             : $(ls $KAHIP_INSTALL_DIR/lib/libkahip*.so* 2>/dev/null | head -1)"
echo " OpenFOAM wrapper    : $FOAM_USER_LIBBIN/libkahipDecomp.so"
echo ""
echo " To use KaHIP in your case add to system/decomposeParDict:"
echo ""
echo "     numberOfSubdomains  8;"
echo "     method  kahip;"
echo "     kahipCoeffs"
echo "     {"
echo "         numberOfSubdomains  8;"
echo "         mode                FAST;"
echo "         imbalance           0.01;"
echo "     }"
echo ""
echo " And add to system/controlDict:"
echo ""
echo '     libs ( "libkahipDecomp.so" );'
echo ""
echo " Then run:"
echo "     source ~/.bashrc"
echo "     decomposePar"
echo ""
print_success "Done"
