#!/bin/bash
# Hook Script for SessionEnd
# 保存会话状态和清理资源

set -e

# 读取 Hook 输入
INPUT=$(cat)

# 提取关键信息
DURATION_MS=$(echo "$INPUT" | jq -r '.duration_ms // 0')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

# 插件数据目录
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/fast-task-channel/data}"
mkdir -p "$PLUGIN_DATA"

# 计算会话时长
DURATION_SECONDS=$((DURATION_MS / 1000))
DURATION_MINUTES=$((DURATION_SECONDS / 60))

if [ $DURATION_MINUTES -gt 0 ]; then
    DURATION_TEXT="${DURATION_MINUTES}m $((DURATION_SECONDS % 60))s"
else
    DURATION_TEXT="${DURATION_SECONDS}s"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "👋 ClaudeGroup Plugin - Session Ending"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏱️ Session Duration: $DURATION_TEXT"
echo ""

# 1. 保存当前任务状态（如果有）
TASK_FILE="$PLUGIN_DATA/current-task.json"
TASK_BACKUP="$PLUGIN_DATA/task-backup-$(date +%Y%m%d-%H%M%S).json"

if [ -f "$TASK_FILE" ]; then
    echo "💾 Saving task state..."

    # 复制当前任务到备份
    cp "$TASK_FILE" "$TASK_BACKUP"

    TASK_ID=$(cat "$TASK_FILE" | jq -r '.task_id // "unknown"')
    TASK_STATUS=$(cat "$TASK_FILE" | jq -r '.status // "unknown"')

    echo "   • Task ID: $TASK_ID"
    echo "   • Status: $TASK_STATUS"
    echo "   • Backup: $TASK_BACKUP"
    echo ""
fi

# 2. 记录会话日志
SESSION_LOG="$PLUGIN_DATA/session.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session ended - Duration: ${DURATION_TEXT} - CWD: ${CWD}" >> "$SESSION_LOG"

# 统计会话次数
SESSION_COUNT=$(wc -l < "$SESSION_LOG" 2>/dev/null || echo "1")
echo "📊 Session Statistics:"
echo "   • Total sessions: $SESSION_COUNT"
echo "   • Log file: $SESSION_LOG"
echo ""

# 3. 清理临时文件
TEMP_DIR="$PLUGIN_DATA/temp"
if [ -d "$TEMP_DIR" ]; then
    TEMP_FILES=$(find "$TEMP_DIR" -type f -mtime +1 2>/dev/null | wc -l)
    if [ "$TEMP_FILES" -gt 0 ]; then
        echo "🧹 Cleaning old temp files..."
        find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null
        echo "   • Removed: $TEMP_FILES files"
        echo ""
    fi
fi

# 4. 生成会话摘要
SUMMARY_FILE="$PLUGIN_DATA/last-session-summary.txt"
cat > "$SUMMARY_FILE" <<EOF
ClaudeGroup Session Summary
===========================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Duration: ${DURATION_TEXT}
Working Directory: ${CWD}

Current Task:
$(if [ -f "$TASK_FILE" ]; then cat "$TASK_FILE"; else echo "No active task"; fi)

EOF

echo "📝 Session Summary:"
echo "   • Saved to: $SUMMARY_FILE"
echo ""

# 5. 显示下次启动提示
if [ -f "$TASK_FILE" ]; then
    TASK_TITLE=$(cat "$TASK_FILE" | jq -r '.title // "Untitled Task"')
    echo "📌 Next Session:"
    echo "   • Resume task: $TASK_TITLE"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Session state saved successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
