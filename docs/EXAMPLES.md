# 使用示例

本文档提供了 Fast Task Channel Plugin 的详细使用示例。

## 目录

- [快速开始](#快速开始)
- [发送任务](#发送任务)
- [审批流程](#审批流程)
- [平台集成](#平台集成)
- [高级用法](#高级用法)

## 快速开始

### 1. 安装插件

```bash
# 进入插件目录
cd /path/to/fast-task-channel

# 安装依赖
./scripts/install.sh

# 启动 Claude Code 并加载插件
claude --plugin-dir /path/to/fast-task-channel
```

### 2. 配置插件

Claude Code 会提示你输入配置:

```
请输入以下配置:
- webhook_port (默认 8080):
- webhook_token (可选):
- github_token (可选):
- jira_url (可选):
- jira_token (可选):
```

### 3. 验证安装

```bash
# 健康检查
curl http://127.0.0.1:8080/health

# 预期响应:
# {"status":"ok","server":"task-channel"}
```

## 发送任务

### 基础任务

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "task-001",
    "title": "修复登录 Bug",
    "description": "用户反馈无法登录,请分析并修复。",
    "priority": "high"
  }'
```

### 带元数据的任务

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "task-002",
    "title": "CI 构建失败",
    "description": "主分支构建失败,请分析原因并修复。",
    "priority": "critical",
    "metadata": {
      "build_url": "https://jenkins.example.com/job/main/1234",
      "branch": "main",
      "commit": "abc123def",
      "failed_stage": "test"
    }
  }'
```

### 需要审批的任务

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "task-003",
    "title": "部署到生产环境",
    "description": "将应用部署到生产环境",
    "priority": "critical",
    "config": {
      "require_approval": true,
      "checkpoints": ["test", "security_scan", "code_review"]
    }
  }'
```

### 带 Webhook 认证的任务

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token" \
  -d '{
    "task_id": "task-004",
    "title": "数据库迁移",
    "description": "执行数据库 schema 迁移"
  }'
```

## 审批流程

### 同步审批(自动/快速审批)

对于低风险操作,服务器会自动允许:

```typescript
// 低风险操作示例
- Read: 读取文件
- Grep: 搜索代码
- Glob: 查找文件

// 服务器响应
{
  "decision": "allow",
  "reason": "低风险操作,自动允许"
}
```

### 异步审批(长时间人工审批)

#### 1. Claude 尝试执行高风险操作

```typescript
// Claude 执行: rm -rf node_modules
// Hook 触发,服务器评估为高风险
```

#### 2. 服务器创建审批并返回 deny

```json
{
  "decision": "deny",
  "reason": "⏳ 操作需要人工审批\n\n审批单号: approval-12345\n审批通过后,我将自动继续执行操作",
  "approval_id": "approval-12345",
  "pending_approval": true
}
```

#### 3. 人工审批

审批人会收到通知(钉钉/企微/OA):

```
标题: Claude Code 操作审批

操作详情:
- 工具: Bash
- 命令: rm -rf node_modules
- 会话: abc123
- 时间: 2025-04-09 12:00:00

请选择:
[同意] [拒绝]
```

#### 4. 审批通过后,服务器发送 Channel 通知

```typescript
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: '✅ 审批 approval-12345 已通过\n\n请继续执行: bash: rm -rf node_modules',
    meta: {
      type: 'approval_result',
      approval_id: 'approval-12345',
      decision: 'allow',
      original_tool: 'Bash',
      original_input: '{"command":"rm -rf node_modules"}'
    }
  }
});
```

#### 5. Claude 收到通知,自动继续执行

Claude 会识别这是审批结果通知,并重新执行被拒绝的操作。

## 平台集成

### GitHub 集成

#### 1. 配置 GitHub Token

```bash
# 在 Claude Code 配置中添加
{
  "github_token": "ghp_xxxxxxxxxxxxxxxxxxxx"
}
```

#### 2. 从 GitHub Issue 创建任务

```typescript
// 示例: 通过 GitHub Action 触发
// .github/workflows/assign-to-claude.yml

name: Assign to Claude
on:
  issues:
    types: [labeled]

jobs:
  assign:
    if: github.event.label.name == 'assign-to-claude'
    runs-on: ubuntu-latest
    steps:
      - name: Send to Claude
        run: |
          curl -X POST http://your-server:8080/webhook \
            -H "Content-Type: application/json" \
            -d "{
              \"task_id\": \"github-${{ github.event.issue.number }}\",
              \"title\": \"${{ github.event.issue.title }}\",
              \"description\": \"${{ github.event.issue.body }}\",
              \"metadata\": {
                \"source\": \"github\",
                \"issue_url\": \"${{ github.event.issue.html_url }}\",
                \"callback_url\": \"${{ github.event.issue.comments_url }}\"
              }
            }"
```

#### 3. 任务完成后更新 GitHub Issue

```typescript
// TaskCompleted Hook 处理
async function notifyGitHub(hookData) {
  await octokit.issues.createComment({
    owner: 'owner',
    repo: 'repo',
    issue_number: extractIssueNumber(hookData.task_id),
    body: `✅ 任务完成\n\n${hookData.execution_result.summary}`
  });
}
```

### Jira 集成

#### 1. 配置 Jira

```bash
{
  "jira_url": "https://your-domain.atlassian.net",
  "jira_token": "your-email:api-token"
}
```

#### 2. 从 Jira 创建任务

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "jira-PROJ-123",
    "title": "实现用户认证功能",
    "description": "As a user, I want to login...",
    "metadata": {
      "source": "jira",
      "issue_key": "PROJ-123",
      "assignee": "john.doe"
    }
  }'
```

#### 3. 任务完成后更新 Jira 状态

```typescript
// TaskCompleted Hook 处理
await jira.updateIssue({
  issueId: 'PROJ-123',
  status: 'Done',
  comment: `任务完成: ${result.summary}`
});
```

### 自建平台集成

```bash
curl -X POST http://127.0.0.1:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "custom-task-001",
    "title": "数据处理任务",
    "description": "处理用户数据并生成报告",
    "metadata": {
      "callback_url": "https://your-platform.com/api/callback"
    }
  }'
```

任务完成后:

```typescript
// TaskCompleted Hook 处理
await axios.post(metadata.callback_url, {
  task_id: hookData.task_id,
  status: 'completed',
  result: hookData.execution_result
});
```

## 高级用法

### 批量发送任务

```bash
#!/bin/bash
# send-tasks.sh

tasks=(
  "task-001|修复登录 Bug|高优先级"
  "task-002|更新文档|中优先级"
  "task-003|性能优化|低优先级"
)

for task in "${tasks[@]}"; do
  IFS='|' read -r id title priority <<< "$task"

  curl -X POST http://127.0.0.1:8080/webhook \
    -H "Content-Type: application/json" \
    -d "{
      \"task_id\": \"$id\",
      \"title\": \"$title\",
      \"description\": \"请处理此任务\",
      \"priority\": \"$priority\"
    }"

  echo "已发送任务: $title"
done
```

### 从 Python 发送任务

```python
import requests
import json

def send_task(title, description, priority="medium", metadata=None):
    url = "http://127.0.0.1:8080/webhook"
    headers = {"Content-Type": "application/json"}

    task_id = f"task-{int(time.time())}"

    payload = {
        "task_id": task_id,
        "title": title,
        "description": description,
        "priority": priority
    }

    if metadata:
        payload["metadata"] = metadata

    response = requests.post(url, headers=headers, data=json.dumps(payload))
    return response.json()

# 使用示例
result = send_task(
    title="分析日志文件",
    description="请分析 /var/log/app.log 中的错误",
    priority="high",
    metadata={"log_path": "/var/log/app.log"}
)

print(result)
# {"status":"received","message":"Task sent to Claude Code","task_id":"task-12345"}
```

### 从 Node.js 发送任务

```javascript
const axios = require('axios');

async function sendTask({ title, description, priority = 'medium', metadata = {} }) {
  const url = 'http://127.0.0.1:8080/webhook';
  const taskId = `task-${Date.now()}`;

  const payload = {
    task_id: taskId,
    title,
    description,
    priority,
    metadata
  };

  try {
    const response = await axios.post(url, payload, {
      headers: { 'Content-Type': 'application/json' }
    });
    return response.data;
  } catch (error) {
    console.error('发送任务失败:', error);
    throw error;
  }
}

// 使用示例
sendTask({
  title: '代码重构',
  description: '重构用户模块代码,提高可维护性',
  priority: 'medium',
  metadata: { module: 'user' }
}).then(result => {
  console.log('任务已发送:', result);
});
```

## 故障排查

### 1. 服务器未启动

```bash
# 检查服务器是否运行
curl http://127.0.0.1:8080/health

# 如果失败,检查 Claude Code 日志
claude --debug
```

### 2. 任务未到达 Claude

```bash
# 检查 MCP 连接
# 在 Claude Code 中运行 /mcp

# 检查服务器日志
# 服务器日志输出到 stderr
```

### 3. 审批超时

```bash
# 检查审批系统是否正常
# 查看服务器日志中的审批记录

# 手动触发审批通过
curl -X POST http://127.0.0.1:8080/approval/approval-12345/approve \
  -H "Content-Type: application/json" \
  -d '{"decision": "approve"}'
```

## 最佳实践

1. **任务描述要清晰**: 详细描述任务目标和要求
2. **合理设置优先级**: 根据紧急程度设置 priority
3. **提供必要的上下文**: 通过 metadata 传递额外信息
4. **配置检查点**: 对重要任务设置 checkpoints
5. **使用 Webhook Token**: 生产环境务必配置认证
6. **监控审批状态**: 定期检查待审批任务
7. **处理超时**: 为长时间审批设置超时机制

## 更多资源

- [架构设计文档](./ARCHITECTURE.md)
- [产品需求文档](./PRD.md)
- [Claude Code Plugins Reference](https://code.claude.com/docs/zh-CN/plugins-reference)
- [Claude Code Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)
