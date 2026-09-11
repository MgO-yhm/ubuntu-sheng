#!/usr/bin/env bash
# 20-desktop.sh —— 安装桌面环境（GNOME / KDE Plasma / plasma-mobile / server）
#
# 对应上游 debian-sheng 的 Install GNOME / Install KDE Plasma 两个步骤，
# 差异：不使用会硬拉 snapd 的 ubuntu-desktop / kubuntu-desktop 元包，
# 改为显式包列表（见 lists/），并补齐 GNOME 分支上游漏掉的 pipewire-alsa。
#
# 环境变量（由 /root/build.env 提供）：
#   DESKTOP         GNOME / KDE Plasma / server
#   PLASMA_MOBILE   true/false
#   QUIET_BOOT      true/false（true 时安装 plymouth）
#
# 在 chroot 内执行:
#   chroot "$MOUNT" /root/sheng-build/in-chroot/20-desktop.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

: "${DESKTOP:?需要 DESKTOP}"
PLASMA_MOBILE="${PLASMA_MOBILE:-false}"
QUIET_BOOT="${QUIET_BOOT:-false}"

case "$DESKTOP" in
  GNOME)
    log "安装 GNOME（snap-free 包列表）"
    apt_update
    apt_install_list_best_effort "$BUILD_DIR/lists/gnome.list"
    ;;
  "KDE Plasma")
    if [[ "$PLASMA_MOBILE" == "true" ]]; then
      log "安装 KDE Plasma Mobile"
      apt_update
      apt_install_list_best_effort "$BUILD_DIR/lists/kde-mobile.list"
    else
      log "安装 KDE Plasma"
      apt_update
      apt_install_list_best_effort "$BUILD_DIR/lists/kde.list"
    fi
    ;;
  server)
    log "desktop=server：不安装桌面环境"
    ;;
  *)
    die "未知的 DESKTOP: $DESKTOP（可选 GNOME / KDE Plasma / server）"
    ;;
esac

# plymouth：与上游同样的条件（quiet_boot 且非 server）
if [[ "$QUIET_BOOT" == "true" && "$DESKTOP" != "server" ]]; then
  log "安装 Plymouth（quiet boot）"
  apt_install_list "$BUILD_DIR/lists/plymouth.list"
  if [[ "$DESKTOP" == "KDE Plasma" ]]; then
    apt_install_best_effort kde-config-plymouth plymouth-theme-breeze
    if plymouth-set-default-theme --list 2>/dev/null | grep -qx breeze; then
      plymouth-set-default-theme breeze || warn "设置 breeze 主题失败"
    fi
  fi
else
  log "跳过 Plymouth"
fi

log "桌面环境安装完成: $DESKTOP"
