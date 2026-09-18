#!/usr/bin/env bash
# build-niri.sh —— 从源码构建 niri（Wayland 滚动平铺合成器）并打成 deb
#
# 为什么必须自己编：Ubuntu 归档里没有 niri。已经核对过
#   * archive.ubuntu.com 的 pool 下没有 n/niri 目录
#   * Launchpad 上查不到 niri 的源包（任何 series 都没有）
# 所以 buster/staging/universe 都装不到它。
#
# niri 的 release 附带 niri-<version>-vendored-dependencies.tar.xz（cargo vendor
# 过的源码），正好适合 CI 里离线构建，不需要联网拉 crate。
#
# 需要环境变量：
#   NIRI_VERSION  默认 26.04（对应 release tag v26.04）
#
# 用法: scripts/packages/build-niri.sh
set -euo pipefail

PKG=niri
VER="${NIRI_VERSION:-26.04}"
TARBALL_NAME="niri-${VER}-vendored-dependencies.tar.xz"
OUT="${PWD}/${PKG}_${VER}-1_arm64.deb"
WORK="${PWD}/build/${PKG}-work"
BUILD="${PWD}/build/${PKG}"

rm -rf "$WORK" "$BUILD"
mkdir -p "$WORK" "$BUILD/DEBIAN"

echo "[build-niri] 下载 $TARBALL_NAME"
if ! curl -fL --retry 3 --connect-timeout 30 -o "$WORK/$TARBALL_NAME" \
     "https://github.com/YaLTeR/niri/releases/download/v${VER}/${TARBALL_NAME}"; then
  echo "[build-niri] 错误：下载 vendored 源码失败（release tag v${VER} 里可能没有该资产）" >&2
  exit 1
fi

echo "[build-niri] 解包"
tar -xf "$WORK/$TARBALL_NAME" -C "$WORK"

# 布局无关：tarball 的顶层目录名可能带版本号/v 前缀，自己找含 Cargo.toml 的那层。
# 用 find -quit 而不是 | head -n1：head 提前关管道会让 find 吃到 SIGPIPE 返回非 0，
# 在 set -o pipefail 下会把整个赋值判为失败，set -e 随即静默终止脚本（无任何报错）。
SRC="$(find "$WORK" -maxdepth 3 -name Cargo.toml -printf '%h\n' -quit)"
[[ -n "$SRC" ]] || { echo "[build-niri] 错误：解包后找不到 Cargo.toml" >&2; ls -R "$WORK" 2>&1 | sed -n '1,40p' >&2; exit 1; }
echo "[build-niri] 源码目录: $SRC"

# Rust 工具链：runner 自带 rustup，但版本可能低于 niri 的 MSRV
if command -v rustup >/dev/null 2>&1; then
  echo "[build-niri] rustup 更新 stable（当前 $(rustc --version 2>/dev/null || echo 无)）"
  rustup update stable >/dev/null 2>&1 || true
  rustup default stable >/dev/null 2>&1 || true
fi
rustc --version || { echo "[build-niri] 错误：没有 rustc" >&2; exit 1; }

echo "[build-niri] cargo build --release（vendored，离线）"
if ! ( cd "$SRC" && cargo build --release --offline ); then
  echo "[build-niri] 离线构建失败，退回联网构建" >&2
  ( cd "$SRC" && cargo build --release )
fi

BIN="$SRC/target/release/niri"
[[ -x "$BIN" ]] || { echo "[build-niri] 错误：没有产出 $BIN" >&2; exit 1; }

echo "[build-niri] 安装到暂存目录"
# 安装路径照 niri 官方 wiki 的 Manual installation
install -Dm755 "$BIN"                                   "$BUILD/usr/bin/niri"
install -Dm755 "$SRC/resources/niri-session"            "$BUILD/usr/bin/niri-session"
install -Dm644 "$SRC/resources/niri.desktop"            "$BUILD/usr/share/wayland-sessions/niri.desktop"
install -Dm644 "$SRC/resources/niri-portals.conf"       "$BUILD/usr/share/xdg-desktop-portal/niri-portals.conf"
install -Dm644 "$SRC/resources/niri.service"            "$BUILD/usr/lib/systemd/user/niri.service"
install -Dm644 "$SRC/resources/niri-shutdown.target"    "$BUILD/usr/lib/systemd/user/niri-shutdown.target"
if [[ -f "$SRC/resources/default-config.kdl" ]]; then
  install -Dm644 "$SRC/resources/default-config.kdl"    "$BUILD/usr/share/niri/default-config.kdl"
fi
# niri-session 依赖的这些运行时组件由上层 lists/niri.list 负责，缺了不致命

# Depends 用 ldd + dpkg -S 推导：手写库名极易写错（libdisplay-info 这类
# 带版本号的包名在 Ubuntu 各版本间会变），推导出来的才是这个构建机上真实的依赖。
echo "[build-niri] 推导运行时依赖"
deps=""
while read -r so; do
  [[ -n "$so" ]] || continue
  pkg="$(dpkg -S "$so" 2>/dev/null | cut -d: -f1 | head -n1 || true)"
  [[ -n "$pkg" ]] || continue
  case ",$deps," in *",$pkg,"*) continue ;; esac
  deps="${deps:+$deps, }$pkg"
done < <(ldd "$BUILD/usr/bin/niri" | awk '{print $3}' | grep -E '^/' | sort -u)
echo "[build-niri] Depends: $deps"

cat > "$BUILD/DEBIAN/control" <<EOF
Package: ${PKG}
Version: ${VER}-1
Architecture: arm64
Maintainer: YaLTeR <niri@yalter.email>
Section: x11
Priority: optional
Depends: ${deps}
Description: Scrollable-tiling Wayland compositor
 niri is a scrollable-tiling Wayland compositor: windows are arranged in
 columns on an infinite strip, and you scroll through them.
 .
 Ubuntu 的归档里没有这个包，本仓库从上游 vendored 源码自行构建。
EOF

find "$BUILD" -type d -exec chmod 755 {} +
find "$BUILD" -type f -exec chmod 644 {} +
chmod 755 "$BUILD/usr/bin/niri" "$BUILD/usr/bin/niri-session"

dpkg-deb --build --root-owner-group "$BUILD" "$OUT"
echo "[build-niri] 产出 $OUT ($(du -h "$OUT" | cut -f1))"
# 末尾这段纯展示：同样避免 head 在 pipefail 下把脚本判死
dpkg-deb -c "$OUT" 2>/dev/null | awk '{print "    "$NF}' | grep -v '/$' | sed -n '1,20p' || true
