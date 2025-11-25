#!/usr/bin/env bash

# --- 1. Setup Direktori dan Konfigurasi Dasar ---
KERNEL_DIR="$PWD"
# BASE_DIR adalah direktori satu level di atas KERNEL_DIR (misalnya: Project-E404X-Fork)
BASE_DIR="$(dirname "$KERNEL_DIR")"

# --- Validasi Argumen Perangkat ---
DEVICE_ARG="$1"
if [[ -z "$DEVICE_ARG" ]]; then
    echo "🚨 ERROR: Masukkan perangkat target (lmi, alioth, munch, dll.)."
    echo "Contoh: ./compile_dtbo.sh lmi"
    exit 1
fi

# Definisikan mapping perangkat
declare -A DEVICE_MAP=(
    ["lmi"]="LMI:vendor/lmi_defconfig"
    ["alioth"]="ALIOTH:vendor/alioth_defconfig"
    ["munch"]="MUNCH:vendor/munch_defconfig"
)

if [[ ! "${DEVICE_MAP[$DEVICE_ARG]}" ]]; then
    echo "🚨 ERROR: Perangkat $DEVICE_ARG tidak ditemukan dalam map."
    exit 1
fi

IFS=':' read -r TARGET DEFCONFIG <<< "${DEVICE_MAP[$DEVICE_ARG]}"
TC_NAME="AOSP-Clang-20.0.0"

# Periksa Toolchain AOSP
TC_PATH="$BASE_DIR/toolchains/aosp-clang"
if [[ ! -d "$TC_PATH" ]]; then
    echo "⚠️ WARNING: Toolchain $TC_NAME tidak ditemukan di $TC_PATH."
    echo "Lanjutkan dengan harapan toolchain ada di \$PATH atau terdefinisi di environment."
fi

# --- Direktori Output Eksternal ---
OUT_DIR="out_dtbo" # Direktori output sementara di dalam KERNEL_DIR
FINAL_OUTPUT_DIR="$BASE_DIR/dtbo_output/$TARGET" # Lokasi hasil akhir (di luar KERNEL_DIR)
mkdir -p "$FINAL_OUTPUT_DIR"
mkdir -p "$KERNEL_DIR/$OUT_DIR"

# --- 2. Setup Environment untuk Kompilasi ---
echo "--- ⚙️ Setting up Environment ($TARGET + $TC_NAME) ---"

# Export Path dan Toolchain Prefix (AOSP Clang)
if [[ -d "$TC_PATH" ]]; then
    export PATH="$TC_PATH/bin:$PATH"
fi

export ARCH="arm64"
export SUBARCH="arm64"

# Flags Khusus Clang (Wajib)
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

# --- 3. Memulai Kompilasi ---
echo "--- ⏳ Starting DTBO Compilation for $TARGET ---"
TIME_START="$(date +"%s")"
LOG_FILE="$FINAL_OUTPUT_DIR/dtbo_compile_$(date +%Y%m%d_%H%M).log"

# Memuat Defconfig
echo "--- Loading $TARGET Defconfig: $DEFCONFIG ---"
make O="$OUT_DIR" "$DEFCONFIG" >> "$LOG_FILE" 2>&1

# Kompilasi DTB dan DTBO Saja
make O="$OUT_DIR" dtbs dtbo.img -j$(nproc) >> "$LOG_FILE" 2>&1

# Ambil status keluar dari make
MAKE_STATUS=$?
TIME_END=$(("$(date +"%s")" - "$TIME_START"))

# --- 4. Verifikasi dan Pindahkan Output Final ---
K_DTBO_SRC="$KERNEL_DIR/$OUT_DIR/arch/arm64/boot/dtbo.img"

if [[ $MAKE_STATUS -eq 0 ]] && [[ -f "$K_DTBO_SRC" ]]; then
    FINAL_IMG_NAME="dtbo_${TARGET}_$(date +%Y%m%d_%H%M).img"
    cp "$K_DTBO_SRC" "$FINAL_OUTPUT_DIR/$FINAL_IMG_NAME"
    
    echo "=========================================================="
    echo "✅ SUCCESS: dtbo.img baru telah dibuat dan disalin!"
    echo "DEVICE: $TARGET"
    echo "LOKASI DTBO: $FINAL_OUTPUT_DIR/$FINAL_IMG_NAME"
    echo "LOKASI LOG: $LOG_FILE"
    echo "Waktu Build: $(($TIME_END / 60))m $(($TIME_END % 60))s"
    echo "=========================================================="
else
    echo "=========================================================="
    echo "❌ ERROR: Kompilasi DTBO gagal. Periksa log!"
    echo "LOKASI LOG: $LOG_FILE"
    echo "=========================================================="
fi