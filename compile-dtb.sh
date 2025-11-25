#!/usr/bin/env bash
# E404 Kernel DTB Compile Script
# Put a fucking credit if you use something from here !

# Set kernel source directory and base directory to place tools
KERNEL_DIR="$PWD"
cd ..
BASE_DIR="$PWD"
cd "$KERNEL_DIR"

set -eo pipefail
trap 'errorbuild' INT TERM ERR

# Parse command line arguments
TC="Unknown-Clang"
TARGET=""
DEFCONFIG=""

# Device selection using arrays
declare -A DEVICE_MAP=(
    ["munch"]="MUNCH:vendor/munch_defconfig"
    ["alioth"]="ALIOTH:vendor/alioth_defconfig"
    ["apollo"]="APOLLO:vendor/apollo_defconfig"
    ["pipa"]="PIPA:vendor/pipa_defconfig"
    ["lmi"]="LMI:vendor/lmi_defconfig"
    ["umi"]="UMI:vendor/umi_defconfig"
    ["cmi"]="CMI:vendor/cmi_defconfig"
    ["cas"]="CAS:vendor/cas_defconfig"
)

# Check if device name is provided as argument
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <device_name>"
    echo "Available devices: ${!DEVICE_MAP[*]}"
    exit 1
fi

DEVICE_NAME="$1"
if [[ -z "${DEVICE_MAP[$DEVICE_NAME]}" ]]; then
    echo "!! Unknown device: $DEVICE_NAME !!"
    echo "Available devices: ${!DEVICE_MAP[*]}"
    exit 1
fi

IFS=':' read -r TARGET DEFCONFIG <<< "${DEVICE_MAP[$DEVICE_NAME]}"

# Toolchain selection - default to AOSP Clang if available
if [[ -d "$BASE_DIR/toolchains/aosp-clang" ]]; then
    export PATH="$BASE_DIR/toolchains/aosp-clang/bin:$PATH"
    TC="AOSP-Clang"
elif [[ -d "$BASE_DIR/toolchains/neutron-clang" ]]; then
    export PATH="$BASE_DIR/toolchains/neutron-clang/bin:$PATH"
    TC="Neutron-Clang"
else
    echo "-- !! Please provide a toolchain !! --"
    exit 1
fi

# Set output directory
DTB_OUT_DIR="$BASE_DIR/dtb-out/$DEVICE_NAME"
mkdir -p "$DTB_OUT_DIR"

# Build environment
export ARCH="arm64"
export SUBARCH="arm64"

# Function definitions
setupbuild() {
    if [[ $TC == *Clang* ]]; then
        BUILD_FLAGS=(
            CC="ccache clang"
            CROSS_COMPILE="aarch64-linux-gnu-"
            CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
            LLVM=1
            LLVM_IAS=1
            LD="ld.lld"
            AR="llvm-ar"
            NM="llvm-nm"
            OBJCOPY="llvm-objcopy"
            OBJDUMP="llvm-objdump"
            STRIP="llvm-strip"
        )
        
        # Export for defconfig (without ccache)
        export CC="clang"
        export CROSS_COMPILE="aarch64-linux-gnu-"
        export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
        export LLVM=1
        export LLVM_IAS=1
    else
        BUILD_FLAGS=(
            CC="ccache aarch64-linux-gcc"
            CROSS_COMPILE="aarch64-linux-"
            CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
        )

        # Export for defconfig (without ccache)
        export CC="aarch64-linux-gcc"
        export CROSS_COMPILE="aarch64-linux-"
        export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
    fi
}

errorbuild() {
    echo "-- !! DTB Build Error !! --"
    exit 1
}

clearbuild() {
    echo "-- Cleaning Out --"
    rm -rf out/*
}

copy_kona_dtb() {
    local output_dir="$1"
    local device_name="$2"
    local timestamp="$3"
    
    echo "-- Looking for kona-v2.1.dtb --"
    
    # Define possible locations for kona-v2.1.dtb
    local possible_paths=(
        "$KERNEL_DIR/out/arch/arm64/boot/dts/qcom"
        "$KERNEL_DIR/out/arch/arm64/boot/dts/vendor"
        "$KERNEL_DIR/out/arch/arm64/boot/dts"
        "$KERNEL_DIR/out/arch/arm64/boot"
    )
    
    local kona_dtb_path=""
    
    # Search for kona-v2.1.dtb in possible locations
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path/kona-v2.1.dtb" ]]; then
            kona_dtb_path="$path/kona-v2.1.dtb"
            echo "Found kona-v2.1.dtb at: $path"
            break
        fi
    done
    
    # If not found, try to find it with find command
    if [[ -z "$kona_dtb_path" ]]; then
        kona_dtb_path=$(find "$KERNEL_DIR/out" -name "kona-v2.1.dtb" -type f 2>/dev/null | head -1)
        if [[ -n "$kona_dtb_path" ]]; then
            echo "Found kona-v2.1.dtb at: $kona_dtb_path"
        fi
    fi
    
    # Copy the file if found
    if [[ -n "$kona_dtb_path" && -f "$kona_dtb_path" ]]; then
        local output_file="$output_dir/${device_name}-dtb-${timestamp}"
        cp "$kona_dtb_path" "$output_file"
        echo "Copied: ${device_name}-dtb-${timestamp}"
        return 0
    else
        echo "-- Error: kona-v2.1.dtb not found --"
        echo "Searched in:"
        for path in "${possible_paths[@]}"; do
            echo "  - $path"
        done
        return 1
    fi
}

compile_dtb() {
    echo "-- Setting up build environment --"
    setupbuild
    
    echo "-- Creating output directory --"
    mkdir -p "$KERNEL_DIR/out"

    echo "-- Generating defconfig --"
    make O=out "$DEFCONFIG" || errorbuild

    echo "-- Compiling device tree binaries --"
    local make_flags=(-j"$(nproc)" O=out "${BUILD_FLAGS[@]}")
    
    if [[ $TC == *Clang* ]]; then
        echo "-- Compiling with Clang --"
        make "${make_flags[@]}" dtbs || errorbuild
    else
        echo "-- Compiling with GCC --"
        make "${make_flags[@]}" dtbs || errorbuild
    fi

    # Show ccache stats after build
    echo "======== CCache Stats =========="
    ccache -s
    echo "================================"

    # Copy kona-v2.1.dtb with timestamp
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    
    echo "-- Copying kona-v2.1.dtb --"
    copy_kona_dtb "$DTB_OUT_DIR" "$DEVICE_NAME" "$TIMESTAMP"
    
    echo "-- DTB compilation completed --"
}

# Main execution
echo "======================================"
echo "    E404 Kernel DTB Compiler"
echo "======================================"
echo "Device: $TARGET ($DEVICE_NAME)"
echo "Toolchain: $TC"
echo "Output Directory: $DTB_OUT_DIR"
echo "======================================"

compile_dtb

echo ""
echo "DTB compilation successful!"
echo "Output file: $DTB_OUT_DIR/${DEVICE_NAME}-dtb-${TIMESTAMP}"