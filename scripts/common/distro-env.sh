#!/usr/bin/env bash
# 公共环境：Ubuntu 版本 ↔ suite 代号映射 + 日志工具
# 被 host/ 与 in-chroot/ 下的脚本共同 source。
#
# 说明：Ubuntu 的 suite 代号必须与 ubuntu-base tarball、apt 源一致，
# 这里集中维护，避免散落在 workflow YAML 里（上游正是把套件名直接写进
# workflow_dispatch 的 choices，新增发行版就要改 YAML）。

# 镜像内由 workflow 写入的构建参数（/root/build.env）；宿主阶段不存在该文件
if [[ -f /root/build.env ]]; then
  set -a
  # shellcheck source=/dev/null
  . /root/build.env
  set +a
fi

: "${DISTRO_SERIES:=26.04}"

case "$DISTRO_SERIES" in
  26.04|resolute) DISTRO_SUITE="resolute" ;;   # Ubuntu 26.04 LTS Resolute Raccoon
  25.10|questing) DISTRO_SUITE="questing" ;;   # Ubuntu 25.10 Questing Quokka
  *) echo "不支持的 Ubuntu 版本: $DISTRO_SERIES（可选 26.04 / 25.10）" >&2; exit 1 ;;
esac
export DISTRO_SUITE

# arm64 走 ports 归档（Ubuntu 的 arm64 软件包不在 archive.ubuntu.com 主归档）
export UBUNTU_PORTS_MIRROR="${UBUNTU_PORTS_MIRROR:-http://ports.ubuntu.com/ubuntu-ports/}"
export UBUNTU_CDIMAGE_BASE="${UBUNTU_CDIMAGE_BASE:-https://cdimage.ubuntu.com/ubuntu-base/releases}"

log()  { printf '[%s] %s\n' "${0##*/}" "$*"; }
warn() { printf '[%s] 警告: %s\n' "${0##*/}" "$*" >&2; }
die()  { printf '[%s] 错误: %s\n' "${0##*/}" "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "需要 root 权限（请用 sudo 调用本脚本）"
}
