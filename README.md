# Linbox

在 Android 上以 **proot** 运行 **Alpine / Ubuntu / Debian** 的轻量 Linux 终端 App。

> Linbox 是一个纯「本地 Linux」项目：去掉了 SSH、本机 shell、服务器 / SFTP / 系统信息
> 等子系统，只保留一个能力 —— 在手机上跑多个互相独立的 Linux 实例，每个实例拥有自己的
> rootfs，可在首页并存、拖拽排序、单独编辑 / 删除。

## 功能

- **多实例并存**：首页列出所有 Linux 实例，点进去即进入对应终端
- **三种发行版**：Alpine（minirootfs）、Ubuntu（ubuntu-base）、Debian（自定义 rootfs URL）
- **粒度配置**：发行版 + 版本 + 镜像 / 软件源 + 自定义 DNS / 镜像 URL
- **真 PTY 终端**：基于 `flutter_pty` + 本地修改版 `xterm`，支持 resize、交互程序、提示符
- **server_box 同款交互**：长按选词、选区手柄、虚拟按键条（Ctrl / Esc / 方向键等）、
  修饰键自动取消、手机输入法键盘联动
- **本地持久化**：实例元数据存 SharedPreferences，rootfs 落盘在
  `files/linux/<id>/rootfs`，不联网、不上传

## 页面

1. **首页** — 多个 Linux 实例列表，点击进入终端；FAB / 设置入口添加实例；支持拖拽排序
2. **终端** — 交互式 proot shell（xterm + flutter_pty），未部署时自动下载解压，失败可重试
3. **添加 / 编辑实例** — 名称、发行版、版本、镜像/软件源、Debian 的 Rootfs URL、DNS
4. **设置** — 主题、终端字号、实例管理（状态 / 占用 / 编辑 / 删除）、虚拟按键、关于

## 实例配置粒度

| 字段 | 说明 |
|---|---|
| 名称 | 任意，首页与终端标题显示 |
| 发行版 | `Alpine` / `Ubuntu` / `Debian` |
| 版本 | 各发行版可选版本（新 → 旧） |
| 镜像 / 软件源 | Alpine/Ubuntu 为 rootfs + apk/apt 源基址；Debian 为 apt 源基址 |
| Rootfs URL | 仅 Debian 需要：填写 aarch64 rootfs tarball 链接（`.tar.gz` / `.tar.xz`） |
| DNS | 空格 / 逗号分隔，默认 `1.1.1.1 8.8.8.8` |

### 为什么 Debian 要填 Rootfs URL

Debian 没有统一稳定的「官方单文件 rootfs tarball」（proot-distro 新版本改为 Docker
registry，GitHub API 与 LXC 镜像站路径均不稳定）。因此 Debian 走「自定义 Rootfs URL」
模式：你自己提供一个 aarch64 rootfs tarball 链接（支持 gzip 或 xz 压缩），Linbox 负责
下载、解压、并写入 `sources.list`。

Alpine（`alpine-minirootfs-<ver>-aarch64.tar.gz`）与 Ubuntu（`ubuntu-base-<ver>-base-
aarch64.tar.gz`）的 rootfs 是官方单文件，可直接从镜像下载，无需手动填 URL。

## 本地 Linux 终端（proot）

每个实例的 rootfs 独立部署：

- 进入终端页时，若未部署则自动 **下载 → 解压 → 写 resolv.conf / 软件源 / hosts / 标记文件**；
- 失败显示错误并支持「重试」；
- 删除实例会清理其整个 `linux/<id>` 目录（含 rootfs）；
- proot 环境 **不是容器**：无内核隔离，`-0` 只是 fake root，ptrace 有性能损耗。

### 已知限制（proot 固有，非 bug）

- **网络探测类工具**：`ping` / `nano` / `vim` 等程序依赖的某些 syscall 会被 proot 默认的
  seccomp 拦截掉并返回 `Bad system call`，已在启动环境设置 `PROOT_NO_SECCOMP=1` 关闭
  seccomp（回退 ptrace）规避。少数设备若仍报 `Operation not permitted`，是 Android 收走了
  `CAP_NET_RAW`，属设备固有限制，纯 proot 无法解决。
- **netlink 工具不可用**：`ip addr` / `ip link` / `ss -i` 等走 netlink，需要真实
  `CAP_NET_ADMIN`，fake root 拿不到，会报 `Permission denied`。替代查看方式：
  - 列网卡：`cat /proc/net/dev`
  - 看路由：`cat /proc/net/route`
  - 测连通 / 解析：`curl -I https://example.com`、`getent hosts example.com`

### proot 二进制（不进仓库，构建时生成）

需要两个文件，都放在 `android/app/src/main/jniLibs/arm64-v8a/`：

| 文件 | 作用 |
|---|---|
| `libproot.so` | proot 本体 |
| `libproot-loader.so` | proot 的 loader，运行时通过 `PROOT_LOADER` 指过去 |

targetSdk ≥ 29 不允许 exec 应用私有目录里的文件，而 rootfs 全在那里。proot 不用 execve
执行 guest 二进制，而是用自带 loader 映射 guest ELF —— 所以 loader 自己必须可执行，只能是
nativeLibraryDir（`apk_data_file`）。配套要求：

- `android/app/build.gradle`：`packaging.jniLibs.useLegacyPackaging = true`
- `AndroidManifest.xml`：`android:extractNativeLibs="true"`

（minSdk ≥ 23 时原生库默认不解包，不开这两项 `nativeLibraryDir` 根本不存在。）

生成方式（需要 NDK）：

```bash
scripts/build-proot-android.sh            # 输出到 jniLibs/arm64-v8a/
scripts/build-proot-android.sh --clean    # 清理
```

脚本锁定了 `termux/proot` 的 `v5.1.107.90`（tag + commit）与 talloc 2.4.2，用 NDK 的
`aarch64-linux-android26-clang` 编译。仓库里 **不含** 编译产物：没有这两个 so 时，Linux
会话会提示缺少 proot。

## 本地运行

需要已安装 Flutter stable（Dart ≥ 3.4）与 Android SDK。

```bash
cd Linbox
flutter pub get
flutter run
```

### 仅编译 arm64 APK

```bash
flutter build apk --release --target-platform android-arm64
# 产物一般在:
#   build/app/outputs/flutter-apk/app-release.apk
# 或 split:
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

工程已在 `android/app/build.gradle` 中限制 `abiFilters "arm64-v8a"`，不会打出其他 ABI。

## CI

`.github/workflows/build-android-arm64.yml`：

- push / PR / 手动触发时编译 **arm64-v8a** release APK
- 上传 Artifact：`linbox-arm64-v8a-release`
- 打 `v*` tag 时自动创建 GitHub Release

## 包名

- applicationId / namespace: `com.linbox.app`
- compileSdk / targetSdk: `36`
- minSdk: Flutter 默认（通常 21）
- 仅 `arm64-v8a`

## 权限

- `INTERNET`
- `ACCESS_NETWORK_STATE`

## 目录结构

```
lib/
  main.dart
  models/
    linux_distro.dart        # 发行版定义（Alpine/Ubuntu/Debian）、镜像、软件源
    linux_instance.dart      # 实例模型（字段 / 序列化 / rootfsUrl）
    virt_key_def.dart        # 虚拟按键定义
  services/
    linux_store.dart         # 多实例持久化（SharedPreferences）
    linux_env.dart           # rootfs 部署（下载/解压 gz+xz/配置）
    linux_session.dart       # proot 会话（flutter_pty）
    settings_store.dart      # 主题/字号/虚拟按键/退出确认
    virt_key_input_handler.dart
  pages/
    home_page.dart           # 多实例列表 + 排序
    terminal_page.dart       # proot 终端（部署+渲染+选词+虚拟按键）
    linux_edit_page.dart     # 新增/编辑实例
    settings_page.dart       # 设置 + 实例管理
    virt_keys_settings_page.dart
  widgets/
    virt_keys.dart
    selection_handles.dart
android/app/src/main/jniLibs/arm64-v8a/   # libproot.so + libproot-loader.so（构建产物）
scripts/build-proot-android.sh           # NDK 编译 proot
packages/xterm/                          # 本地修改版 xterm（支持选区手柄等）
.github/workflows/build-android-arm64.yml
```
