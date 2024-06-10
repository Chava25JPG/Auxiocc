#!/bin/bash

set -eu

# Setup
FFMPEG_MODULE_PATH="$1"
NDK_PATH="$2"
HOST_PLATFORM="$3"
ANDROID_ABI="$4"
ENABLED_DECODERS=("${@:5}")

# Number of jobs to run in parallel
JOBS="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 4)"

# Common configuration options
COMMON_OPTIONS="--target-os=android --enable-static --disable-shared --disable-doc --disable-programs --disable-everything --disable-avdevice --disable-avformat --disable-swscale --disable-postproc --disable-avfilter --disable-symver --enable-swresample --extra-ldexeflags=-pie --disable-v4l2-m2m --disable-vulkan"

# Toolchain path
TOOLCHAIN_PREFIX="${NDK_PATH}/toolchains/llvm/prebuilt/${HOST_PLATFORM}/bin"
if [[ ! -d "${TOOLCHAIN_PREFIX}" ]]; then
    echo "Error: NDK path not found at ${TOOLCHAIN_PREFIX}"
    exit 1
fi

# Ensure the ffmpeg directory is clean and ready
cd "${FFMPEG_MODULE_PATH}/jni"
if [[ -d "./ffmpeg" ]]; then
    echo "Cleaning up the existing FFmpeg directory..."
    rm -rf ffmpeg
fi

echo "Cloning FFmpeg..."
git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg
cd ffmpeg

# Build for each architecture
for ARCH in armeabi-v7a arm64-v8a x86 x86_64; do
    echo "Configuring FFmpeg for ${ARCH}..."
    CC="${TOOLCHAIN_PREFIX}/armv7a-linux-androideabi${ANDROID_ABI}-clang"
    CXX="${TOOLCHAIN_PREFIX}/armv7a-linux-androideabi${ANDROID_ABI}-clang++"

    # Verify that the compilers exist
    if [[ ! -x "$CC" ]]; then
        echo "Compiler not found: $CC"
        exit 1
    fi

    if [[ ! -x "$CXX" ]]; then
        echo "Compiler not found: $CXX"
        exit 1
    fi

    ./configure \
        --libdir=android-libs/${ARCH} \
        --arch=arm \
        --cpu=armv7-a \
        --cross-prefix="${TOOLCHAIN_PREFIX}/armv7a-linux-androideabi${ANDROID_ABI}-" \
        --cc="$CC" \
        --cxx="$CXX" \
        --nm="${TOOLCHAIN_PREFIX}/llvm-nm" \
        --ar="${TOOLCHAIN_PREFIX}/llvm-ar" \
        --ranlib="${TOOLCHAIN_PREFIX}/llvm-ranlib" \
        --strip="${TOOLCHAIN_PREFIX}/llvm-strip" \
        --extra-cflags="-march=armv7-a -mfloat-abi=softfp" \
        --extra-ldflags="-Wl,--fix-cortex-a8" \
        ${COMMON_OPTIONS}
    make -j${JOBS}
    make install-libs
    if [[ ! -f "android-libs/${ARCH}/libswresample.a" ]]; then
        echo "Error: libswresample.a not found for ${ARCH}"
        exit 1
    fi
    make clean
done


