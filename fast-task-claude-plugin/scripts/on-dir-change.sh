#!/bin/bash
# Hook Script for CwdChanged
# 目录切换时的上下文更新

set -e

# 读取 Hook 输入
INPUT=$(cat)

# 提取关键信息
OLD_CWD=$(echo "$INPUT" | jq -r '.oldCwd // ""')
NEW_CWD=$(echo "$INPUT" | jq -r '.newCwd // ""')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Working Directory Changed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -z "$OLD_CWD" ]; then
    echo "From: (initial directory)"
else
    echo "From: $OLD_CWD"
fi
echo "To:   $NEW_CWD"
echo ""

# 1. 检查新目录的项目类型
echo "🔍 Analyzing new directory..."

# 检查是否是 Git 仓库
if [ -d "$NEW_CWD/.git" ]; then
    echo "   ✓ Git repository detected"

    # 尝试获取当前分支
    if command -v git &> /dev/null; then
        cd "$NEW_CWD" 2>/dev/null
        BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        echo "   • Current branch: $BRANCH"
    fi
fi

# 检查项目类型
PROJECT_MARKERS=()
[ -f "$NEW_CWD/package.json" ] && PROJECT_MARKERS+=("Node.js")
[ -f "$NEW_CWD/requirements.txt" ] && PROJECT_MARKERS+=("Python")
[ -f "$NEW_CWD/go.mod" ] && PROJECT_MARKERS+=("Go")
[ -f "$NEW_CWD/Cargo.toml" ] && PROJECT_MARKERS+=("Rust")
[ -f "$NEW_CWD/pom.xml" ] && PROJECT_MARKERS+=("Java/Maven")
[ -f "$NEW_CWD/build.gradle" ] && PROJECT_MARKERS+=("Java/Gradle")

if [ ${#PROJECT_MARKERS[@]} -gt 0 ]; then
    echo "   ✓ Project type: ${PROJECT_MARKERS[*]}"
fi

# 检查是否有 Claude 配置
CLAUDE_FILES=(".claude/CLAUDE.md" "CLAUDE.md" ".claude.json")
for claude_file in "${CLAUDE_FILES[@]}"; do
    if [ -f "$NEW_CWD/$claude_file" ]; then
        echo "   ✓ Claude config: $claude_file"
        break
    fi
done

echo ""

# 2. 检查任务配置
TASK_CONFIG="$NEW_CWD/.task-config.json"
if [ -f "$TASK_CONFIG" ]; then
    echo "⚙️ Task Configuration Found:"
    cat "$TASK_CONFIG" | jq '.' 2>/dev/null || cat "$TASK_CONFIG"
    echo ""
fi

# 3. 检查是否有与当前项目相关的任务
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/fast-task-channel/data}"
TASK_FILE="$PLUGIN_DATA/current-task.json"

if [ -f "$TASK_FILE" ]; then
    TASK_WORKDIR=$(cat "$TASK_FILE" | jq -r '.workdir // ""')

    if [ "$TASK_WORKDIR" = "$NEW_CWD" ]; then
        echo "📌 Active Task for This Directory:"
        TASK_TITLE=$(cat "$TASK_FILE" | jq -r '.title // "Untitled"')
        TASK_STATUS=$(cat "$TASK_FILE" | jq -r '.status // "unknown"')
        echo "   • $TASK_TITLE ($TASK_STATUS)"
        echo ""
    fi
fi

# 4. 检查目录权限
if [ -w "$NEW_CWD" ]; then
    echo "✓ Directory is writable"
else
    echo "⚠️ Warning: Directory is not writable"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Context updated for new directory"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
