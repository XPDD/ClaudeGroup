#!/bin/bash
# Hook Script for SessionStart
# 加载项目上下文和配置信息

set -e

# 读取 Hook 输入
INPUT=$(cat)

# 提取关键信息
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
GIT_ROOT=$(echo "$INPUT" | jq -r '.git.root // ""')
GIT_BRANCH=$(echo "$INPUT" | jq -r '.git.branch // ""')
PLATFORM=$(echo "$INPUT" | jq -r '.platform // "unknown"')

# 插件数据目录
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/fast-task-channel/data}"

# 创建数据目录
mkdir -p "$PLUGIN_DATA"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 ClaudeGroup Plugin - Session Started"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 显示工作目录信息
echo "📂 Working Directory:"
echo "   • Path: $CWD"
if [ -n "$GIT_ROOT" ]; then
    echo "   • Git Root: $GIT_ROOT"
    echo "   • Branch: $GIT_BRANCH"
fi
echo ""

# 2. 检查项目配置文件
CONFIG_FILES=(".task-config.json" "claude-task.json" ".claude/CLAUDE.md")
for config_file in "${CONFIG_FILES[@]}"; do
    config_path="$CWD/$config_file"
    if [ -f "$config_path" ]; then
        echo "✓ Found config: $config_file"
        # 显示配置内容（如果文件不太大）
        if [ $(stat -f%z "$config_path" 2>/dev/null || stat -c%s "$config_path" 2>/dev/null) -lt 2048 ]; then
            cat "$config_path" | jq '.' 2>/dev/null || cat "$config_path"
        fi
        echo ""
    fi
done

# 3. 检查是否有未完成的任务
TASK_FILE="$PLUGIN_DATA/current-task.json"
if [ -f "$TASK_FILE" ]; then
    echo "⏳ Pending Task Found:"
    echo ""

    TASK_ID=$(cat "$TASK_FILE" | jq -r '.task_id // "unknown"')
    TASK_TITLE=$(cat "$TASK_FILE" | jq -r '.title // "Untitled"')
    TASK_STATUS=$(cat "$TASK_FILE" | jq -r '.status // "pending"')

    echo "   ID: $TASK_ID"
    echo "   Title: $TASK_TITLE"
    echo "   Status: $TASK_STATUS"
    echo ""

    # 如果任务状态是 in_progress，显示更多信息
    if [ "$TASK_STATUS" = "in_progress" ]; then
        TASK_DESC=$(cat "$TASK_FILE" | jq -r '.description // ""')
        if [ -n "$TASK_DESC" ]; then
            echo "   Description: $TASK_DESC"
        fi
    fi
    echo ""
fi

# 4. 检查 MCP 服务器连接
MCP_PORT="${USER_CONFIG_SERVER_PORT:-8080}"
echo "🔌 MCP Server:"
echo "   • Port: $MCP_PORT"
echo "   • Status: Checking..."

# 简单的端口检查（不依赖额外工具）
if command -v nc &> /dev/null; then
    if nc -z localhost "$MCP_PORT" 2>/dev/null; then
        echo "   • Connected ✓"
    else
        echo "   • Not running ⚠️"
    fi
else
    echo "   • Status: Unknown (install netcat for checks)"
fi
echo ""

# 5. 显示系统信息
echo "💻 System:"
echo "   • Platform: $PLATFORM"
echo "   • Shell: $SHELL"
echo "   • Plugin Data: $PLUGIN_DATA"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Context loaded successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
