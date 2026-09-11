# 构建排错与首启验收手册（Ubuntu）

本项目的流水线已在 GitHub Actions 上跑通并产出镜像（见 README 的"已验证的构建"）。
本文用于**排错**与**真机验收**，按出现顺序列出每一步的"正常表现 / 失败含义 / 处置"。

## 0. 触发前

- 先在 Settings → Secrets 里设置 `ROOTFS_PASSWORD`（未设置则镜像密码为默认值 `password`）。
- 想只验证流程不产出 Artifact 时，把 `upload_artifacts` 设为 `false`。
- 不想花一小时装桌面时，先用 `desktop=server` 跑一遍（组装作业约 19 分钟）。

## 1. 日志观测点

| 步骤 | 正常表现 | 失败含义与处置 |
|---|---|---|
| Install Host Tools | 安装 `mmdebstrap curl git e2fsprogs` | — |
| `[Prebuilt] Download Kernel & boot.img` | 打印 release tag 与 `boot_sheng_dualboot_plymouth.img` 等 | 报"未下载到 boot 镜像"= 该 release 没有这个变体 → 改 `quiet_boot=false` 或换 `boot_mode` |
| Bootstrap Ubuntu Base | 候选 URL 依次尝试，命中后打印 `VERSION_ID` | 全部失败会回退 `mmdebstrap`；仍失败可显式指定地址（脚本支持 `UBUNTU_BASE_URL` 环境变量） |
| `[chroot] Disable snap` | `snap 已禁用（pin + 清除 + hold 完成）` | — |
| `[chroot] Install Base Packages` | **必须出现"已确认 apt 无法安装 snapd（nosnap pin 生效）"**；此步耗时较长（≈24 分钟，见下） | 若变成 `nosnap.pref 未生效` → pin 写法在该版本上失效（社区通用的 `Pin: release a=*` 在 Ubuntu 上不匹配任何版本，本项目用 `Pin: version *`） |
| `[chroot] Install Desktop` | KDE Plasma ≈64 分钟、GNOME 类似；日志可能出现"跳过安装失败的包: xxx" | 桌面列表是 best-effort 安装：个别包改名只告警不失败（这是有意的，避免版本差异让整条构建失败）；关键包由校验步骤硬校验 |
| `[chroot] Install Browser` | `browser=none` 时直接跳过 | 选 `firefox` 时从 Mozilla 官方 apt 源安装；**不要**改用 Ubuntu 主归档的 firefox（snap 过渡包，硬依赖 snapd） |
| `[chroot] Install Device Packages` | `共收集到 N 个 deb`、`iio-sensor-proxy 使用本仓库版本: 99993.9-6`、`depmod` 生成索引 | ① `apt-get install` 报依赖错误 → 多为下载来的 `xiaomi-*.deb` 依赖了 Ubuntu 已改名的包，按报错包名核对；② 提示"装成了发行版版本"= 自建版没覆盖成功 |
| `[chroot] Verify Image` | 全部 `[ OK ]` | 任一 `[FAIL]` 都会让构建失败，按提示定位（snapd / 内核模块 `modules.dep` / fstab / 设备关键文件 / 显示管理器与 NetworkManager 是否 enable / locale） |
| Finalize Image | `镜像已收缩: 10G → x.xG`，并写入 step summary | 显示"失败（保持 10G）"时镜像仍可刷写，只是首启扩容前会占满分区 |

**耗时基线**（实测，仅供判断"是否卡死"参考）：`Install Base Packages` 约 24 分钟、
`Install Desktop`(Plasma) 约 64 分钟，KDE 版组装作业合计 **90 分钟**。
Ubuntu arm64 的 apt 在 chroot 内就是这么慢（下载串行 + dpkg 逐个解包），**不要据此判断为卡死**；
`timeout-minutes: 360` 足够覆盖。若日志长时间完全不动，再考虑是真卡住。

## 2. 刷写

前置：已解锁 BL、TWRP 已装、宿主机 `fastboot` 可用。双系统请先在 TWRP 里用 `parted` 缩小 `userdata`
并在末尾新建 `linux` 分区（概念参考 [alghiffaryfa19/Linux-xiaomi-sheng](https://github.com/alghiffaryfa19/Linux-xiaomi-sheng)）。

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

> ⚠️ 刷写会修改设备分区，请先备份。单系统模式（`boot_mode=single (userdata)`）会清空原有系统。

## 3. 首启验收判据

1. **根分区扩容**：`df -h /` 应接近 `linux` 分区大小（`x-systemd.growfs`）；否则查 `systemctl status systemd-growfs-root.service`。
2. **内核与模块**：`uname -r` 与 `/usr/lib/modules/` 下目录一致；`modprobe -c | head` 无报错（`modules.dep` 已在构建期生成）。
3. **固件**：`dmesg | grep -i -E 'firmware|adreno|ath12k|fastrpc'`。
4. **传感器链路**：`systemctl status adsprpcd-sensorspd iio-sensor-proxy`；`monitor-sensor` / `ssccli` 有输出。
5. **桌面**：`systemctl get-default` = `graphical.target`；自动登录生效（GNOME 看 `/etc/gdm3/custom.conf`，KDE 看 `/etc/sddm.conf.d/autologin.conf`）。
6. **网络**：`nmcli` 能看到 WCN7850；`rfkill list` 无硬阻塞。
7. **snap**：`which snap` 与 `dpkg -l snapd` 都应为空（构建期已断言，这里是最终确认）。
8. **6 个 `xiaomi-*` 功能**：MiPPS 快充协商、关机充电屏、触控/手写笔、手写笔蓝牙状态、TEE 指纹、官方键盘麦克风指示灯 —— 逐个实测。

## 4. 常见问题速查

| 症状 | 可能原因 | 处置 |
|---|---|---|
| 构建日志有 `::warning::未设置 ROOTFS_PASSWORD` | 未设 secret | 设置后重跑（否则镜像密码是 `password`） |
| `nosnap.pref 未生效` | pin 写法与版本不匹配 | 见上表；本项目已改用 `Pin: version *` + 断言 |
| 校验阶段 `[FAIL] 缺少 /usr/libexec/iio-sensor-proxy` | 设备 deb 未装上 | 看 `Install Device Packages` 的依赖报错 |
| 首启无 Wi-Fi / 无 GPU | 固件缺失 | 设备上 `dmesg` 确认；本项目固件包替换了 `linux-firmware`，必要时补装对应固件包 |
| 首启没进图形界面 | 显示管理器未 enable | 构建期 `90-verify.sh` 会校验；若单机检查用 `systemctl is-enabled gdm3/sddm` |
| 桌面缺少某些应用/字体 | best-effort 安装了但该包在该版本缺失 | 在构建日志搜"跳过安装失败的包" |

## 5. 常用排查命令

```bash
# 挂载产物镜像检查真实状态（在 x86 主机上可用 loop 挂载 ext4）
sudo mount -o loop rootfs.img /mnt && sudo chroot /mnt /bin/bash

# 包层面
dpkg -l | grep -E 'iio-sensor|libssc|firmware-xiaomi|linux-xiaomi'
apt-cache policy snapd          # Candidate 应为 (none)

# 设备侧
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy -u NetworkManager --no-pager
```
