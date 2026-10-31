# Linux x64 本地桌面构建（linux-desktop-x64 分支）

本分支在官方 mac-arm64 / mac-x64 / win-x64 三个发布目标之外，新增 **linux-x64 本地构建**能力。范围是 unsigned 本地构建：不签名、不公证、无自动更新通道、不上传发布，仅用于在 Linux x64 机器上运行桌面应用。

上游明确不把 Linux 作为 Desktop 发布目标（见 `apps/desktop/packaging/README.md` 与架构决策记录 2026-08-25），本分支不改变该产品决策，只补齐本地构建路径。

## 构建

前置要求：

- Node.js ≥ 24.9（例如 `nvm use v26.13.0`）、仓库已 `pnpm install`
- Linux x64 构建主机（目标与主机平台必须一致）
- 网络可下载 Electron / Node / Python 运行时（首次约 300–500 MB）

命令（在仓库根目录）：

```sh
# 目录构建（最快验证路径，产物为可直接运行的目录）
pnpm run package:desktop:linux:x64:unsigned:dir

# AppImage（unsigned，走 electron-builder linux AppImage 目标）
pnpm run package:desktop:linux:x64:unsigned
```

构建流程与 mac/win 完全一致：全仓库构建 → 打包工作区包 → 准备 Electron + 主运行时（Node/Python/pnpm）→ 准备 dsh 运行时树 → electron-builder → 打包产物冒烟（含 DOCX/XLSX/PPTX → PDF 转换）。

产物位置（已在本机验证可启动）：

- 目录构建：`apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/linux-unpacked/`
  - 可执行文件 `linux-unpacked/deepseek-harness`，CLI 启动器 `linux-unpacked/resources/runtime/cli/bin/dsh`
- AppImage：同目录下 `deepseek-harness-<版本>-linux-x86_64-unsigned.AppImage`（约 360 MB）

### 网络加速（国内网络建议）

直连 github.com / files.pythonhosted.org 可能只有 20–40 KB/s，且 GitHub 资产下载常在收尾时挂起（ETIMEDOUT）。全部手段的字节完整性都由 SHA-256 或内嵌校验和保证：

```sh
# 1. 预填充 Python 归档与 wheels 缓存（阿里云 PyPI 镜像 + gh-proxy.com）
python3 apps/desktop/scripts/seed-runtime-download-cache.py linux-x64

# 2. Electron 与 electron-builder 工具链走镜像（AppImage 构建必需）
export ELECTRON_MIRROR="https://mirrors.huaweicloud.com/electron/"
export ELECTRON_BUILDER_BINARIES_MIRROR="https://gh-proxy.com/https://github.com/electron-userland/electron-builder-binaries/releases/download"

pnpm run package:desktop:linux:x64:unsigned:dir
```

缓存位于 `apps/desktop/.desktop-build/downloads/`（以 sha256 为文件名），重复构建直接命中。

### 运行说明

- 本机（Ubuntu, kernel 6.8, X11）上 Electron 原生沙箱直接可用，无需 `--no-sandbox`。若你的发行版限制了非特权 user namespace 且启动报 sandbox 错误：`sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox`，或临时用 `--no-sandbox` 启动。
- 首次启动会打开欢迎窗口并写入 `~/.dsh`（桌面 profile）。
- Office 转 PDF 使用 `libreoffice-kit-wasm` 引擎（上游未发布 Linux 原生引擎），已通过打包冒烟验证。
- 应用图标：安装脚本写入的启动器条目指向 `resources/icon.png`；窗口标题栏/任务栏/Alt-Tab 图标由 `BrowserWindow({ icon })` 提供同一资源；打包清单的 `desktopName` 与条目名、`StartupWMClass` 三者一致（均为 `deepseek-harness`），运行中的窗口才会和启动器条目关联并显示产品图标，而不是默认的 Electron 图标。
- 系统托盘与关闭行为：Linux 与 Windows 一致，关闭主窗口隐藏到托盘（首次关闭有一次提示），托盘提供「打开 / 退出」入口，托盘图标即应用图标（32 px）。Ubuntu 桌面默认带 AppIndicator 支持，直接可用；vanilla GNOME 需先启用 AppIndicator 扩展。托盘宿主不可用时（如缺少 libayatana-appindicator），关闭窗口改为走标准退出确认直接退出，避免留下无法找回的后台进程；任何时候重新运行可执行文件都会聚焦已有实例（单实例锁）。Windows 隐藏到托盘、macOS 隐藏到 Dock 的行为不变。
- 宿主进程意外退出自动恢复：运行中的工作区遇到宿主进程意外终止（例如 Electron 在高并发子进程负载下的内部断言崩溃，`libuv-worker trap int3`）时，自动重启宿主并重新加载工作区页面（滚动 10 分钟内最多 3 次；每次均写入崩溃报告并在更新日志记录 `host-restarted`），只有恢复失败或预算耗尽才进入原有的致命恢复对话框。启动阶段的失败不重试，仍直接走致命恢复。

## 一键安装与升级（本机）

安装到 `~/Application/deepseek-harness`，结构为 `versions/<版本>-<时间戳>/` + `current` 原子软链；重复运行即完成升级，保留最近 3 个版本可回滚，用户数据（`~/.dsh`）不受影响。同时写入应用菜单入口（`~/.local/share/applications/deepseek-harness.desktop`）并创建 `~/.local/bin/dsh` CLI 软链：

```sh
apps/desktop/scripts/install-linux-desktop.sh               # 安装/升级现有构建产物
apps/desktop/scripts/install-linux-desktop.sh --rebuild     # 先重新打包再安装（上游同步后常用）
```

应用运行中脚本会拒绝安装并提示退出。回滚：`ln -sfn versions/<旧版本目录> ~/Application/deepseek-harness/current`。

## 与上游同步

上游原始仓库为 `source` remote（deepseek-ai/deepseek-harness），个人 fork 为 `origin`：

```sh
git fetch source
git rebase source/master     # 或 merge；本分支改动小且加性，冲突通常集中在下列文件
pnpm install                 # 依赖变化时
pnpm run package:desktop:linux:x64:unsigned:dir   # 重新构建验证
pnpm exec vitest run apps/desktop/tests/desktop-build-paths.spec.ts apps/desktop/tests/package-target.spec.ts apps/desktop/tests/prepare-runtime-patches.spec.ts
```

每次同步后重点检查（上游改动最可能冲突/失效的位置）：

- `apps/desktop/scripts/package-target.ts` 的 `TARGETS` 注册表与宿主机校验
- `apps/desktop/scripts/desktop-build-paths.mjs` / `.d.mts` 的 `SUPPORTED_TARGETS` 与平台映射
- `apps/desktop/scripts/prepare-runtime.ts`、`prepare-dsh.ts` 的 Electron 可执行文件三段路径
- `apps/desktop/scripts/electron-builder-config.mjs` 的 `linux` 段（icon / executableName / syncDesktopName）与 `extraMetadata.desktopName`
- `apps/desktop/patches/libreoffice-kit@0.1.5.patch`：若上游升级 `@deepseek-ai/libreoffice-kit` 版本，需同步 `runtime-patch-policy.ts` 中的 spec 并按新版本内容重新生成补丁（修的是 asar 环境下 `lstatSync(…, { throwIfNoEntry: false })` 返回 `null` 导致 Linux WASM 引擎回退失效的问题；上游修复该问题后可直接删除补丁）

## 本分支改动清单

| 文件 | 改动 |
|---|---|
| `apps/desktop/scripts/package-target.ts` | TARGETS 增加 linux-x64；宿主机校验；unsigned 非 Windows 使用本地环境；release-record 文件名守卫 |
| `apps/desktop/scripts/desktop-build-paths.mjs` / `.d.mts` | 白名单与平台映射加入 linux-x64；新增 `DesktopBuildTarget` 类型 |
| `apps/desktop/scripts/desktop-package-environment.mjs` / `.d.mts` | 平台类型放宽；signed Linux 显式报错；unsigned 非 Windows 跳过强制更新策略 |
| `apps/desktop/scripts/desktop-toolchain-preflight.ts` | 平台联合类型加入 `linux`（仅 tar 探测） |
| `apps/desktop/scripts/prepare-runtime.ts` / `prepare-dsh.ts` | Electron 可执行文件路径三段化（win32/darwin/linux） |
| `apps/desktop/scripts/prepare-cli.ts` + `apps/desktop/cli/dsh-linux` | Linux `dsh` 启动器（按 `resources/` 相对路径解析可执行文件） |
| `apps/desktop/scripts/smoke-packaged-runtime.ts` | `linux-unpacked` 布局与 `deepseek-harness` 可执行文件路径 |
| `apps/desktop/scripts/electron-builder-config.mjs` | unsigned 非 Windows 跳过策略；linux 段补 icon / executableName / syncDesktopName，extraMetadata 补 `desktopName`（Linux app_id / WM_CLASS 与启动器条目一致） |
| `apps/desktop/src/window-icon.ts`、`src/main.ts`、`src/welcome-window.ts` | Linux 窗口图标：主窗口与欢迎窗口通过 `BrowserWindow({ icon })` 使用 `resources/icon.png`（标题栏/任务栏/Alt-Tab 不再显示默认 Electron 图标）；Linux 启用系统托盘（应用图标 32 px，首次关闭提示一次），有托盘时关闭即隐藏、无托盘宿主时关闭走标准退出确认，win/mac 行为不变 |
| `src/main.ts` 宿主崩溃恢复 + `src/update-journal.ts` | 运行中的工作区遇到宿主意外退出时自动重启宿主并重载工作区页面（预算内不弹致命对话框），复用更新安装的恢复路径；诊断照常写入崩溃报告，更新日志新增 `host-restarted` |
| `apps/desktop/scripts/install-linux-desktop.sh` | 启动器条目补 `StartupWMClass=deepseek-harness`，运行中的窗口与条目正确关联 |
| `apps/desktop/scripts/runtime-patch-policy.ts` + `apps/desktop/patches/libreoffice-kit@0.1.5.patch` | 运行时专用补丁：修复 asar 下 LibreOfficeKit Linux WASM 引擎回退 |
| `apps/desktop/scripts/desktop-upload-plan.ts`、`upload-target.ts`、`desktop-edgeone.ts`、`retain-desktop-ci.ts`、`development-project.ts` | 上传/公证/CI 保留流程保持 mac/win-only（类型收窄为 `DesktopAutoUpdateTarget`）；dev 启动放宽为 `DesktopBuildTarget` |
| `apps/desktop/scripts/seed-runtime-download-cache.py` | 镜像预填充下载缓存辅助脚本 |
| `apps/desktop/package.json`、`package.json` | `package:linux:x64:unsigned[:dir]` 脚本 |
| 相关 spec | `desktop-build-paths` / `package-target` / `prepare-runtime-patches` 断言随行为更新；`linux-desktop` / `window-icon` 覆盖图标关联，`welcome-window` / `main-startup` 断言窗口 icon |

## 已知限制

- 仅支持 unsigned：无签名 / 公证 / 自动更新 / 发布上传（Linux 无对应基础设施，上游亦无此计划）。
- `check:package` 在 Linux 主机仍会失败（它走 signed 配置路径，符合 fail-loud 语义）。
- LibreOffice Linux 原生引擎（`libreoffice-kit-linux-x64-glibc`）从未发布到 npm，Office 转换始终走 WASM 引擎。
- 本机环境基线：`apps/desktop/tests/macos-notarization-proxy.spec.ts` 在干净的 master 上同样失败（flock 插件按需编译在该测试上下文失败），与本分支无关。
