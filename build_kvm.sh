#!/usr/bin/env bash
set -Eeuo pipefail

# Kernel build script for xiaomi-mt6893-dev kernel_xiaomi_mt6893
# Target: ares / agate family, with KVM enabled.
#
# Usage:
#   ./build_kvm.sh [device] [-c]
#
# Examples:
#   ./build_kvm.sh ares
#   ./build_kvm.sh -c ares
#   ./build_kvm.sh ares -c

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')
DEVICE="ares"
CLEAN_BUILD=false

for arg in "$@"; do
    case "$arg" in
        -c|--clean)
            CLEAN_BUILD=true
            ;;
        -* )
            ;;
        * )
            DEVICE="$arg"
            ;;
    esac
done

DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="HydrogenKernel-KVM-${DEVICE}-${DATE}.zip"

echo "Building for: ${DEVICE}"
echo "Defconfig: ${DEFCONFIG}"

# Toolchain
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 -b clang-15 https://gitlab.com/LeCmnGend/proton-clang.git proton-clang
    cd "$CURRENT_DIR"
fi
export PATH="$TC_DIR/bin:$PATH"
export USE_CCACHE=1
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"

if [ "$CLEAN_BUILD" = true ]; then
    rm -rf out
fi

mkdir -p out

# Base defconfig
make O=out ARCH=arm64 "$DEFCONFIG"

# Enable KVM-related options that are typically safe for arm64 downstream trees.
# If a symbol does not exist in this tree, scripts/config will ignore it.
scripts/config --file out/.config \
    -e VIRTUALIZATION \
    -e KVM \
    -e KVM_ARM_HOST \
    -e KVM_MMIO \
    -e HAVE_KVM_IRQCHIP

# Keep the config conservative for old downstream trees.
make O=out ARCH=arm64 olddefconfig

# Show the final KVM bits for quick verification.
echo
printf 'KVM config summary:\n'
grep -E '^(CONFIG_VIRTUALIZATION|CONFIG_KVM|CONFIG_KVM_ARM_HOST|CONFIG_KVM_MMIO|CONFIG_HAVE_KVM_IRQCHIP)=' out/.config || true

echo
echo "Starting compilation..."
if make -j"$(nproc --all)" O=out ARCH=arm64 \
    CC="ccache clang" LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    Image.gz; then
    echo
    echo "Kernel compiled successfully. Zipping up..."

    rm -rf AnyKernel3
    git clone -q --depth=1 https://github.com/rio004/AnyKernel3 AnyKernel3

    cp out/arch/arm64/boot/Image.gz AnyKernel3/

    # Keep the packaging simple and deterministic.
    (cd AnyKernel3 && zip -r9 "../${ZIPNAME}" . -x '*.git*' 'README.md' '*placeholder*')

    rm -rf AnyKernel3

    echo
    echo "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: ${ZIPNAME}"
else
    echo
    echo "Compilation failed!"
    exit 1
fi
