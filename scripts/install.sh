#!/bin/sh
#
# install.sh — 把当前目录发现的 Skill 安装到目标 skills 目录。
#
# 每个 Skill 是一个至少包含 SKILL.md 的目录，可能还有 references/、
# tests/ 等。安装即把整个目录平铺复制（或软链）到目标安装目录。
#
# 用法（在待安装 Skill 所在目录执行）:
#   /path/to/install.sh                      安装全部 Skill 到默认目录 (~/.claude/skills)
#   /path/to/install.sh deep-research ...    只安装指定的 Skill
#   /path/to/install.sh --update ...        更新目标目录里已安装的 Skill 到最新版
#                                           （不加名字=更新全部已安装；跳过内容未变化的）
#   /path/to/install.sh --list              列出当前目录可安装的 Skill
#   /path/to/install.sh --agent NAME ...    安装/更新到指定 coding agent 的 skills 目录
#                                           NAME: claude | codex | trae-cn（--list-agents 查看）
#   /path/to/install.sh --list-agents       列出内置的 agent 及其安装目录
#   /path/to/install.sh --target DIR ...    指定安装目录（优先级最高）
#   /path/to/install.sh --link ...          用软链接代替复制（开发时便于实时编辑）
#   /path/to/install.sh --dry-run ...       只打印将要执行的操作，不落盘
#   /path/to/install.sh --force ...         覆盖已存在的同名 Skill 时不再询问
#   /path/to/install.sh --help
#
# 源目录: 当前目录下有 skills/ 时使用 ./skills；当前目录本身包含
# SKILL.md 时安装该单个 Skill；否则扫描当前目录的直接子目录。
# 目标目录解析顺序: --target > --agent > $SKILLS_DIR > 默认(~/.claude/skills)
#
# 本脚本只用 POSIX sh 语法，可用 sh / dash / bash 运行：
#   sh /path/to/install.sh ...   或   /path/to/install.sh ...   或   bash /path/to/install.sh ...
#
set -eu

# ---- 定位脚本和当前工作目录内的 Skill 源 ----------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SELF="$SCRIPT_DIR/$(basename "$0")"
WORK_DIR=$(pwd -P)
if [ -d "$WORK_DIR/skills" ]; then
  SRC_DIR=$(cd "$WORK_DIR/skills" && pwd -P)
else
  SRC_DIR="$WORK_DIR"
fi

# ---- 内置 coding agent 的 skills 安装目录 ----------------------------------
# 各 agent 约定的 skills 目录（惯例为 ~/.<agent>/skills）。
# 未知 agent 会报错并提示用 --target。
agent_dir() {
  case "$1" in
    claude)  printf '%s\n' "$HOME/.$1/skills" ;;
    codex)   printf '%s\n' "$HOME/.$1/skills" ;;
    trae-cn) printf '%s\n' "$HOME/.$1/skills" ;;
    *)       return 1 ;;
  esac
}
KNOWN_AGENTS="claude codex trae-cn"

# ---- 默认配置 --------------------------------------------------------------
MODE="copy"        # copy | link
DRY_RUN=0
FORCE=0
UPDATE=0
DO_LIST=0
DO_LIST_AGENTS=0
AGENT=""
TARGET_OVERRIDE=""
SELECTED=""        # 用户指定的 Skill 名，换行分隔
SELECTED_COUNT=0

# ---- 输出辅助 --------------------------------------------------------------
info()  { printf '  %s\n' "$*"; }
warn()  { printf 'WARN: %s\n' "$*" >&2; }
err()   { printf 'ERROR: %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
  sed -n '3,26p' "$SELF" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# ---- 统计换行分隔列表里的非空行数 ------------------------------------------
list_count() {
  if [ -z "$1" ]; then echo 0; return; fi
  printf '%s\n' "$1" | grep -c .
}

# ---- 发现源目录内所有 Skill（目录名 = Skill 名，需含 SKILL.md）-------------
discover_skills() {
  [ -d "$SRC_DIR" ] || die "找不到 skills 源目录: $SRC_DIR"
  if [ -f "$SRC_DIR/SKILL.md" ]; then
    basename "$SRC_DIR"
    return
  fi
  for _d in "$SRC_DIR"/*/; do
    [ -d "$_d" ] || continue
    _name=$(basename "$_d")
    [ -f "$_d/SKILL.md" ] || continue   # 没有 SKILL.md 的目录不是 Skill
    printf '%s\n' "$_name"
  done
}

# ---- 获取 Skill 对应的源路径 -----------------------------------------------
skill_source() {
  if [ -f "$SRC_DIR/SKILL.md" ]; then
    [ "$(basename "$SRC_DIR")" = "$1" ] || return 1
    printf '%s\n' "$SRC_DIR"
  else
    printf '%s\n' "$SRC_DIR/$1"
  fi
}

# ---- 判断某个 Skill 是否已安装在目标目录（普通目录或软链均算）--------------
is_installed() {
  # $1=skill 名  $2=目标目录
  [ -e "$2/$1/SKILL.md" ] || [ -L "$2/$1" ]
}

# ---- 判断已安装内容与仓库源是否一致（一致则更新时跳过）--------------------
same_as_source() {
  # $1=源目录  $2=已安装目录；用 diff 递归比对，忽略 .DS_Store
  diff -r -q -x '.DS_Store' "$1" "$2" >/dev/null 2>&1
}

# ---- 解析参数 --------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage 0 ;;
    --list)         DO_LIST=1; shift ;;
    --list-agents)  DO_LIST_AGENTS=1; shift ;;
    --update)       UPDATE=1; shift ;;
    --link)         MODE="link"; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --force)        FORCE=1; shift ;;
    --agent)        [ $# -ge 2 ] || die "--agent 需要一个 agent 名参数"; AGENT="$2"; shift 2 ;;
    --agent=*)      AGENT="${1#*=}"; shift ;;
    --target)       [ $# -ge 2 ] || die "--target 需要一个目录参数"; TARGET_OVERRIDE="$2"; shift 2 ;;
    --target=*)     TARGET_OVERRIDE="${1#*=}"; shift ;;
    --)             shift
                    while [ $# -gt 0 ]; do
                      SELECTED="${SELECTED}${1}
"
                      SELECTED_COUNT=$((SELECTED_COUNT + 1)); shift
                    done ;;
    -*)             die "未知选项: $1（--help 查看用法）" ;;
    *)              SELECTED="${SELECTED}${1}
"
                    SELECTED_COUNT=$((SELECTED_COUNT + 1)); shift ;;
  esac
done

# ---- --list-agents: 列出内置 agent 及其目录后退出 --------------------------
if [ "$DO_LIST_AGENTS" -eq 1 ]; then
  info "内置 coding agent (--agent NAME):"
  for a in $KNOWN_AGENTS; do
    info "$(printf '%-10s -> %s' "$a" "$(agent_dir "$a")")"
  done
  info "其它 agent 用 --target DIR 指定任意目录。"
  exit 0
fi

# ---- 解析安装目标目录 ------------------------------------------------------
# 优先级: --target > --agent > $SKILLS_DIR > 默认(claude)
if [ -n "$TARGET_OVERRIDE" ]; then
  TARGET="$TARGET_OVERRIDE"
elif [ -n "$AGENT" ]; then
  TARGET=$(agent_dir "$AGENT") || die "未知 agent '$AGENT'（--list-agents 查看内置项，或用 --target 指定目录）"
elif [ -n "${SKILLS_DIR:-}" ]; then
  TARGET="$SKILLS_DIR"
else
  TARGET=$(agent_dir claude)
fi

# ---- --list: 列出可安装的 Skill 后退出 -------------------------------------
if [ "$DO_LIST" -eq 1 ]; then
  info "可安装的 Skill (源: $SRC_DIR):"
  discover_skills | while IFS= read -r s; do info "- $s"; done
  exit 0
fi

# ---- 计算待安装列表 --------------------------------------------------------
ALL_SKILLS=$(discover_skills)
[ -n "$ALL_SKILLS" ] || die "在 $SRC_DIR 下没有发现任何 Skill"

TO_INSTALL=""
if [ "$SELECTED_COUNT" -eq 0 ]; then
  if [ "$UPDATE" -eq 1 ]; then
    # 更新且未指定名字：只处理目标目录里已安装的 Skill
    [ -d "$TARGET" ] || die "目标目录不存在，没有可更新的 Skill: $TARGET"
    while IFS= read -r have; do
      [ -n "$have" ] || continue
      if is_installed "$have" "$TARGET"; then
        TO_INSTALL="${TO_INSTALL}${have}
"
      fi
    done <<EOF
$ALL_SKILLS
EOF
    [ -n "$TO_INSTALL" ] || die "目标目录里没有已安装的 Skill 可更新: $TARGET"
  else
    TO_INSTALL="$ALL_SKILLS"
  fi
else
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    if ! printf '%s\n' "$ALL_SKILLS" | grep -qxF "$want"; then
      die "仓库内没有名为 '$want' 的 Skill（--list 查看全部）"
    fi
    # 更新模式下要求该 Skill 已安装，避免把“更新”变成意外的新装
    if [ "$UPDATE" -eq 1 ] && ! is_installed "$want" "$TARGET"; then
      die "'$want' 尚未安装在 ${TARGET}，无法更新（去掉 --update 可安装它）"
    fi
    TO_INSTALL="${TO_INSTALL}${want}
"
  done <<EOF
$SELECTED
EOF
fi

# ---- 展示计划并落盘 --------------------------------------------------------
if [ "$UPDATE" -eq 1 ]; then printf 'Skill 更新\n'; else printf 'Skill 安装\n'; fi
info "源目录:   $SRC_DIR"
if [ -z "$TARGET_OVERRIDE" ] && [ -n "$AGENT" ]; then
  info "目标目录: $TARGET  (agent: $AGENT)"
else
  info "目标目录: $TARGET"
fi
if [ "$MODE" = link ]; then _mode='软链接 (--link)'; else _mode='复制'; fi
if [ "$DRY_RUN" -eq 1 ]; then _mode="$_mode  [dry-run]"; fi
info "方式:     $_mode"
info "数量:     $(list_count "$TO_INSTALL")"
printf '\n'

# dry-run 之外才真正创建目标目录
if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$TARGET"
fi
# 解析目标绝对路径（软链需要绝对源路径才稳妥）
TARGET_ABS="$TARGET"
if [ "$DRY_RUN" -eq 0 ]; then
  TARGET_ABS=$(cd "$TARGET" && pwd -P)
fi

installed=0
updated=0
skipped=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  src=$(skill_source "$name")
  dst="$TARGET_ABS/$name"
  src_abs=$(cd "$src" && pwd -P)
  if [ "$src_abs" = "$dst" ]; then
    info "源与目标相同，跳过 $name"; skipped=$((skipped + 1)); continue
  fi
  exists=0
  if [ -e "$dst" ] || [ -L "$dst" ]; then exists=1; fi

  # 更新模式：内容未变化则跳过，避免无谓重写
  if [ "$UPDATE" -eq 1 ] && [ "$exists" -eq 1 ]; then
    if [ "$MODE" = link ]; then
      # 已经是指向同一源的软链，视为未变化
      if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src_abs" ]; then
        info "未变化 $name"; skipped=$((skipped + 1)); continue
      fi
    elif [ ! -L "$dst" ] && same_as_source "$src_abs" "$dst"; then
      info "未变化 $name"; skipped=$((skipped + 1)); continue
    fi
  fi

  # 目标已存在时的处理：更新模式直接覆盖；安装模式按需询问
  if [ "$exists" -eq 1 ]; then
    if [ "$UPDATE" -eq 0 ] && [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
      printf '  %s 已存在，覆盖? [y/N] ' "$name"
      read -r ans </dev/tty || ans=""
      case "$ans" in
        y|Y|yes|YES) : ;;
        *) info "跳过 $name"; skipped=$((skipped + 1)); continue ;;
      esac
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      info "[dry-run] 移除已存在: $dst"
    else
      rm -rf "$dst"
    fi
  fi

  # 本条属于“更新”还是“新装”，用于日志与计数
  if [ "$exists" -eq 1 ]; then verb="更新"; else verb="安装"; fi

  if [ "$MODE" = link ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      info "[dry-run] ln -s $src_abs -> $dst"
    else
      ln -s "$src_abs" "$dst"
      info "已${verb}(链接) $name"
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      info "[dry-run] cp -R $src -> $dst"
    else
      cp -R "$src_abs" "$dst"
      find "$dst" -name '.DS_Store' -delete 2>/dev/null || true
      info "已${verb} $name"
    fi
  fi
  if [ "$exists" -eq 1 ]; then updated=$((updated + 1)); else installed=$((installed + 1)); fi
done <<EOF
$TO_INSTALL
EOF

printf '\n完成: 新装 %d 个, 更新 %d 个, 跳过 %d 个 -> %s\n' "$installed" "$updated" "$skipped" "$TARGET"
