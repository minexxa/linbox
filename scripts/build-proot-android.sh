#!/usr/bin/env bash
#
# 用 NDK 编译 Android arm64 的 proot 与其 loader，输出到
# android/app/src/main/jniLibs/arm64-v8a/
#
#   libproot.so          proot 本体
#   libproot-loader.so   proot 的 loader
#
# 为什么必须两个、且必须叫 lib*.so
# --------------------------------
# targetSdk >= 29 起，进程不能 execve 应用私有目录里的文件，而 Linux rootfs
# 就是一堆放在那里的文件。proot 的绕法不是要权限，而是根本不对 guest 二进制
# 调用 execve：它自带的 loader 映射 guest ELF，再把控制权交给 guest 自己的
# 解释器。
#
# 两个容易踩的坑，报错都长得像"系统限制"而不是配置错误：
#
#   1. loader 必须一起打包，并通过 PROOT_LOADER 指过去（代码里已设）。
#      否则 proot 会把内嵌的 loader 解包到临时目录 —— 那个目录正是应用私有
#      目录，不可执行 —— 然后退回普通 execve，报
#      `proot error: execve(...): Permission denied`。
#
#   2. 应用必须开启 legacy packaging（build.gradle 里的
#      `packaging.jniLibs.useLegacyPackaging = true`，清单里的
#      `android:extractNativeLibs="true"`）。minSdk >= 23 时原生库默认从 APK
#      直接映射、不解包，nativeLibraryDir 根本不存在，两个二进制无处安放。
#
# 两者都只能从 nativeLibraryDir 执行（SELinux 上下文 apk_data_file），
# 而 Android 只解包 lib/<abi>/lib*.so 这种名字的文件，所以文件名必须是
# lib*.so —— 它们并不是共享库，只是借这个壳。
#
# 用法
# ----
#   scripts/build-proot-android.sh [--clean]
#
# 环境：
#   ANDROID_NDK_HOME   NDK 路径；缺省取 $ANDROID_HOME/ndk/$PROOT_NDK_VERSION
#   PROOT_NDK_VERSION  需要校验的 NDK 版本（可留空）
#   PROOT_OUT_DIR      输出目录（默认 android/app/src/main/jniLibs/arm64-v8a）
#   PROOT_BUILD_DIR    工作目录（默认 build/proot-android）
#
# 需要 curl / tar / make / git。仓库里不下发二进制，构建时生成。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${PROOT_BUILD_DIR:-$REPO_ROOT/build/proot-android}"
OUT_DIR="${PROOT_OUT_DIR:-$REPO_ROOT/android/app/src/main/jniLibs/arm64-v8a}"
PINNED_NDK_VERSION="${PROOT_NDK_VERSION:-}"

# proot 用的是 termux 的 fork（含 Android 修复），不是上游 proot-me；
# 同时按 tag + tag 当时指向的 commit 双重锁定（tag 会移动，commit 不会）。
PROOT_REPO="https://github.com/termux/proot.git"
PROOT_TAG=v5.1.107.90
PROOT_COMMIT=894e5789cd982e53d644bb3a13332f1d35e907ac

# 26 而不是应用的 minSdk：proot 只是个普通可执行程序，用不到新 libc。
ANDROID_API=26
NDK_TRIPLE=aarch64-linux-android

TALLOC_VERSION=2.4.2
TALLOC_URLS=(
  "https://download.samba.org/pub/talloc/talloc-${TALLOC_VERSION}.tar.gz"
  "https://deb.debian.org/debian/pool/main/t/talloc/talloc_${TALLOC_VERSION}.orig.tar.gz"
  "https://ftp.osuosl.org/pub/blfs/conglomeration/talloc/talloc-${TALLOC_VERSION}.tar.gz"
)
TALLOC_SHA256=85ecf9e465e20f98f9950a52e9a411e14320bc555fa257d87697b7e7a9b1d8a6

log() { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[0;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--clean" ]; then
  log "清理 $WORK_DIR 与已生成的库"
  rm -rf "$WORK_DIR" "$OUT_DIR/libproot.so" "$OUT_DIR/libproot-loader.so"
  exit 0
fi

find_ndk() {
  for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [ -n "$candidate" ] && [ -d "$candidate" ] && { echo "$candidate"; return; }
  done
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
  if [ -n "$PINNED_NDK_VERSION" ]; then
    local pinned="$sdk/ndk/$PINNED_NDK_VERSION"
    [ -d "$pinned" ] || die "未找到 NDK $PINNED_NDK_VERSION：$pinned"
    echo "$pinned"
    return
  fi
  # 没指定版本时，用 SDK 里装好的最新一个（CI 上 Gradle 通常已经下好了）。
  local latest
  latest="$(ls -1d "$sdk"/ndk/*/ 2>/dev/null | sort -V | tail -n 1)"
  [ -d "$latest" ] || die "请设置 ANDROID_NDK_HOME / PROOT_NDK_VERSION（未找到 $sdk/ndk/*）"
  echo "${latest%/}"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

fetch() {
  local dest="$1" want="$2" url got
  shift 2
  if [ -f "$dest" ]; then
    [ -z "$want" ] && return
    got="$(sha256 "$dest")"
    [ "$got" = "$want" ] && return
    rm -f "$dest"
  fi
  for url in "$@"; do
    log "下载 $(basename "$dest") <- $url"
    if curl -fsSL --retry 3 -o "$dest" "$url"; then
      [ -z "$want" ] && return 0
      got="$(sha256 "$dest")"
      [ "$got" = "$want" ] && return 0
      rm -f "$dest"
      log "校验失败：$url"
    else
      rm -f "$dest"
    fi
  done
  die "无法下载 $(basename "$dest")"
}

build_talloc() {
  local src="$WORK_DIR/talloc-$TALLOC_VERSION"
  fetch "$WORK_DIR/talloc.tar.gz" "$TALLOC_SHA256" "${TALLOC_URLS[@]}"
  rm -rf "$src"
  tar xzf "$WORK_DIR/talloc.tar.gz" -C "$WORK_DIR"

  # talloc.c 依赖 samba 的 replace.h（兼容层）。为 bionic 造一个最小版本，
  # 比把 samba 的 waf build 引进来便宜得多。
  cat >"$src/replace.h" <<'SHIM'
#ifndef REPLACE_H
#define REPLACE_H
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/auxv.h>

/* 必须与 tarball 一致，talloc.c 运行时会断言 */
#define TALLOC_BUILD_VERSION_MAJOR   2
#define TALLOC_BUILD_VERSION_MINOR   4
#define TALLOC_BUILD_VERSION_RELEASE 2

#define HAVE_SYS_AUXV_H 1
#define HAVE_INTPTR_T 1
#define HAVE_VA_COPY 1
#define HAVE_CONSTRUCTOR_ATTRIBUTE 1

#define VALGRIND_MAKE_MEM_UNDEFINED(p, n) do { (void)(p); (void)(n); } while (0)
#define VALGRIND_MAKE_MEM_DEFINED(p, n)   do { (void)(p); (void)(n); } while (0)
#define VALGRIND_MAKE_MEM_NOACCESS(p, n)  do { (void)(p); (void)(n); } while (0)

#ifndef ZERO_STRUCT
#define ZERO_STRUCT(x) memset((char *)&(x), 0, sizeof(x))
#endif
#ifndef discard_const
#define discard_const(ptr) ((void *)((uintptr_t)(ptr)))
#endif
#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif
#endif /* REPLACE_H */
SHIM

  log "编译 talloc"
  "$CC" -c -O2 -o "$WORK_DIR/talloc.o" -I "$src" "$src/talloc.c"
  "$TOOLCHAIN/llvm-ar" rcsD "$WORK_DIR/libtalloc.a" "$WORK_DIR/talloc.o"
}

patch_proot() {
  local file="$1/src/extension/ashmem_memfd/ashmem_memfd.c"
  grep -q '#include <string.h>' "$file" && return
  # strcmp/memset 无声明：新 clang 直接报错，而这份代码当年只是警告。
  log "给 ashmem_memfd.c 打补丁以适配新 NDK"
  awk 'NR==1{print "#include <string.h>"}1' "$file" >"$file.new"
  mv "$file.new" "$file"
}

build_proot() {
  local src="$WORK_DIR/proot"
  [ -d "$src/.git" ] || rm -rf "$src"
  if [ ! -d "$src" ]; then
    log "克隆 proot $PROOT_TAG"
    git clone --quiet --depth 1 --branch "$PROOT_TAG" "$PROOT_REPO" "$src"
  fi
  local head
  head="$(git -C "$src" rev-parse HEAD)"
  [ "$head" = "$PROOT_COMMIT" ] ||
    die "proot $PROOT_TAG 的 HEAD 是 $head，不是锁定的 $PROOT_COMMIT"
  git -C "$src" reset --hard "$PROOT_COMMIT" >/dev/null
  git -C "$src" clean -ffdqx
  patch_proot "$src"

  log "编译 proot"
  # 必须 in-tree：proot 的 makefile 对 out-of-tree 会重复拼前缀。
  # bionic 没有 ARG_MAX；-I. 是因为它自己的头文件按 `execve/elf.h` 方式包含。
  ( cd "$src/src" && make \
      CC="$CC" \
      STRIP="$TOOLCHAIN/llvm-strip" \
      OBJCOPY="$TOOLCHAIN/llvm-objcopy" \
      OBJDUMP="$TOOLCHAIN/llvm-objdump" \
      CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I. -DARG_MAX=131072 -I$WORK_DIR/talloc-$TALLOC_VERSION" \
      CFLAGS="-O2 -fPIE" \
      LDFLAGS="-Wl,-z,noexecstack -pie -L$WORK_DIR -ltalloc" \
      -j"$(nproc)" >/dev/null )

  [ -f "$src/src/proot" ] || die "proot 未构建成功"
  [ -f "$src/src/loader/loader" ] || die "proot loader 未构建成功"

  mkdir -p "$OUT_DIR"
  install -m 0755 "$src/src/proot" "$OUT_DIR/libproot.so"
  install -m 0755 "$src/src/loader/loader" "$OUT_DIR/libproot-loader.so"
}

NDK="$(find_ndk)"
log "NDK: $NDK"
case "$(uname -s)" in
  Darwin) HOST_TAG=darwin-x86_64 ;;
  Linux) HOST_TAG=linux-x86_64 ;;
  *) die "不支持的构建主机：$(uname -s)" ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CC="$TOOLCHAIN/${NDK_TRIPLE}${ANDROID_API}-clang"
[ -x "$CC" ] || die "找不到编译器：$CC"

mkdir -p "$WORK_DIR"
build_talloc
build_proot

log "输出："
ls -l "$OUT_DIR"/libproot.so "$OUT_DIR"/libproot-loader.so
