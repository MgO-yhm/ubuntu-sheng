# 首次构建清单（Ubuntu 版）

> 本仓库全部代码都是**静态编写**的（开发环境禁止执行 bash/git/tar/python），
> 因此语法、接线、路径都靠逐行审查 + 跨仓库一致性核对保证，**但没有实跑过**。
> 按下面顺序做，能把第一次排错时间压到最短。

## 0. 先跑静态自检

push 后 `.github/workflows/validate.yml` 会自动触发（也可手动 Run）：

- 全部 `.sh` 的 `bash -n`
- `shellcheck --severity=warning`
- 解析 `.github/workflows/*.yml`
- 关键文件存在性（`mkbootimg`、`sm8550.config`、包列表、设备包目录树）

**不通过就不要浪费构建时间。**

## 1. 准备

1. 推到你自己的 GitHub，启用 Actions（需要能拿到 `ubuntu-24.04-arm` runner：public repo 免费）。
2. 设置 secret `ROOTFS_PASSWORD`（不设也能构建，但镜像密码是不安全的默认值 `password`，日志有 `::warning::`）。

## 2. 第一次构建：建议参数

| 输入 | 建议 | 理由 |
|---|---|---|
| `upload_artifacts` | `false` | 先只验证流程，成功后再改 true 跑一次 |
| `desktop` | `KDE Plasma`（默认） | 一次只改一个变量 |
| `quiet_boot` | `false` 先试 | 排除 plymouth 变量 |
| `kernel_source` | `prebuilt`（默认） | `custom_build` 会多花 30–60 分钟 |

## 3. 构建日志里要盯的点（按出现顺序）

| 步骤 | 正常表现 | 失败/异常的含义与处置 |
|---|---|---|
| `[Prebuilt] Download Kernel & boot.img` | 打印 release tag 与 `boot_sheng_dualboot_plymouth.img` | 报"未下载到 boot 镜像"= 该 release 没有这个变体 → 改 `quiet_boot=false` 或换 `boot_mode` |
| `Bootstrap Ubuntu Base` | 候选 URL 依次尝试，命中后打印 `VERSION_ID` | 全部失败会回退 `mmdebstrap`；仍失败就用 `UBUNTU_BASE_URL` 指定可用地址（国内镜像更快） |
| `[chroot] Disable snap` | `snap 已禁用` | — |
| `[chroot] Install Base Packages` | **必须出现 `已确认 snapd 被 pin 到 -10`** | 若变成 `错误: nosnap.pref 的 Pin-Priority 未生效` → 该版本的 `Pin: release a=*` 不匹配，需要改 pin 写法（按 `origin "Ubuntu"` 或 `Pin: version *`） |
| `[chroot] Install Desktop` | 若出现 `跳过安装失败的包: xxx` 警告，**记下包名** | 桌面列表是 best-effort（有意如此，避免 25.10/26.04 包改名让整条构建挂掉），但缺包会让桌面不完整 |
| `[chroot] Install Device Packages` | `共收集到 N 个 deb`、`iio-sensor-proxy 使用本仓库版本: 99993.9-6` | ① `apt-get install` 报依赖错误 → 多为下载来的 `xiaomi-*.deb` 依赖了 Ubuntu 已改名的包；② 提示"装成了发行版版本"= 自建版没覆盖成功 |
| `[chroot] Verify Image` | 全部 `[ OK ]` | 任一 `[FAIL]` 会让构建失败，按提示定位（snapd / 内核模块 / fstab / 关键文件 / 显示管理器 / locale / 传感器服务启用状态） |
| `Finalize Image` | `镜像已收缩: 10G → x.xG`，并写入 step summary | 若显示"失败（保持 10G）"：产物仍可刷写，但首启扩容前会占满分区 |

## 4. 刷写（B 槽 + `linux` 分区；双系统请在 TWRP 内先分好区）

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot.img
fastboot flash linux rootfs.img
fastboot reboot
```

## 5. 首启后的验收判据

1. **扩容**：`df -h /` 应接近 `linux` 分区大小（`x-systemd.growfs`）；否则看 `systemctl status systemd-growfs-root.service`。
2. **内核/模块**：`uname -r` 与 `/usr/lib/modules/` 下目录一致，`modprobe -c | head` 无报错。
3. **固件**：`dmesg | grep -i -E 'firmware|adreno|ath12k|fastrpc'`（缺 Adreno/WiFi 固件说明固件包没覆盖到）。
4. **传感器**：`systemctl status adsprpcd-sensorspd iio-sensor-proxy`；`monitor-sensor` / `ssccli` 有输出。
5. **桌面**：`systemctl get-default` = `graphical.target`；自动登录生效（GNOME 看 `/etc/gdm3/custom.conf`，KDE 看 `/etc/sddm.conf.d/autologin.conf`）。
6. **网络**：`nmcli` 能看到 WCN7850，`rfkill list` 无硬阻塞。
7. **snap**：`which snap` 与 `dpkg -l snapd` 都应为空（构建期已断言，这里是最终确认）。
8. **6 个 `xiaomi-*` 功能**：MiPPS 120W 快充协商、关机充电屏、触控/手写笔、手写笔蓝牙状态、TEE 指纹、官方键盘麦克风指示灯 —— 逐个实测（它们的运行时依赖是估算的，见各构建脚本头部注释）。

## 6. 最可能需要调整的三处

| 事项 | 位置 | 判据 |
|---|---|---|
| `Pin: release a=*` 是否生效 | `scripts/in-chroot/15-nosnap.sh` | 构建日志里的 pin 断言（已在构建期强制失败） |
| 6 个 `xiaomi-*.deb` 的 Depends 能否在 26.04 解析 | `scripts/in-chroot/30-device-packages.sh` | 安装步骤是否报依赖错误 |
| `plasma-mobile` 在 26.04 的打包状态 | `scripts/lists/kde-mobile.list` | 日志里是否出现"跳过安装失败的包: plasma-mobile" |

## 7. 排错命令

```bash
# 挂载产物镜像检查真实状态
sudo mount -o loop rootfs.img /mnt && sudo chroot /mnt /bin/bash
# 包层面
dpkg -l | grep -E 'iio-sensor|libssc|firmware-xiaomi|linux-xiaomi'; apt-cache policy snapd
# 设备侧
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy -u NetworkManager --no-pager
```
