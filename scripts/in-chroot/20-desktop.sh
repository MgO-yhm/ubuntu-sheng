#!/usr/bin/env bash
# 20-desktop.sh —— 安装桌面环境（GNOME / KDE Plasma / plasma-mobile / Lomiri / server）
#
# 对应上游 debian-sheng 的 Install GNOME / Install KDE Plasma 两个步骤，
# 差异：不使用会硬拉 snapd 的 ubuntu-desktop / kubuntu-desktop 元包，
# 改为显式包列表（见 lists/），并补齐 GNOME 分支上游漏掉的 pipewire-alsa。
#
# 环境变量（由 /root/build.env 提供）：
#   DESKTOP         GNOME / KDE Plasma / Lomiri / server
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
  Lomiri)
    log "安装 Lomiri"
    apt_update
    # 会话本体必须装上，所以放 best_effort 之外：
    #   lomiri                    —— shell 主体（/usr/bin/lomiri，ELF）
    #   lomiri-desktop-session    —— 会话入口：/usr/bin/lomiri-session、
    #                                /usr/lib/systemd/user/lomiri.service、
    #                                /usr/share/wayland-sessions/lomiri.desktop
    # 少了第二个的典型症状：systemd 一直报 “lomiri.service 不存在”，greetd
    # 也无从拉起会话（真机上表现为屏幕停在 tty1 的登录提示）。
    apt_install lomiri lomiri-desktop-session
    for p in lomiri lomiri-desktop-session; do
      dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" \
        || die "$p 未安装成功"
    done
    [[ -x /usr/bin/lomiri-session ]] || die "缺少 /usr/bin/lomiri-session（镜像不可用）"
    apt_install_list_best_effort "$BUILD_DIR/lists/lomiri.list"
    ;;
  Niri)
    log "安装 Niri（滚动平铺 Wayland 合成器）"
    # niri / noctalia / mpvpaper 都不在 Ubuntu 归档里，由独立仓库
    # code002-2/ubuntu-niri-repo 构建并发布成 apt 源（pool 下没有 n/niri，
    # Launchpad 上也没有源包，所以必须自建）。构建在那边做，这边只消费，
    # 避免同一个包两处构建、两处版本。
    if [[ -n "${NIRI_REPO:-}" ]]; then
      log "加入自建 apt 源: $NIRI_REPO"
      printf 'deb [trusted=yes arch=arm64] %s stable main\n' "$NIRI_REPO" \
        > /etc/apt/sources.list.d/ubuntu-niri-repo.list
      # trusted=yes：该源不做 GPG 签名（自用设备）。apt 不会校验来源，
      # 所以要确保 NIRI_REPO 指向的是我们自己的 Pages 地址。
    else
      die "NIRI_REPO 为空：niri 只在自建源里有，没源就装不上（见 rootfs.yml 的 niri_repo 输入项）"
    fi
    apt_update
    # niri 是硬性要求；noctalia/mpvpaper 在 lists 里走 best_effort
    apt_install niri
    command -v niri >/dev/null 2>&1 || die "niri 装上了但 PATH 里找不到可执行文件"
    command -v niri-session >/dev/null 2>&1 || die "缺少 niri-session（greetd 靠它起会话）"
    [[ -f /usr/share/wayland-sessions/niri.desktop ]] || die "缺少 niri 的 wayland-sessions 描述文件"
    apt_install_list_best_effort "$BUILD_DIR/lists/niri.list"
    ;;
  server)
    log "desktop=server：不安装桌面环境"
    ;;
  *)
    die "未知的 DESKTOP: $DESKTOP（可选 GNOME / KDE Plasma / Lomiri / Niri / server）"
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
