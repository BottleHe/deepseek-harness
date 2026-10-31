#!/usr/bin/env bash
# 将 linux-x64 桌面构建产物一键安装到 ~/Application/deepseek-harness，可重复运行完成升级。
#
# 结构：versions/<版本>-<时间戳>/ 保存每次安装的完整应用，current 软链原子指向最新版本；
# 升级不影响用户数据（应用数据在 ~/.dsh）。默认保留最近 3 个版本，其余自动清理。
#
# 用法：
#   apps/desktop/scripts/install-linux-desktop.sh                 # 安装/升级现有构建产物
#   apps/desktop/scripts/install-linux-desktop.sh --rebuild       # 先重新打包再安装
#   apps/desktop/scripts/install-linux-desktop.sh --source <目录> # 指定 linux-unpacked 目录
#   apps/desktop/scripts/install-linux-desktop.sh --root <目录>   # 指定安装根目录（默认 ~/Application/deepseek-harness）

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$BASH_SOURCE")/../../.." && pwd)
DEFAULT_SOURCE="$REPO_ROOT/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/linux-unpacked"
SOURCE=""
ROOT="$HOME/Application/deepseek-harness"
KEEP_VERSIONS=3
REBUILD=0

die() { echo "安装失败: $*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --rebuild) REBUILD=1 ;;
    --source) SOURCE=${2:?--source 需要一个目录参数}; shift ;;
    --root) ROOT=${2:?--root 需要一个目录参数}; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数 $1（--help 查看用法）" ;;
  esac
  shift
done
[ -n "$SOURCE" ] || SOURCE=$DEFAULT_SOURCE

# 国内网络下 GitHub 直连经常在收尾时挂起；镜像字节均由构建侧校验和保证。
export ELECTRON_MIRROR=${ELECTRON_MIRROR:-"https://mirrors.huaweicloud.com/electron/"}
export ELECTRON_BUILDER_BINARIES_MIRROR=${ELECTRON_BUILDER_BINARIES_MIRROR:-"https://gh-proxy.com/https://github.com/electron-userland/electron-builder-binaries/releases/download"}

command -v pnpm >/dev/null 2>&1 || die "未找到 pnpm；请先进入 Node >= 24.9 环境并完成 pnpm install"
command -v python3 >/dev/null 2>&1 || die "未找到 python3"

if [ "$REBUILD" -eq 1 ] || [ ! -d "$SOURCE" ]; then
  [ "$REBUILD" -eq 1 ] && echo "==> 重新打包 linux-x64（需要数分钟）……" \
    || echo "==> 未找到构建产物 $SOURCE，先执行打包……"
  (cd "$REPO_ROOT" && pnpm run package:desktop:linux:x64:unsigned:dir)
fi

[ -x "$SOURCE/deepseek-harness" ] || die "构建产物不完整（缺少可执行文件）: $SOURCE"
[ -f "$SOURCE/resources/app.asar" ] || die "构建产物不完整（缺少 app.asar）: $SOURCE"

VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
  "$REPO_ROOT/apps/desktop/package.json")
[ -n "$VERSION" ] || die "无法读取版本号"

# 复制期间应用不能在运行，否则文件替换会得到混合状态。
if pgrep -f "^$ROOT/" >/dev/null 2>&1; then
  die "检测到安装在 $ROOT 的应用正在运行，请先完全退出（含托盘进程）后重试"
fi

STAMP=$(date +%Y%m%d-%H%M%S)
STAGING="$ROOT/versions/.staging-$STAMP"
DEST="$ROOT/versions/$VERSION-$STAMP"
mkdir -p "$ROOT/versions"
rm -rf "$STAGING"

echo "==> 安装 $VERSION 到 $DEST（约 1.1 GB，请稍候）……"
cp -a "$SOURCE" "$STAGING"
mv "$STAGING" "$DEST"

# 原子切换 current：先生成临时软链再 rename，任何时刻 current 都指向完整版本。
if [ -e "$ROOT/current" ] && [ ! -L "$ROOT/current" ]; then
  echo "==> 移除旧结构的 current 目录"
  rm -rf "$ROOT/current"
fi
ln -s "versions/$VERSION-$STAMP" "$ROOT/.current.tmp.$$"
mv -T "$ROOT/.current.tmp.$$" "$ROOT/current"

# 清理旧版本：保留 current 指向的版本与最新的若干个。
CURRENT_REAL=$(readlink -f "$ROOT/current")
mapfile -t OLD < <(ls -1dt "$ROOT"/versions/*/ 2>/dev/null | tail -n +$((KEEP_VERSIONS + 1)) || true)
for directory in "${OLD[@]}"; do
  [ "$(readlink -f "${directory%/}")" = "$CURRENT_REAL" ] && continue
  echo "==> 清理旧版本 ${directory%/}"
  rm -rf "${directory%/}"
done

# 桌面菜单入口。StartupWMClass 与 Electron 的 desktopName（app_id / WM_CLASS）一致，
# 运行中的窗口才能和本条目关联并显示产品图标。
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/deepseek-harness.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DeepSeek Harness
Comment=DeepSeek Harness 桌面应用（本地 Linux 构建）
Exec=$ROOT/current/deepseek-harness
Icon=$ROOT/current/resources/icon.png
Terminal=false
Categories=Development;Utility;
StartupWMClass=deepseek-harness
EOF
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

# CLI 软链：已存在且不指向本安装时不动，避免覆盖其它 dsh。
BIN_DIR="$HOME/.local/bin"
CLI="$ROOT/current/resources/runtime/cli/bin/dsh"
if [ -e "$BIN_DIR/dsh" ] || [ -L "$BIN_DIR/dsh" ]; then
  if [ "$(readlink "$BIN_DIR/dsh" 2>/dev/null || true)" != "$CLI" ]; then
    echo "==> 跳过 CLI 软链：$BIN_DIR/dsh 已存在且非本安装"
  fi
else
  mkdir -p "$BIN_DIR"
  ln -s "$CLI" "$BIN_DIR/dsh"
  echo "==> 已创建 CLI 软链 $BIN_DIR/dsh（确认 ~/.local/bin 在 PATH 中）"
fi

echo "==> 完成：$VERSION 已安装到 $ROOT/current"
echo "    启动：$ROOT/current/deepseek-harness 或应用菜单中的 DeepSeek Harness"
echo "    回滚：ln -sfn versions/<旧版本目录> $ROOT/current"
