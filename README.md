# ubuntu-sheng

> 本项目是基于 [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) 的构建逻辑移植而来的**独立仓库**：
> 用 GitHub Actions 为**小米平板 6S Pro（sheng / 高通 SM8550）**构建 Ubuntu rootfs，产出可直接 fastboot 刷写的 `rootfs.img` 与 `boot.img`。
>
> **本仓库硬性要求：系统中完全禁用 snap。** 不安装 `snapd`（apt pin 断言 + 清除 + 构建末尾硬校验），
> 也不使用 `ubuntu-desktop` / `kubuntu-desktop` 这类硬依赖 snapd 的元包，浏览器走 Mozilla 官方 apt 源（deb 版）。

---

## 支持范围

| 项 | 说明 |
|---|---|
| Ubuntu 版本 | **26.04 LTS (Resolute Raccoon)**、**25.10 (Questing Quokka)** |
| 架构 | arm64（aarch64），包源使用 `ports.ubuntu.com/ubuntu-ports` |
| 桌面环境 | KDE Plasma（含 `plasma-mobile` 选项）/ GNOME / server（无图形界面） |
| 启动方式 | `dual (linux)`（双系统，默认）/ `single (userdata)` / `custom`（自定义分区名） |
| 内核 | `prebuilt`（取 [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline) 的最新 release）或 `custom_build`（自编译） |
| 设备功能包 | firmware、alsa UCM2、传感器（libssc + iio-sensor-proxy + 注册表）、键盘认证、以及 6 个 `xiaomi-*` 包 |

## 快速开始

1. Fork 本仓库，在 **Actions** 页面启用 workflow。
2. 选择 **Build RootFS (Ubuntu)** → **Run workflow**，按需填写参数（默认值即可直接构建）。
3. 构建完成后在该次运行的 **Artifacts** 中下载 `rootfs-ubuntu-*` 与 `boot-ubuntu-*`。
4. 刷写（与上游流程一致，假设使用 B 槽 + `linux` 分区）：

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

> 建议在仓库 Secrets 中设置 `ROOTFS_PASSWORD`（普通用户与 root 的密码）。
> 未设置时会回退到上游同样的不安全默认值 `password`，构建日志会给出警告。

## 参数说明

| 参数 | 默认 | 说明 |
|---|---|---|
| **Ubuntu 版本** | `26.04 (resolute)` | 25.10 为 Questing Quokka |
| **桌面环境** | `KDE Plasma` | `GNOME` / `server`（无 GUI） |
| **plasma_mobile** | `false` | 勾选后用 `plasma-mobile` 替代 `plasma-desktop` |
| **browser** | `none` | `firefox` = 从 Mozilla 官方 apt 源装 deb 版（Ubuntu 主归档的 firefox 是 snap 过渡包，在无 snap 系统上装不了） |
| **autologin** | `true` | 自动登录普通用户 |
| **username / hostname** | `username` / `xiaomi-sheng` | |
| **language** | `None (C.UTF-8)` | 选择后生成该 locale + `en_US.UTF-8`，写 `/etc/default/locale` 与 `/etc/locale.conf` |
| **boot_mode** | `dual (linux)` | 决定 fstab 的 `PARTLABEL=` 与使用哪个预编译 boot 镜像；`custom` 时必须搭配 `kernel_source=custom_build` |
| **custom_partition** | *(空)* | 仅 `boot_mode=custom` 时需要，只允许字母数字与 `_`/`-` |
| **quiet_boot** | `true` | 安装 Plymouth，并选用 `*_plymouth.img`（server 模式忽略） |
| **kernel_source** | `prebuilt` | `custom_build` 时用下面两组参数自行编译 |
| **kernel_repo / kernel_branch / kernel_config** | `ianchb/sm8550-mainline` / `sheng-7.2.2` / `sm8550.config` | `custom_build` 的内核仓库、分支与配置文件 |
| **firmware_repo / firmware_branch** | `ianchb/sheng-firmware` / `master` | 设备固件来源 |
| **rootfs_size** | `10G` | 初始大小；构建后收缩，首启靠 `x-systemd.growfs` 自动扩容 |
| **shrink_image** | `true` | 构建后 `e2fsck` + `resize2fs -M` 收缩镜像（上游没有这一步） |
| **upload_artifacts** | `true` | 测试构建可关闭，只验证流程而不产出 artifact |

## 禁用 snap 的实现

| 层 | 做法 | 位置 |
|---|---|---|
| 包选择 | 不使用 `ubuntu-desktop` / `ubuntu-desktop-minimal` / `kubuntu-desktop` 等元包，改用显式包列表（`gnome-shell`、`plasma-desktop` 等） | `scripts/lists/*.list` |
| apt 策略 | `/etc/apt/preferences.d/nosnap.pref` 把 `snapd` / `snap-confine` 的 `Pin-Priority` 设为 `-10`，并 `apt-mark hold snapd` | `scripts/in-chroot/15-nosnap.sh` |
| 清除 | 若基础镜像或依赖已带入 snapd，则 `apt-get purge` 并删除 `/snap`、`/var/lib/snapd` | 同上 |
| 浏览器 | Firefox 从 `packages.mozilla.org` 安装（deb 版），并对该源设高优先级 | `scripts/in-chroot/25-browser.sh` |
| 硬校验 | 构建末尾检查 `snapd` 未安装、`snap` 命令不存在、无 snap 目录，任一不满足即失败 | `scripts/in-chroot/90-verify.sh` |

## 仓库结构

```
.github/workflows/
  _packages.yml     # workflow_call：8 个设备功能包构建作业 + xiaomi-* 下载作业
  rootfs.yml        # 主编排：参数解析 + 组装 rootfs.img / boot.img
  validate.yml      # CI 自检：bash -n / shellcheck / YAML 解析 / 关键文件存在性
docs/
  parity-with-upstream.md   # 上游 rootfs.yml 各步骤 ↔ 本仓库文件的逐项对照（验收清单）
scripts/
  common/           # 版本↔suite 映射、日志工具（宿主与镜像内共用）
  host/             # 宿主阶段：建镜像 / bootstrap / 挂载 chroot / 取内核 / 生成 boot.img / 伸缩镜像
  in-chroot/        # 镜像内阶段：基础包 / 禁用 snap / 桌面 / 浏览器 / 设备包 / 系统配置 / 校验
  lists/            # 包列表（一行一个包，# 注释）
  packages/         # 设备功能包的构建脚本（dpkg-deb 打包）
alsa-xiaomi-sheng/  # UCM2 配置（deb 目录树）
firmware-xiaomi-sheng/ linux-xiaomi-sheng/ sheng-devauth/ sheng-sensors-files/
patches/ mkbootimg sm8550.config .gitattributes
```

## 相对上游 debian-sheng 的改动

1. **发行版**：`debootstrap trixie/forky` → Ubuntu 26.04 / 25.10，基线镜像用官方 `ubuntu-base` rootfs tarball（失败时回退 `mmdebstrap`），arm64 走 `ports.ubuntu.com`。
2. **禁用 snap**（见上表），上游 Debian 侧不存在该问题。
3. **补齐上游缺失的 `depmod`**：安装内核后执行 `depmod -a <kver>`，并要求 `modules.dep` 存在，否则构建失败。
4. **镜像收缩**：新增 `e2fsck -fy` + `resize2fs -M`（上游产物恒为 10 GiB 稀疏文件）。
5. **依赖解析失败即报错**：上游 `apt-get install /tmp/*.deb || apt-get install -f -y` 之后无条件删除 deb，可能在半配置状态下产出坏镜像；这里失败会终止构建。
6. **结构**：上游 `rootfs.yml` / `rootfs-lite.yml` / `fnnas-rootfs.yml` 是三份 44–45 KB 的复制粘贴；本仓库把设备包构建抽成 `_packages.yml`（workflow_call），把构建步骤抽成可审阅的 shell 脚本，测试模式合并为 `upload_artifacts` 输入项。
7. **修正 UCM 软链**：`alsa-xiaomi-sheng/.../conf.d/sm8550/Xiaomi-Pad6SPro.conf` 在上游是 symlink，在 Windows 上克隆会退化成普通文本文件，打包前显式重建。
8. **`policy-rc.d` 生命周期**：chroot 内阻止 postinst 启动服务，出厂前删除并校验（否则设备上服务永远起不来）。

## 已知限制

- 与上游一致：**不生成 initramfs**。内核 `sm8550.config` 中 `CONFIG_EXT4_FS=y`（ext4 内建），因此可以无 initramfs 直接挂载 ext4 根分区启动；这也意味着 Plymouth 的 splash 在 `custom_build` 场景下不会真正显示（上游同样如此）。
- `active` 分区（A 槽）保留原 Android/HyperOS 系统，Debian/Ubuntu 走 B 槽；切换槽位与分区调整请在 TWRP 内完成。
- 项目处于早期阶段，刷写会修改设备分区，请自行备份。

## 首次推送注意

- 本仓库**未初始化 git**（按需求"先不推送"）。在 Windows 上 `git init && git add` 时，
  脚本的**可执行位不会保留**（Windows 的 git 不跟踪 filemode）。这不影响构建：
  workflow 里每个直接执行的 `./scripts/...` 之前都显式 `chmod +x`，
  镜像内的脚本由 `scripts/host/02-mount-chroot.sh` 统一 `chmod -R 755`。
- `.gitattributes` 设了 `* text=auto eol=lf`，防止 CRLF 破坏 shell 脚本与 `mkbootimg`。
- `.gitignore` 排除了构建产物（`*.deb`、`*.img`、`debs/` 等），
  但**设备包目录树必须提交**：`alsa-xiaomi-sheng/`、`firmware-xiaomi-sheng/`、
  `linux-xiaomi-sheng/`、`sheng-devauth/`、`sheng-sensors-files/`（含 `DEBIAN/control`）、
  以及 `patches/`、`mkbootimg`、`sm8550.config`。

## 致谢

- **map220v** — TWRP、主线内核移植与大量设备适配
- **alghiffaryfa19** — 上游原始构建脚本
- **ianchb** — [debian-sheng](https://github.com/ianchb/debian-sheng) 与 `xiaomi-*` 设备功能包
