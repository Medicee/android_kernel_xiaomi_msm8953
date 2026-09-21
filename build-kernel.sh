#!/bin/bash

###############################################################################
# Kernel Build Script for Xiaomi Mi A1 (tissot)
# Usage: ./build-kernel.sh [options]
# Options:
#   -c, --clean         Clean before build
#   -m, --modules       Build modules
#   -d, --defconfig     Specify defconfig file
#   -o, --output        Output directory (default: out)
#   -j, --jobs          Number of parallel jobs (default: nproc)
#   -t, --toolchain     Toolchain type: clang, gcc, auto (default: auto)
#   -v, --verbose       Verbose output
#   -h, --help          Show this help
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEVICE="tissot"
ARCH="arm64"
SUBARCH="arm64"
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-tissot_defconfig}"
OUT_DIR="${OUT_DIR:-out}"
JOBS="${JOBS:-$(nproc)}"
TOOLCHAIN="auto"
CLEAN_BUILD=0
BUILD_MODULES=0
VERBOSE=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$(pwd)"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/toolchain}"
GCC_TOOLCHAIN_DIR="${GCC_TOOLCHAIN_DIR:-$HOME/gcc-toolchain}"

# Build tools
CLANG_VERSION="r416183b"
GCC_CROSS_COMPILE="aarch64-linux-gnu-"

###############################################################################
# Functions
###############################################################################

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -18 "$0" | tail -16
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    local deps=("make" "gcc" "flex" "bison")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "$dep not found. Please install it."
            exit 1
        fi
    done
    
    print_success "All dependencies found"
}

check_toolchain() {
    print_info "Checking toolchain..."
    
    if [ "$TOOLCHAIN" = "auto" ]; then
        if command -v clang &> /dev/null; then
            TOOLCHAIN="clang"
            print_success "Using CLANG toolchain"
        elif [ -f "$TOOLCHAIN_DIR/clang_r$CLANG_VERSION/bin/clang" ]; then
            TOOLCHAIN="clang"
            export PATH="$TOOLCHAIN_DIR/clang_r$CLANG_VERSION/bin:$PATH"
            print_success "Using downloaded CLANG toolchain"
        elif command -v aarch64-linux-gnu-gcc &> /dev/null; then
            TOOLCHAIN="gcc"
            print_success "Using GCC toolchain"
        else
            print_warning "No suitable toolchain found. Installing GCC..."
            install_gcc_toolchain
        fi
    fi
    
    case "$TOOLCHAIN" in
        clang)
            if ! command -v clang &> /dev/null && [ ! -f "$TOOLCHAIN_DIR/clang_r$CLANG_VERSION/bin/clang" ]; then
                print_error "CLANG not found. Download from: https://android.googlesource.com/platform/prebuilts/clang/"
                exit 1
            fi
            print_success "CLANG toolchain ready"
            ;;
        gcc)
            if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
                print_warning "GCC ARM64 cross compiler not found"
                install_gcc_toolchain
            fi
            print_success "GCC toolchain ready"
            ;;
        *)
            print_error "Unknown toolchain: $TOOLCHAIN"
            exit 1
            ;;
    esac
}

install_gcc_toolchain() {
    print_info "Installing GCC ARM64 toolchain..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
    elif command -v pacman &> /dev/null; then
        sudo pacman -S aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils
    elif command -v yum &> /dev/null; then
        sudo yum install -y gcc-c++-aarch64-linux-gnu binutils-aarch64-linux-gnu
    else
        print_error "Package manager not found. Please install gcc-aarch64-linux-gnu manually."
        exit 1
    fi
}

clean_build() {
    print_info "Cleaning build directory..."
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    print_success "Build directory cleaned"
}

setup_config() {
    print_info "Setting up kernel configuration..."
    
    mkdir -p "$OUT_DIR"
    
    # Try multiple config sources
    if [ -f "arch/$ARCH/configs/$KERNEL_DEFCONFIG" ]; then
        cp "arch/$ARCH/configs/$KERNEL_DEFCONFIG" "$OUT_DIR/.config"
        print_success "Using kernel defconfig from arch/"
    elif [ -f "$KERNEL_DEFCONFIG" ]; then
        cp "$KERNEL_DEFCONFIG" "$OUT_DIR/.config"
        print_success "Using provided defconfig"
    elif [ -f "arch/arm64/configs/tissot_defconfig" ]; then
        cp "arch/arm64/configs/tissot_defconfig" "$OUT_DIR/.config"
        print_success "Using tissot_defconfig"
    else
        print_error "No defconfig found!"
        echo "Searched for:"
        echo "  - arch/$ARCH/configs/$KERNEL_DEFCONFIG"
        echo "  - $KERNEL_DEFCONFIG"
        exit 1
    fi
    
    # Generate config from defconfig
    make O="$OUT_DIR" ARCH="$ARCH" olddefconfig 2>&1 | grep -v "^#" || true
    print_success "Kernel configuration ready"
}

build_kernel() {
    print_info "Building kernel (${JOBS} jobs)..."
    
    local make_opts=(
        "O=$OUT_DIR"
        "ARCH=$ARCH"
        "-j$JOBS"
    )
    
    if [ "$VERBOSE" = "1" ]; then
        make_opts+=("V=1")
    fi
    
    case "$TOOLCHAIN" in
        clang)
            print_info "Using CLANG compiler..."
            if [ -d "$TOOLCHAIN_DIR/clang_r$CLANG_VERSION" ]; then
                export PATH="$TOOLCHAIN_DIR/clang_r$CLANG_VERSION/bin:$PATH"
            fi
            
            make_opts+=(
                "CC=clang"
                "LD=ld.lld"
                "CLANG_TRIPLE=aarch64-linux-gnu-"
            )
            ;;
        gcc)
            print_info "Using GCC compiler..."
            make_opts+=(
                "CROSS_COMPILE=$GCC_CROSS_COMPILE"
            )
            ;;
    esac
    
    if ! make "${make_opts[@]}"; then
        print_error "Kernel build failed!"
        exit 1
    fi
    
    print_success "Kernel build completed"
}

build_modules() {
    if [ "$BUILD_MODULES" = "0" ]; then
        return
    fi
    
    print_info "Building kernel modules..."
    
    local make_opts=(
        "O=$OUT_DIR"
        "ARCH=$ARCH"
        "-j$JOBS"
    )
    
    case "$TOOLCHAIN" in
        clang)
            make_opts+=(
                "CC=clang"
                "LD=ld.lld"
            )
            ;;
        gcc)
            make_opts+=(
                "CROSS_COMPILE=$GCC_CROSS_COMPILE"
            )
            ;;
    esac
    
    if ! make "${make_opts[@]}" modules modules_install INSTALL_MOD_PATH="$OUT_DIR/modules"; then
        print_error "Module build failed!"
        exit 1
    fi
    
    print_success "Modules built successfully"
}

collect_artifacts() {
    print_info "Collecting build artifacts..."
    
    local artifacts_dir="artifacts"
    mkdir -p "$artifacts_dir"
    
    # Kernel image
    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        cp "$OUT_DIR/arch/arm64/boot/Image" "$artifacts_dir/"
        print_success "Copied kernel Image"
    elif [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
        cp "$OUT_DIR/arch/arm64/boot/Image.gz" "$artifacts_dir/"
        print_success "Copied kernel Image.gz"
    else
        print_warning "Kernel image not found"
    fi
    
    # Device tree blobs
    if [ -d "$OUT_DIR/arch/arm64/boot/dts" ]; then
        find "$OUT_DIR/arch/arm64/boot/dts" -name "*.dtb" -exec cp {} "$artifacts_dir/" \; 2>/dev/null || true
        print_success "Copied device tree blobs"
    fi
    
    # Configuration
    if [ -f "$OUT_DIR/.config" ]; then
        cp "$OUT_DIR/.config" "$artifacts_dir/config-$DEVICE"
        print_success "Copied kernel config"
    fi
    
    # vmlinux (for debugging)
    if [ -f "$OUT_DIR/vmlinux" ]; then
        cp "$OUT_DIR/vmlinux" "$artifacts_dir/"
        print_success "Copied vmlinux"
    fi
    
    # Modules
    if [ -d "$OUT_DIR/modules" ] && [ "$(ls -A "$OUT_DIR/modules")" ]; then
        tar -czf "$artifacts_dir/modules-$DEVICE.tar.gz" -C "$OUT_DIR" modules/
        print_success "Packaged modules"
    fi
    
    # System.map
    if [ -f "$OUT_DIR/System.map" ]; then
        cp "$OUT_DIR/System.map" "$artifacts_dir/"
        print_success "Copied System.map"
    fi
    
    # Summary
    echo ""
    print_info "Artifacts collected in: $artifacts_dir/"
    ls -lh "$artifacts_dir/" 2>/dev/null | tail -n +2
}

print_summary() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Build Summary${NC}"
    echo -e "${BLUE}================================${NC}"
    echo "Device: $DEVICE"
    echo "Architecture: $ARCH"
    echo "Toolchain: $TOOLCHAIN"
    echo "Defconfig: $KERNEL_DEFCONFIG"
    echo "Output Dir: $OUT_DIR"
    echo "Build Jobs: $JOBS"
    echo "Modules: $([ "$BUILD_MODULES" = "1" ] && echo "Yes" || echo "No")"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ] || [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
        print_success "Build completed successfully!"
        [ -d "artifacts" ] && echo "Artifacts: $(ls -1 artifacts/ | wc -l) files"
    else
        print_warning "Build completed but kernel image not found"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--clean)
                CLEAN_BUILD=1
                shift
                ;;
            -m|--modules)
                BUILD_MODULES=1
                shift
                ;;
            -d|--defconfig)
                KERNEL_DEFCONFIG="$2"
                shift 2
                ;;
            -o|--output)
                OUT_DIR="$2"
                shift 2
                ;;
            -j|--jobs)
                JOBS="$2"
                shift 2
                ;;
            -t|--toolchain)
                TOOLCHAIN="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execution
    print_info "Starting kernel build for $DEVICE..."
    echo ""
    
    check_dependencies
    check_toolchain
    
    [ "$CLEAN_BUILD" = "1" ] && clean_build
    
    setup_config
    build_kernel
    build_modules
    collect_artifacts
    print_summary
}

main "$@"
