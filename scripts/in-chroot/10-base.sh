#!/usr/bin/env bash
# 10-base.sh —— 在 chroot 内安装基础系统包（Ubuntu）
#
# 对应上游 debian-sheng “Install Base Packages” 步骤。
# 在 chroot 内执行：
#   chroot "$MOUNT" /root/sheng-build/in-chroot/10-base.sh
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/root/sheng-build}"
# shellcheck source=/dev/null
source "$BUILD_DIR/common/distro-env.sh"
# shellcheck source=/dev/null
source "$BUILD_DIR/in-chroot/lib-apt.sh"

prepare_apt

log "安装基础包（$DISTRO_SERIES / $DISTRO_SUITE）"
apt_update

# snap 禁用必须在任何安装前生效，并且要**当场断言**：一旦 pin 没生效，
# snapd 会经 Recommends 链被拉进来，直到最后一步 90-verify.sh 才失败 —— 白烧一小时构建。
# 断言只看"存在负优先级"（不写死 -10/-1），这样改用 version pin 等其他写法也不会误报。
# 另外 apt-mark hold 只有在 apt lists 可用（即 update 之后）才认识 snapd 这个包名。
if ! apt-cache policy snapd 2>/dev/null | grep -qE 'Pin-Priority:[[:space:]]*-[0-9]+'; then
  die "nosnap.pref 未生效：apt-cache policy snapd 里没有负的 Pin-Priority（见 15-nosnap.sh 的说明）"
fi
apt-mark hold snapd 2>/dev/null || warn "apt-mark hold snapd 失败（pin 仍然有效，不致命）"
log "已确认 snapd 被 apt pin 到负优先级（并尝试 hold）"

apt_install_list "$BUILD_DIR/lists/base.list"

# 上游显式预装的运行期库（best-effort，带 t64 兜底），见 lists/runtime-libs.list 的说明
apt_install_list_best_effort "$BUILD_DIR/lists/runtime-libs.list"

# wireless-regdb 的 alternatives（与上游 “Use Upstream Regulatory Database” 步骤一致）
if [[ -x /usr/bin/update-alternatives && -e /lib/firmware/regulatory.db-upstream ]]; then
  update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream \
    || warn "设置 regulatory.db alternatives 失败"
  log "已切换到 upstream 无线管制数据库"
else
  log "跳过 regulatory.db alternatives（该版本未提供）"
fi

log "基础包安装完成"
