# 与上游 debian-sheng 的功能对照（Ubuntu 版）

> 上游基准：`ianchb/debian-sheng` 的 `.github/workflows/rootfs.yml`（master，1280 行，7 个作业）。
> 本表逐条列出上游每个步骤在本仓库的落点，用于验收"全量对齐"。
> 生成方式：对照上游 `rootfs.yml` 全文分析逐项核对本仓库文件，非凭印象填写。

## 一、workflow_dispatch 输入项

| 上游输入 | 本仓库 | 说明 |
|---|---|---|
| `distro_suite`（trixie/forky） | `ubuntu_series`（26.04/25.10） | 换成 Ubuntu 版本；suite 代号在 `scripts/common/distro-env.sh` 集中映射 |
| `desktop`（GNOME/KDE Plasma/server） | 同名同选项 | ✅ |
| `plasma_mobile` | ✅ 同名 | ✅ |
| `autologin` | ✅ | ✅ |
| `username` | ✅ | ✅ |
| `hostname` | ✅ | ✅ |
| `language`（10 个选项） | ✅ 同 10 项 | ✅ |
| `boot_mode`（single/dual/custom） | ✅ 同名同选项 | 第三个选项字面量同为 `custom` |
| `quiet_boot` | ✅ | ✅ |
| `custom_partition` | ✅ | ✅ |
| `kernel_source`（prebuilt/custom_build） | ✅ | ✅ |
| `kernel_repo` / `kernel_branch` / `kernel_config` | ✅ | 默认值同上游（`sheng-7.2.2` / `sm8550.config`） |
| `firmware_repo` / `firmware_branch` | ✅ | 默认 `ianchb/sheng-firmware` / `master` |
| — | **新增** `rootfs_size`、`shrink_image`、`upload_artifacts`、`browser` | 前两项是上游缺口补强；`upload_artifacts` 合并了上游 `rootfs-lite.yml` 的"测试不产出"用途；`browser` 因 Ubuntu 的 firefox 是 snap 过渡包而必须单列 |

## 二、设备功能包构建（上游 6+3 个作业 → `_packages.yml`）

| 上游作业 | 本仓库 job | 实现脚本 |
|---|---|---|
| `build-kernel`（custom_build） | `build-kernel` | `scripts/packages/build-kernel.sh` |
| `build-fastrpc` | `build-fastrpc` | `scripts/packages/build-fastrpc.sh` |
| `build-libssc` | `build-libssc` | `scripts/packages/build-libssc.sh` |
| `build-iio-sensor-proxy` | `build-iio-sensor-proxy` | `scripts/packages/build-iio-sensor-proxy.sh` |
| `build-sheng-sensors` | `build-sheng-sensors` | `scripts/packages/build-sheng-sensors.sh` |
| `build-sheng-devauth` | `build-sheng-devauth` | `scripts/packages/build-sheng-devauth.sh` |
| Package alsa-xiaomi-sheng | `package-alsa` | `scripts/packages/build-alsa.sh` |
| Package firmware-xiaomi-sheng | `package-firmware` | `scripts/packages/build-firmware.sh` |
| 6 × `gh release download` xiaomi-* | `fetch-xiaomi-debs` | `scripts/packages/fetch-xiaomi-debs.sh` |

## 三、rootfs 组装步骤

| 上游步骤 | 本仓库落点 | 备注 |
|---|---|---|
| Verify Arguments（密码警告、custom 组合校验） | `rootfs.yml` → Verify Arguments | 同规则 |
| Parse Partition Label（label / quiet / boot_img_pattern） | `rootfs.yml` → Parse Arguments | 同逻辑 + 追加 `desktop_slug` |
| Install Build Tools（debootstrap git curl） | `rootfs.yml` → Install Host Tools | 改为 `mmdebstrap curl git e2fsprogs`（基线用 ubuntu-base tarball，mmdebstrap 仅作回退） |
| `[Prebuilt]` Download Kernel | `scripts/host/10-fetch-kernel.sh` | 同样的 `gh release list/download`，同样的 4 个 boot 变体名 |
| `[Custom]` Download Kernel Package/Image | `rootfs.yml` → download-artifact ×2 | ✅ |
| Create RootFS Image（`truncate` + `mkfs.ext4`） | `scripts/host/00-prepare-image.sh` | 额外加 `-L rootfs` 卷标；仍是无分区表镜像 |
| Mount RootFS Image | 同上（loop mount） | ✅ |
| Run Debootstrap | `scripts/host/01-bootstrap.sh` | 改为 ubuntu-base tarball（多候选地址）+ apt 源写 deb822（ports + updates/security/backports） |
| Mount Virtual File Systems（bind /dev,/dev/pts,proc,sys + resolv.conf） | `scripts/host/02-mount-chroot.sh` | 额外把脚本与 `debs/` 拷入镜像 |
| Install Base Packages | `scripts/in-chroot/10-base.sh` + `scripts/lists/base.list` | 不预装 lib* 运行期库（交给 apt 解析本地 deb 依赖，规避 t64 改名） |
| Use Upstream Regulatory Database | `scripts/in-chroot/10-base.sh` | 同样的 `update-alternatives --set regulatory.db` |
| Install Plymouth（quiet 且非 server） | `scripts/in-chroot/20-desktop.sh` + `lists/plymouth.list` | KDE 追加 breeze 主题（best-effort） |
| Install All .deb Packages | `scripts/in-chroot/30-device-packages.sh` | 上游 `\|\| apt-get install -f -y` 后静默继续；这里失败会终止 |
| Fix Permissions（adsprpcd/iio-sensor-proxy/monitor-sensor/ssccli） | `scripts/in-chroot/30-device-packages.sh` | ✅ 同样的 4 个路径 |
| Enable Sensor Services | `scripts/in-chroot/30-device-packages.sh` | **修正上游拼写**：真实 unit 是 `adsprpcd-sensorspd.service`（a-d-s-p-r-p-c-d），上游 enable 写成 `adsrpcd-…`（少一个 rp）→ 上游那个 unit 其实永远没被启用。本仓库写死正确文件名，并在 `90-verify.sh` 里校验"已 enable"而不只是"文件存在" |
| — | **新增** `depmod -a <kver>` + 校验 `modules.dep` | 上游全程无 depmod（同仓库 `fnnas-rootfs.yml` 有） |
| Set Hostname（/etc/hostname + /etc/hosts 127.0.1.1） | `scripts/in-chroot/40-system-config.sh` | ✅ |
| Configure Locale | 同上 | 同语义，双写 `/etc/default/locale` 与 `/etc/locale.conf` |
| Create User（`useradd -m -s /bin/bash -G sudo`） | 同上 | ✅ |
| Set Passwords（用户与 root 同密码，空则 `password`） | 同上（密码经 600 权限文件传入，不再走命令行） | ✅ |
| Install GNOME / KDE Plasma | `scripts/in-chroot/20-desktop.sh` + `lists/*.list` | 不用 `ubuntu-desktop`/`kubuntu-desktop`（依赖 snapd）；GNOME 分支补上上游漏掉的 `pipewire-alsa` |
| Install KDE Plasma Plymouth Settings | `scripts/in-chroot/20-desktop.sh` | ✅ |
| Configure GDM / SDDM (+Autologin) | `scripts/in-chroot/40-system-config.sh` | **有意与上游不同**：Ubuntu 的 gdm3 只读 `/etc/gdm3/custom.conf`，而上游 Debian 用的是 `/etc/gdm3/daemon.conf`（照搬会静默失效）。本仓库改 `custom.conf` 并写 `daemon.conf` 作为 Debian 系兼容；SDDM 仍是 `/etc/sddm.conf.d/autologin.conf`（两边一致）；`90-verify.sh` 校验 `custom.conf` 里的 `AutomaticLoginEnable=true` |
| Enable NetworkManager | 同上 | ✅ |
| Configure fstab（`PARTLABEL=<label> / ext4 defaults,x-systemd.growfs 0 1`） | 同上 | ✅ 完全一致 |
| Clean APT Cache + 删 resolv.conf | `40-system-config.sh`（apt clean）+ `rootfs.yml` → Cleanup Host Files | ✅ |
| Unmount Virtual File Systems（`if: always()`） | `scripts/host/03-umount-chroot.sh` + workflow `if: always()` | ✅（不再连带卸载镜像本身，避免 e2fsck 拒绝运行） |
| Unmount Image & Set UUID（`tune2fs -U ee8d3593-…`） | `scripts/host/04-finalize-image.sh` | 同 UUID；**新增** `e2fsck -fy` + `resize2fs -M` + 截断文件 |
| `[Custom]` Generate boot.img（本地 mkbootimg） | `scripts/host/11-make-bootimg.sh` | cmdline、base/kernel_offset/tags_offset/pagesize 与上游逐字一致 |
| Upload RootFS Image / Boot Image | `rootfs.yml` → upload-artifact ×2 | `retention-days: 14`、`compression-level: 1` 同上游 |

## 四、明确记录的行为差异

1. **不安装浏览器（默认）**：上游在 GNOME/KDE 里都装了 `firefox-esr`；Ubuntu 无 snap 系统装不了 Ubuntu 的 `firefox`，故改为 `browser` 输入项（`none` 默认，`firefox` 走 Mozilla 官方 apt 源）。
2. **不生成 initramfs**：与上游一致（内核 `CONFIG_EXT4_FS=y`，无需 initramfs）。副作用是 `custom_build` 下 plymouth splash 不会真正显示。
3. **失败即终止**：设备 deb 安装、`modules.dep` 缺失、snapd 存在、fstab 不符、关键文件缺失等都会让构建失败，而不是产出静默坏镜像（上游多处为静默继续）。
4. **`policy-rc.d` 生命周期**：chroot 内写入以阻止 postinst 启服务，出厂前删除并校验（上游无此机制，`sheng-devauth` 等 postinst 在 chroot 内的 `systemctl start` 会失败但被 `|| true` 掩盖）。
