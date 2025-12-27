#!/usr/bin/env bash

KERNEL_DIR="$PWD"
BASE_DIR="$(dirname "$KERNEL_DIR")"

DEVICE_ARG="$1"
if [[ -z "$DEVICE_ARG" ]]; then
    echo "Please provide device (lmi, alioth, munch, etc.)."
    echo "Example: ./compile_dtbo.sh lmi"
    exit 1
fi

declare -A DEVICE_MAP=(
    ["lmi"]="LMI:vendor/lmi_defconfig"
    ["alioth"]="ALIOTH:vendor/alioth_defconfig"
    ["munch"]="MUNCH:vendor/munch_defconfig"
)

if [[ ! "${DEVICE_MAP[$DEVICE_ARG]}" ]]; then
    echo " ERROR: device $DEVICE_ARG is unknown."
    exit 1
fi

IFS=':' read -r TARGET DEFCONFIG <<< "${DEVICE_MAP[$DEVICE_ARG]}"
TC_NAME="AOSP-Clang-20.0.0"

TC_PATH="$BASE_DIR/toolchains/aosp-clang"
if [[ ! -d "$TC_PATH" ]]; then
    echo "WARNING: Toolchain $TC_NAME not found in $TC_PATH."
fi

OUT_DIR="out_dtbo" 
FINAL_OUTPUT_DIR="$BASE_DIR/dtbo_output/$TARGET" 
mkdir -p "$FINAL_OUTPUT_DIR"
mkdir -p "$KERNEL_DIR/$OUT_DIR"

echo "--- Setting up Environment ($TARGET + $TC_NAME) ---"

if [[ -d "$TC_PATH" ]]; then
    export PATH="$TC_PATH/bin:$PATH"
fi

export ARCH="arm64"
export SUBARCH="arm64"

export CC="clang"
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export LLVM=1
export LLVM_IAS=1
export LD="ld.lld"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export STRIP="llvm-strip"

echo "--- Starting DTBO Compilation for $TARGET ---"
TIME_START="$(date +"%s")"
LOG_FILE="$FINAL_OUTPUT_DIR/dtbo_compile_$(date +%Y%m%d_%H%M).log"

echo "--- Loading $TARGET Defconfig: $DEFCONFIG ---"
make O="$OUT_DIR" "$DEFCONFIG" >> "$LOG_FILE" 2>&1

make O="$OUT_DIR" dtbs dtbo.img -j$(nproc) >> "$LOG_FILE" 2>&1

MAKE_STATUS=$?
TIME_END=$(("$(date +"%s")" - "$TIME_START"))

K_DTBO_SRC="$KERNEL_DIR/$OUT_DIR/arch/arm64/boot/dtbo.img"

if [[ $MAKE_STATUS -eq 0 ]] && [[ -f "$K_DTBO_SRC" ]]; then
    FINAL_IMG_NAME="dtbo_${TARGET}_$(date +%Y%m%d_%H%M).img"
    cp "$K_DTBO_SRC" "$FINAL_OUTPUT_DIR/$FINAL_IMG_NAME"
    
    echo "=========================================================="
    echo "SUCCESS: dtbo.img created successfully!"
    echo "DEVICE: $TARGET"
    echo "DTBO LOCATION: $FINAL_OUTPUT_DIR/$FINAL_IMG_NAME"
    echo "LOG: $LOG_FILE"
    echo "BUILD TIME: $(($TIME_END / 60))m $(($TIME_END % 60))s"
    echo "=========================================================="
else
    echo "=========================================================="
    echo "ERROR: DTBO compilation failed!"
    echo "LOG FILE: $LOG_FILE"
    echo "=========================================================="
fi