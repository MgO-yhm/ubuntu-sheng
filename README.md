# ubuntu-sheng

[![Validate](https://github.com/code002-2/ubuntu-sheng/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/code002-2/ubuntu-sheng/actions/workflows/validate.yml)
[![Build RootFS](https://github.com/code002-2/ubuntu-sheng/actions/workflows/rootfs.yml/badge.svg?branch=main)](https://github.com/code002-2/ubuntu-sheng/actions/workflows/rootfs.yml)

用 **GitHub Actions** 为**小米平板 6S Pro（sheng / 高通 SM8550）**构建 **Ubuntu arm64** 的 `rootfs.img` 与 `boot.img`，
产物可直接用 `fastboot` 刷入设备。构建逻辑移植自 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng)，
系统完全禁用 snap。姊妹项目：[archlinux-sheng](https://github.com/code002-2/archlinux-sheng)（Arch Linux ARM）。

## 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| **Ubuntu 版本** | `26.04 (resolute)` | 可选 `26.10 (stonking)`（开发中）与 `25.10 (questing)`；apt 源按版本自动选择（26.04 及以后 arm64 用 main archive，25.10 及更早用 ports） |
| **桌面环境** | `KDE Plasma` | `GNOME` / `server`（无图形界面） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop` |
| **browser** | `none` | `firefox` = 从 Mozilla 官方 apt 源安装 deb 版（Ubuntu 主归档的 `firefox` 是 snap 过渡包） |
| **autologin** | `true` | 自动登录（GNOME → `/etc/gdm3/custom.conf`；KDE → `/etc/sddm.conf.d/autologin.conf`） |
| **username / hostname** | `username` / `xiaomi-sheng` | 仅允许字母数字与 `_ . -` |
| **password** | *(空)* | 镜像密码（普通用户与 `root` 同密码）。优先用本输入项；留空则用仓库 Secret `ROOTFS_PASSWORD`；都为空时为 `password`。输入项会 `::add-mask::` 打码，但**值仍显示在该次运行的输入摘要里**，介意请改用 Secret |
| **language** | `None (C.UTF-8)` | 10 种可选；选择后生成该 locale + `en_US.UTF-8`，写 `/etc/default/locale` 与 `/etc/locale.conf` |
| **boot_mode** | `dual (linux)` | `single (userdata)` / `dual (linux)` / `custom`；决定 fstab 的 `PARTLABEL=` 与使用哪个预编译 boot 镜像 |
| **custom_partition** | *(空)* | 仅 `boot_mode=custom` 需要，且必须搭配 `kernel_source=custom_build` |
| **quiet_boot** | `true` | 安装 Plymouth 并选用 `*_plymouth.img`；`server` 模式下自动忽略 |
| **kernel_source** | `prebuilt` | `prebuilt` = 取 [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) 的最新 release；`custom_build` = 自行编译 |
| **kernel_release** | `7.2.6` | `prebuilt` 取哪个 release（留空则取最新；固定版本便于复现），boot 镜像与内核 deb 同源 |
| **kernel_repo / kernel_branch / kernel_config** | `ianchb/sm8550-mainline` / `sheng-7.2.6` / `sm8550.config` | 仅 `custom_build` 使用；仓库内 `sm8550.config` 与上游同名 release 同步（当前 = 7.2.6） |
| **firmware_repo / firmware_branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源 |
| **rootfs_size** | `10G` | 镜像初始大小；构建后收缩，首启由 `x-systemd.growfs` 扩到分区实际大小 |
| **shrink_image** | `true` | 构建后 `e2fsck -fy` + `resize2fs -M` 收缩镜像 |
| **upload_artifacts** | `true` | 设为 `false` 只验证流程、不产出 Artifact |

## 许可与第三方组件

本仓库是构建脚本集合，自身不声明开源许可证（上游 `debian-sheng` 亦未声明）。
仓库内包含的第三方内容如下，版权归各自权利人：

| 内容 | 来源 | 许可 |
|---|---|---|
| `mkbootimg` | AOSP `system/tools/mkbootimg` | Apache-2.0 |
| `sm8550.config` | [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) | GPL-2.0（Linux 内核配置） |
| `patches/`（`adsprpcd-sensorspd.service`、`wait_for_qmi_service.patch`） | 上游 `debian-sheng` 及其各自上游 | 随各上游仓库 |
| `sheng-sensors-files/`（SSC 传感器注册表、udev 规则） | 上游 `sheng-sensors` 包 | 随上游 |
| `alsa-xiaomi-sheng/`（UCM2 配置） | 上游 `alsa-xiaomi-sheng` 包 | 随上游 |
| 构建期下载的内核 deb、`xiaomi-*` deb、设备固件 | 各自的 GitHub release / 仓库 | 见对应上游仓库 |

`firmware-xiaomi-sheng` 在本仓库内只有包骨架（`DEBIAN/control`），**固件二进制在构建时从上游
`sheng-firmware` 下载**，本仓库不重新分发；这些固件版权归高通 / 小米等各自权利人，
仅用于在自有设备上运行 Linux。

## 致谢

- **map220v** — TWRP、主线内核移植与大量设备适配
- **alghiffaryfa19** — 上游原始构建脚本
- **ianchb** — [debian-sheng](https://github.com/ianchb/debian-sheng) 与 `xiaomi-*` 设备功能包
- **Dylan Van Assche** — `libssc` 与 `iio-sensor-proxy` 的 SSC 后端
