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
    apt_update
    # niri 不在 Ubuntu 归档里（pool 下没有 n/niri，Launchpad 上也没有源包），
    # 用的是 build-niri 作业从上游 vendored 源码构建的本地 deb ——
    # 它已经在 /tmp/debs 里（由 scripts/host/02-mount-chroot.sh 拷入）。
    shopt -s nullglob
    niri_debs=(/tmp/debs/niri_*.deb)
    [[ "${#niri_debs[@]}" -gt 0 ]] || die "找不到 niri 的 deb（/tmp/debs/niri_*.deb）：build-niri 作业失败或被跳过"
    # 用 apt 装本地 deb：libwayland/libseat/libdisplay-info 这些运行时依赖
    # 由 apt 从归档里补齐，比自己写 Depends 稳
    if ! apt_install "${niri_debs[@]}"; then
      warn "niri 首次安装失败，修依赖后重试"
      apt-get install -f -y || true
      apt_install "${niri_debs[@]}" || die "niri 安装失败，请看上面的依赖错误"
    fi
    command -v niri >/dev/null 2>&1 || die "niri 装上了但 PATH 里找不到可执行文件"
    [[ -f /usr/share/wayland-sessions/niri.desktop ]] || die "缺少 niri 的 wayland-sessions 描述文件"
    command -v niri-session >/dev/null 2>&1 || die "缺少 niri-session（greetd 靠它起会话）"
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
