# ubuntu-sheng

[![Validate](https://github.com/code002-2/ubuntu-sheng/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/code002-2/ubuntu-sheng/actions/workflows/validate.yml)
[![Build RootFS](https://github.com/code002-2/ubuntu-sheng/actions/workflows/rootfs.yml/badge.svg?branch=main)](https://github.com/code002-2/ubuntu-sheng/actions/workflows/rootfs.yml)

用 **GitHub Actions** 为**小米平板 6S Pro（sheng / 高通 SM8550）**构建 **Ubuntu arm64** 的 `rootfs.img` 与 `boot.img`，
产出物可直接用 `fastboot` 刷入设备。构建逻辑移植自 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng)（Debian 版）。

**系统中完全禁用 snap**（apt pin、构建期断言、末尾硬校验），不使用会带入 `snapd` 的 `ubuntu-desktop` / `kubuntu-desktop` 元包。
浏览器默认不安装（Ubuntu 主归档的 `firefox` 是 snap 过渡包），需要时可选 Mozilla 官方 apt 源装 deb 版。

## 已验证的构建

以下配置已在本仓库的 GitHub Actions 上**实际跑通并产出镜像**（2026-09-11）：

| 配置 | 构建记录 | 产物 | Artifact 大小¹ | 组装耗时 |
|---|---|---|---|---|
| Ubuntu 26.04 / **server** | [run 34596051825](https://github.com/code002-2/ubuntu-sheng/actions/runs/34596051825) | `rootfs-ubuntu-26.04-server-linux`<br>`boot-ubuntu-26.04-server-linux` | 973.5 MB<br>15.7 MB | 19 分钟 |
| Ubuntu 26.04 / **KDE Plasma** | [run 34603371147](https://github.com/code002-2/ubuntu-sheng/actions/runs/34603371147) | `rootfs-ubuntu-26.04-KDE-Plasma-linux`<br>`boot-ubuntu-26.04-KDE-Plasma-linux` | 1362.1 MB<br>15.7 MB | 90 分钟 |

¹ Artifact 是 zip 压缩后的大小；`rootfs.img` 是 ext4 镜像，刷写前请以解压后的实际大小为准（构建日志与 step summary 会打印）。

> Ubuntu arm64 的 apt 在 chroot 内偏慢：实测 `[chroot] Install Base Packages` ≈ 24 分钟、`Install Desktop`（Plasma）≈ 64 分钟，
> 因此桌面版整轮约 1.5 小时。这是耗时问题而非异常。（对比：姊妹项目 archlinux-sheng 同样的步骤用 pacman 并行下载，整轮仅约 10 分钟。）

**镜像尚未在真机上刷写验证过。**

## 快速开始

1. **Fork 本仓库**（公开仓库可用免费的 `ubuntu-24.04-arm` 原生 arm64 runner）。
2. **设置密码**：Settings → Secrets and variables → Actions → New repository secret，名称 `ROOTFS_PASSWORD`。
   > 未设置时构建仍会成功，但镜像里普通用户与 `root` 的密码会是默认值 `password`，构建日志会给出 `::warning::`。
3. **运行构建**：Actions → **Build RootFS (Ubuntu)** → Run workflow（保持默认参数即可）。
4. **下载产物**：该次运行的 Summary 页 → Artifacts → `rootfs-*.zip` 与 `boot-*.zip`。
5. **刷写**（假设使用 B 槽与 `linux` 分区）：

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

6. **首启检查**：`df -h /`（growfs 生效）、`uname -r`（与 `/usr/lib/modules/` 一致）、
   `dmesg | grep -i -E 'firmware|adreno|ath12k'`、`systemctl status adsprpcd-sensorspd iio-sensor-proxy`、
   能自动进桌面、`nmcli` 看到 WCN7850、`which snap` 为空，并实测 6 个 `xiaomi-*` 功能（快充 / 关机充电 /
   触控与手写笔 / 手写笔状态 / 指纹 / 键盘麦克风指示灯）。

## 参数说明

| 参数 | 默认值 | 说明 |
|---|---|---|
| **Ubuntu 版本** | `26.04 (resolute)` | 可选 `25.10 (questing)`；apt 源按版本自动选择（见下文） |
| **桌面环境** | `KDE Plasma` | `GNOME` / `server`（无图形界面） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop` |
| **browser** | `none` | `firefox` = 从 Mozilla 官方 apt 源安装 deb 版 |
| **autologin** | `true` | 自动登录（GNOME → `/etc/gdm3/custom.conf`；KDE → `/etc/sddm.conf.d/autologin.conf`） |
| **username / hostname** | `username` / `xiaomi-sheng` | 仅允许字母数字与 `_ . -` |
| **language** | `None (C.UTF-8)` | 10 种可选；选择后生成该 locale + `en_US.UTF-8`，写 `/etc/default/locale` 与 `/etc/locale.conf` |
| **boot_mode** | `dual (linux)` | `single (userdata)` / `dual (linux)` / `custom`；决定 fstab 的 `PARTLABEL=` 与使用哪个预编译 boot 镜像 |
| **custom_partition** | *(空)* | 仅 `boot_mode=custom` 需要，且必须搭配 `kernel_source=custom_build` |
| **quiet_boot** | `true` | 安装 Plymouth 并选用 `*_plymouth.img`；`server` 模式下自动忽略 |
| **kernel_source** | `prebuilt` | `prebuilt` = 取 [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) 的最新 release；`custom_build` = 自行编译 |
| **kernel_repo / kernel_branch / kernel_config** | `ianchb/sm8550-mainline` / `sheng-7.2.2` / `sm8550.config` | 仅 `custom_build` 使用 |
| **firmware_repo / firmware_branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源 |
| **rootfs_size** | `10G` | 镜像初始大小；构建后收缩，首启由 `x-systemd.growfs` 扩到分区实际大小 |
| **shrink_image** | `true` | 构建后 `e2fsck -fy` + `resize2fs -M` 收缩镜像 |
| **upload_artifacts** | `true` | 设为 `false` 只验证流程、不产出 Artifact（等价于上游的 rootfs-lite 模式） |

## 实现要点

**结构**：`rootfs.yml` 只做编排（解析参数 → 取内核 → 收集设备包 → 建镜像 → bootstrap → 挂 chroot →
镜像内 6 个阶段 → 卸载 → 收缩 → 上传）；设备功能包的构建放在可复用的 `_packages.yml`（`workflow_call`）；
具体步骤都在 `scripts/` 下的可审阅脚本里。上游把 44–45 KB 逻辑内联在 YAML 并额外复制出
`rootfs-lite.yml` / `fnnas-rootfs.yml`，本项目用 `upload_artifacts` 输入项替代"再复制一份"的做法。

**apt 源按版本选择**（重要）：从 Ubuntu 26.04 起 **arm64 已从 `ports.ubuntu.com` 迁到 `archive.ubuntu.com`**
（25.10 及更早仍用 ports）。`scripts/common/distro-env.sh` 按版本选择主源与安全源，
避免继续使用不再刷新的旧 pocket。

**设备功能包**：`alsa-xiaomi-sheng`（UCM2）、`firmware-xiaomi-sheng`、
`linux-xiaomi-sheng`（内核与模块）、`sheng-devauth`（键盘认证）、`sheng-sensors`（SSC 传感器注册表）、
`fastrpc`、`libssc`（含 QRTR 等待补丁）、`iio-sensor-proxy`（启用 SSC 后端），
以及从 [ianchb](https://github.com/ianchb) 的 6 个仓库下载的 `xiaomi-*` 包
（MiPPS 快充协商 / 充电模式 / 触控与手写笔 / 手写笔状态 / TEE 指纹 / 官方键盘助手）。

**相对上游补齐的环节**：`depmod`（上游全程缺失）、镜像收缩（上游产物恒为 10 GiB 稀疏文件）、
依赖解析失败即终止（上游静默继续，可能产出半配置镜像）、出厂前清理构建残留
（`/root/sheng-build`、`/tmp/debs`）、`policy-rc.d` 生命周期闭环并校验、
输入白名单校验、CI 静态自检 `validate.yml`。

**修正的上游缺陷**：
① `adsprpcd-sensorspd.service` 的拼写——上游 enable 的是不存在的 `adsrpcd-…`（少一个 `rp`），
即传感器守护进程从未被真正启用；
② GDM 自动登录路径——Ubuntu 的 gdm3 只读 `/etc/gdm3/custom.conf`，上游照搬的 Debian 路径在 Ubuntu 上静默失效。

**snap**：`15-nosnap.sh` 写 apt pin（`Pin: version *` + `Pin-Priority: -1`）并清除已装 snapd；
`10-base.sh` 断言 apt 无法安装 snapd，`90-verify.sh` 末尾硬校验。

## 仓库结构

```
.github/workflows/
  _packages.yml        workflow_call：8 个设备包构建作业 + xiaomi-* 下载作业
  rootfs.yml           主编排：参数解析 + 组装 rootfs.img / boot.img
  validate.yml         CI 静态自检：bash -n / shellcheck / YAML 解析 / 关键文件
scripts/
  common/              版本↔suite 映射、apt 源选择、日志工具
  host/                建镜像 / bootstrap / 挂载 chroot / 取内核 / 生成 boot.img / 卸载与收缩
  in-chroot/           基础包 / 禁用 snap / 桌面 / 浏览器 / 设备包 / 系统配置 / 校验
  lists/               包列表（一行一包）
  packages/            设备包构建脚本（dpkg-deb）
alsa-xiaomi-sheng/ firmware-xiaomi-sheng/ linux-xiaomi-sheng/ sheng-devauth/ sheng-sensors-files/
patches/ mkbootimg sm8550.config
```

## 已知限制

- **不生成 initramfs**（与上游一致）：内核 `sm8550.config` 中 `CONFIG_EXT4_FS=y`，可直接挂载 ext4 根分区启动。
  副作用是 `custom_build` 场景下 Plymouth splash 不会真正显示。
- **浏览器默认不装**：Ubuntu 主归档的 `firefox` / `chromium-browser` 都是 snap 过渡包，且 Ubuntu 无 `firefox-esr`；
  需要时请选 `browser=firefox`（Mozilla 官方 apt 源）。
- **设备固件替换语义**：`firmware-xiaomi-sheng` 声明 `Conflicts/Replaces: linux-firmware`
  （与 Debian 版同义），即用设备固件包**替换**发行版 linux-firmware。
  首启后请用 `dmesg | grep -i -E 'firmware|adreno|ath12k'` 确认 GPU/Wi-Fi 固件是否齐全。
- **可选包按 best-effort 安装**：桌面/字体等可选包若在某个版本缺失或改名，只会在日志里出现
  "跳过安装失败的包"告警；关键组件由 `90-verify.sh` 硬校验。
- **尚未真机验证**：镜像产出了，但未在设备上刷写与验收。

姊妹项目：[archlinux-sheng](https://github.com/code002-2/archlinux-sheng)（Arch Linux ARM，设备包为原生 pacman 包）。

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
