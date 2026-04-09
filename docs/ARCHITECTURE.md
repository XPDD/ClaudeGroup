# Fast Task Channel Plugin - 架构设计文档

**文档版本**: 2.0
**更新日期**: 2025-04-09
**更新内容**: 新增详细的 Hook 设计说明（第 4 节）

## 1. 概述

### 1.1 目标

为 Claude Code 提供任务通道和执行控制能力:
- 通过 HTTP Webhook 接收任务
- 支持同步/异步审批机制
- 提供任务执行过程控制
- 任务完成后通知外部平台

### 1.2 核心价值

- **任务下发自动化**: 不限于对话输入,支持任何系统通过 Webhook 发送任务
- **执行过程可控**: 通过 Hook 进行审批、检查点验证、质量门禁
- **长时间审批支持**: 异步审批机制,支持几小时到几天的审批流程
- **平台集成**: 任务完成后自动通知 GitHub、Jira 等平台

## 2. 系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Channel MCP Server                            │
│                  (TypeScript + Express)                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Webhook 接收层                                            │ │
│  │  • POST /webhook - 接收任务                                │ │
│  │  • POST /approval/:id/approve - 审批回调                   │ │
│  │  • GET /health - 健康检查                                  │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Hook 处理层                                               │ │
│  │  • POST /hooks/pre-tool-use - 工具执行前审批               │ │
│  │  • POST /hooks/task-created - 子任务创建通知               │ │
│  │  • POST /hooks/task-completed - 任务完成验证               │ │
│  │  • POST /hooks/post-tool-use - 工具执行后处理              │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  业务逻辑层                                               │ │
│  │  • 风险评估 (Risk Assessment)                              │ │
│  │  • 审批管理 (Approval Store)                               │ │
│  │  • 平台通知 (Platform Notifier)                            │ │
│  │  • 验证器 (Validators)                                     │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  MCP Transport Layer                                       │ │
│  │  • stdio communication with Claude Code                    │ │
│  │  • Channel notifications                                   │ │
│  │  • Tool calls                                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
           │                                   │
           │ MCP stdio                         │ HTTP/HTTPS
           ▼                                   ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│      Claude Code        │     │      外部系统                    │
│  • 接收任务              │     │  • 任务创建系统                  │
│  • 执行任务              │     │  • 审批系统(钉钉/企微/OA)        │
│  • Hook 触发             │     │  • GitHub/Jira/自建平台         │
└─────────────────────────┘     └─────────────────────────────────┘
```

### 2.2 数据流向

#### 任务下发流程

```
外部系统 → HTTP POST /webhook
           ↓
    验证请求格式
           ↓
    构建 Channel 消息
           ↓
    MCP notification (channel 事件)
           ↓
    Claude Code 接收并执行
```

#### 同步审批流程

```
Claude 执行工具
      ↓
PreToolUse Hook 触发
      ↓
HTTP POST /hooks/pre-tool-use
      ↓
风险评估 → 低/中风险
      ↓
立即返回 allow/deny
      ↓
Claude 继续/停止
```

#### 异步审批流程

```
Claude 执行工具
      ↓
PreToolUse Hook 触发
      ↓
HTTP POST /hooks/pre-tool-use
      ↓
风险评估 → 高风险
      ↓
创建审批记录
      ↓
发送审批通知到审批系统
      ↓
立即返回 deny + pending_approval
      ↓
Claude 暂停
      ↓
[几小时后] 人工审批通过
      ↓
审批系统回调 POST /approval/:id/approve
      ↓
MCP notification (channel 事件)
      ↓
Claude 收到通知,重新执行操作
```

#### 任务完成流程

```
Claude 完成任务
      ↓
TaskCompleted Hook 触发
      ↓
HTTP POST /hooks/task-completed
      ↓
验证任务结果
      ↓
通知外部平台 (GitHub/Jira/自建平台)
      ↓
返回 allow/deny
      ↓
Claude 标记任务完成
```

## 3. 核心模块设计

### 3.1 Webhook 模块

**文件**: `channel-server/src/webhook.ts`

**职责**:
- 接收 HTTP POST 请求
- 验证请求格式
- 构建 Channel 消息
- 发送 MCP Channel 事件

**接口**:
```typescript
interface WebhookRequest {
  task_id: string;
  title: string;
  description: string;
  priority?: 'low' | 'medium' | 'high' | 'critical';
  metadata?: Record<string, any>;
  config?: {
    require_approval?: boolean;
    checkpoints?: string[];
  };
}
```

### 3.2 Hook 处理器模块

**目录**: `channel-server/src/handlers/`

#### 3.2.1 PreToolUse Handler

**文件**: `handlers/pre-tool-use.ts`

**职责**:
- 评估操作风险等级
- 根据风险等级决定审批策略
- 处理同步/异步审批
- 管理审批记录

**风险评估**:
```typescript
function assessRisk(toolName: string, toolInput: any): RiskLevel {
  // low: 低风险操作(Read, Grep 等)
  // medium: 中等风险(普通文件编辑)
  // high: 高风险(rm -rf, 生产环境部署等)
}
```

**审批策略**:
- **低风险**: 自动允许
- **中等风险**: 同步审批(可以快速响应)
- **高风险**: 异步审批(需要人工审批)

#### 3.2.2 TaskCreated Handler

**文件**: `handlers/task-created.ts`

**职责**:
- 记录子任务创建
- 通知外部系统
- 可选:创建额外的子任务

#### 3.2.3 TaskCompleted Handler

**文件**: `handlers/task-completed.ts`

**职责**:
- 验证任务是否可以完成
- 通知外部平台
- 返回 allow/deny 决定

**验证逻辑**:
- 检查执行结果
- 验证所有检查点是否通过
- 确认代码质量

**平台通知**:
- GitHub: 更新 Issue 状态/评论
- Jira: 更新任务状态
- 自建平台: 通用 Webhook 回调

#### 3.2.4 PostToolUse Handler

**文件**: `handlers/post-tool-use.ts`

**职责**:
- 检查点验证
- 进度通知
- 触发下一步操作

### 3.3 审批管理模块

**TODO**: 需要实现

**职责**:
- 保存待审批操作
- 管理审批状态
- 提供审批查询接口

**存储方案**:
- 方案 1: 内存存储(简单,但重启后丢失)
- 方案 2: 文件存储(持久化)
- 方案 3: 数据库存储(生产环境推荐)

### 3.4 平台通知模块

**TODO**: 需要实现

**职责**:
- 通知 GitHub
- 通知 Jira
- 通用 Webhook 回调

## 4. Hook 设计

### 4.1 Hook 设计概述

根据 PRD 的业务需求，本系统使用以下 Hook 事件来实现任务执行的全生命周期控制：

| Hook 事件 | 业务用途 | 触发时机 | 响应类型 |
|----------|---------|---------|---------|
| **SessionStart** | 加载项目上下文 | 会话启动 | 无（仅初始化） |
| **PreToolUse** | 审批机制 | 工具执行前 | allow/deny/ask/pending_approval |
| **PostToolUse** | 检查点验证 | 工具执行成功 | 无（仅记录） |
| **TaskCreated** | 子任务通知 | 创建任务时 | 无（仅记录） |
| **TaskCompleted** | 完成验证与平台通知 | 任务完成时 | allow/deny |
| **SessionEnd** | 保存状态 | 会话结束 | 无（仅清理） |

### 4.2 SessionStart Hook

#### 业务需求
- 加载项目相关的上下文信息
- 初始化任务执行环境
- 检查外部服务连接

#### 触发时机
Claude Code 会话启动时

#### 输入 Schema
```json
{
  "cwd": "/path/to/project",
  "git": {
    "branch": "main",
    "root": "/path/to/git/root"
  },
  "platform": "darwin",
  "env": {
    "CLAUDE_SESSION_ID": "uuid"
  }
}
```

#### 处理逻辑
1. 检查项目根目录是否存在 `CLAUDE.md` 文件
2. 读取项目配置文件（如 `.task-config.json`）
3. 初始化与 MCP 服务器的连接
4. 加载任务上下文（如果存在未完成任务）

#### 配置示例
```json
{
  "SessionStart": [{
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/load-context.sh"
    }]
  }]
}
```

#### 脚本实现
**文件**: `fast-task-claude-plugin/scripts/load-context.sh`

```bash
#!/bin/bash
# 加载项目上下文

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
GIT_ROOT=$(echo "$INPUT" | jq -r '.git.root')

# 1. 检查项目配置
if [ -f "$GIT_ROOT/.task-config.json" ]; then
  echo "✓ 检测到项目配置文件"
  cat "$GIT_ROOT/.task-config.json"
fi

# 2. 检查是否有未完成的任务
TASK_FILE="${CLAUDE_PLUGIN_DATA}/current-task.json"
if [ -f "$TASK_FILE" ]; then
  echo "⏳ 检测到未完成的任务"
  cat "$TASK_FILE" | jq -r '.task_description'
fi

# 3. 初始化 MCP 服务器连接
echo "正在连接到任务服务器..."

exit 0
```

### 4.3 PreToolUse Hook

#### 业务需求
- 实现审批机制（同步/异步）
- 根据操作风险等级决定审批策略
- 支持长时间异步审批流程

#### 触发时机
执行工具（Bash、Write、Edit）之前

#### 输入 Schema
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "rm -rf node_modules"
  },
  "permissionMode": "auto"
}
```

#### 风险评估策略

| 风险等级 | 操作示例 | 审批方式 |
|---------|---------|---------|
| **低风险** | Read, Grep, 查看文件 | 自动允许 |
| **中等风险** | 普通文件编辑 | 同步审批（<30秒） |
| **高风险** | rm -rf, 生产部署 | 异步审批 |

#### 响应类型

**1. allow** - 允许执行
```json
{
  "decision": "allow",
  "reason": "操作已审批通过"
}
```

**2. deny** - 拒绝执行（最终拒绝）
```json
{
  "decision": "deny",
  "reason": "该操作被安全策略禁止"
}
```

**3. ask** - 询问用户
```json
{
  "decision": "ask",
  "reason": "请确认是否执行此操作"
}
```

**4. pending_approval** - 异步审批（关键机制）
```json
{
  "decision": "deny",
  "reason": "操作需要人工审批，审批单号: approval-123",
  "approval_id": "approval-123",
  "pending_approval": true
}
```

#### 配置示例
```json
{
  "PreToolUse": [{
    "matcher": "Bash|Write|Edit",
    "hooks": [{
      "type": "http",
      "url": "http://localhost:8080/hooks/pre-tool-use",
      "timeout": 5000
    }]
  }]
}
```

#### 异步审批流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Claude 尝试执行敏感操作                                    │
└─────────────────────────────────────────────────────────────┘
Claude: 执行 rm -rf node_modules
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. PreToolUse Hook 触发                                      │
└─────────────────────────────────────────────────────────────┘
Hook → HTTP POST /hooks/pre-tool-use
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 服务器创建审批（立即返回）                                 │
└─────────────────────────────────────────────────────────────┘
- 创建审批记录 (approval-123)
- 发送通知到审批系统（钉钉/企微）
- 立即返回 deny + pending_approval
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Claude 收到 deny，操作被阻止                               │
└─────────────────────────────────────────────────────────────┘
系统消息: "⏳ 操作已提交审批，审批单号: approval-123"
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. [几小时后] 人工审批通过                                    │
└─────────────────────────────────────────────────────────────┘
审批系统 → POST /approval/approval-123/approve
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. 服务器通过 Channel 通知 Claude                            │
└─────────────────────────────────────────────────────────────┘
Channel 消息: "✅ 审批通过，请继续执行: rm -rf node_modules"
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Claude 收到通知，重新执行操作                              │
└─────────────────────────────────────────────────────────────┘
Claude: 执行 rm -rf node_modules
```

### 4.4 PostToolUse Hook

#### 业务需求
- 验证工具执行结果
- 检查点验证（test、lint、security_scan）
- 进度通知
- 触发后续操作

#### 触发时机
工具执行成功后

#### 输入 Schema
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "npm test"
  },
  "toolResult": {
    "exitCode": 0,
    "stdout": "Tests passed",
    "stderr": ""
  },
  "duration_ms": 5000
}
```

#### 处理逻辑
1. 记录工具执行结果
2. 检查是否是检查点操作（test/lint/security_scan）
3. 如果是检查点，验证结果是否通过
4. 发送进度通知到外部系统

#### 配置示例
```json
{
  "PostToolUse": [{
    "matcher": "Bash|Write|Edit",
    "hooks": [{
      "type": "http",
      "url": "http://localhost:8080/hooks/post-tool-use"
    }]
  }]
}
```

### 4.5 TaskCreated Hook

#### 业务需求
- 通知外部系统子任务已创建
- 记录任务层级关系
- 可选：动态创建额外子任务

#### 触发时机
Claude 创建新任务时

#### 输入 Schema
```json
{
  "taskId": "task-456",
  "subject": "分析崩溃日志",
  "description": "从 Crashlytics 获取并分析崩溃日志",
  "status": "pending"
}
```

#### 处理逻辑
1. 记录任务创建事件
2. 建立与主任务的关联
3. 通知外部系统任务状态更新
4. 可选：返回额外的子任务建议

#### 配置示例
```json
{
  "TaskCreated": [{
    "hooks": [{
      "type": "http",
      "url": "http://localhost:8080/hooks/task-created"
    }]
  }]
}
```

### 4.6 TaskCompleted Hook

#### 业务需求
- 验证任务完成条件
- 通知外部平台（GitHub、Jira、自建平台）
- 返回 allow/deny 决定

#### 触发时机
Claude 尝试标记任务为完成时

#### 输入 Schema
```json
{
  "taskId": "task-123",
  "subject": "修复登录页面崩溃问题",
  "status": "completed",
  "result": {
    "files_changed": ["src/LoginView.tsx"],
    "tests_passed": true,
    "commit": "abc123",
    "pr_url": "https://github.com/repo/pull/456"
  }
}
```

#### 验证检查项

| 检查项 | 说明 | 必需 |
|-------|------|------|
| 执行结果 | 任务是否成功完成 | ✅ |
| 检查点 | 配置的检查点是否全部通过 | ✅ |
| 代码质量 | 是否通过代码审查 | ✅ |
| 测试覆盖 | 是否有足够的测试 | 可选 |

#### 响应类型

**1. allow** - 允许完成任务
```json
{
  "decision": "allow",
  "reason": "任务已完成，已通知外部平台"
}
```

**2. deny** - 拒绝完成（需要继续工作）
```json
{
  "decision": "deny",
  "reason": "检查点未通过：测试失败，请修复后重试",
  "continue": false
}
```

#### 平台通知

**GitHub**:
```typescript
await octokit.issues.createComment({
  owner: 'owner',
  repo: 'repo',
  issue_number: 123,
  body: `✅ 任务完成\n\n${result.summary}\n\nPR: ${result.pr_url}`
})
```

**Jira**:
```typescript
await jira.updateIssue({
  issueId: 'TASK-123',
  status: 'Done',
  comment: `任务完成: ${result.summary}`
})
```

**自建平台**:
```typescript
await webhook.post(config.callback_url, {
  task_id: taskId,
  status: 'completed',
  result: result
})
```

#### 配置示例
```json
{
  "TaskCompleted": [{
    "hooks": [{
      "type": "http",
      "url": "http://localhost:8080/hooks/task-completed",
      "timeout": 10000
    }]
  }]
}
```

### 4.7 SessionEnd Hook

#### 业务需求
- 清理临时文件
- 保存会话状态
- 关闭外部连接

#### 触发时机
Claude Code 会话结束时

#### 输入 Schema
```json
{
  "duration_ms": 3600000,
  "cwd": "/path/to/project"
}
```

#### 处理逻辑
1. 保存当前任务状态到 `${CLAUDE_PLUGIN_DATA}/current-task.json`
2. 清理临时文件
3. 关闭 MCP 连接
4. 发送会话结束通知

#### 配置示例
```json
{
  "SessionEnd": [{
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/save-state.sh"
    }]
  }]
}
```

#### 脚本实现
**文件**: `fast-task-claude-plugin/scripts/save-state.sh`

```bash
#!/bin/bash
# 保存会话状态

INPUT=$(cat)
DURATION=$(echo "$INPUT" | jq -r '.duration_ms')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# 1. 保存任务状态
TASK_FILE="${CLAUDE_PLUGIN_DATA}/current-task.json"
if [ -f "$TASK_FILE" ]; then
  echo "保存任务状态..."
  cp "$TASK_FILE" "${TASK_FILE}.backup"
fi

# 2. 记录会话日志
echo "[$(date)] Session ended, duration: ${DURATION}ms" >> "${CLAUDE_PLUGIN_DATA}/session.log"

exit 0
```

### 4.8 Hook 配置文件结构

**文件**: `fast-task-claude-plugin/hooks/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/load-context.sh"
      }]
    }],

    "PreToolUse": [{
      "matcher": "Bash|Write|Edit",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:8080/hooks/pre-tool-use",
        "timeout": 5000,
        "headers": {
          "Authorization": "Bearer ${user_config.webhook_token}"
        }
      }]
    }],

    "PostToolUse": [{
      "matcher": "Bash|Write|Edit",
      "hooks": [{
        "type": "http",
        "url": "http://localhost:8080/hooks/post-tool-use"
      }]
    }],

    "TaskCreated": [{
      "hooks": [{
        "type": "http",
        "url": "http://localhost:8080/hooks/task-created"
      }]
    }],

    "TaskCompleted": [{
      "hooks": [{
        "type": "http",
        "url": "http://localhost:8080/hooks/task-completed",
        "timeout": 10000
      }]
    }],

    "SessionEnd": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/save-state.sh"
      }]
    }]
  }
}
```

### 4.9 Hook 脚本文件组织

```
fast-task-claude-plugin/
├── hooks/
│   └── hooks.json                 # Hook 配置
└── scripts/
    ├── load-context.sh            # SessionStart 处理
    ├── save-state.sh              # SessionEnd 处理
    └── on-dir-change.sh           # CwdChanged 处理（可选）
```

## 5. 配置系统

### 5.1 用户配置

**plugin.json** 中的 `userConfig`:

```json
{
  "userConfig": {
    "webhook_port": {...},
    "webhook_token": {...},
    "github_token": {...},
    "jira_url": {...},
    "jira_token": {...}
  }
}
```

### 5.2 环境变量

配置会自动转换为环境变量:
- `WEBHOOK_PORT`
- `WEBHOOK_TOKEN`
- `GITHUB_TOKEN`
- `JIRA_URL`
- `JIRA_TOKEN`
- `PLUGIN_DATA`

### 5.3 插件变量

- `${CLAUDE_PLUGIN_ROOT}`: 插件安装目录
- `${CLAUDE_PLUGIN_DATA}`: 持久数据目录

## 6. 安全考虑

### 6.1 认证

- Webhook Token: 验证请求来源
- Bearer Token: HTTP 认证

### 6.2 授权

- 敏感操作需要审批
- 多级审批支持

### 6.3 门控

- 发送者白名单(可选)
- IP 白名单(可选)

## 7. 扩展性设计

### 7.1 平台扩展

添加新的平台通知:
1. 在 `platform/` 目录创建新文件
2. 实现通知接口
3. 在 `task-completed.ts` 中注册

### 7.2 审批策略扩展

添加新的审批策略:
1. 在 `pre-tool-use.ts` 中扩展风险评估函数
2. 添加新的审批处理逻辑

### 7.3 Hook 事件扩展

当前已实现的 Hook 事件已满足核心业务需求：

**核心 Hooks（已实现）**:
- ✅ SessionStart - 加载项目上下文
- ✅ PreToolUse - 审批机制（同步/异步）
- ✅ PostToolUse - 检查点验证
- ✅ TaskCreated - 子任务通知
- ✅ TaskCompleted - 完成验证与平台通知
- ✅ SessionEnd - 保存状态

**可选 Hooks（未来扩展）**:
- PostToolUseFailure - 错误处理和重试逻辑
- CwdChanged - 目录切换时的上下文更新
- Stop - 中断时的清理操作

如需添加新的 Hook 事件：
1. 在 `hooks/hooks.json` 中添加配置
2. 在 `fast-task-server` 中实现对应的处理逻辑
3. 更新架构文档

## 8. 部署方案

### 8.1 开发环境

```bash
# 本地运行
cd channel-server
npm install
npm run dev
```

### 8.2 生产环境

```bash
# 使用 PM2
pm2 start dist/index.js --name task-channel

# 使用 Docker
docker build -t task-channel .
docker run -p 8080:8080 task-channel
```

## 9. 监控和日志

### 9.1 日志

- 使用 `console.error` 输出到 stderr
- 日志级别: INFO, WARN, ERROR

### 9.2 监控

- 健康检查端点: `GET /health`
- TODO: 添加指标收集(Prometheus 等)

## 10. 测试策略

### 10.1 单元测试

- 测试风险评估逻辑
- 测试消息格式化
- 测试平台通知

### 10.2 集成测试

- 测试完整任务流程
- 测试审批流程
- 测试平台通知

### 10.3 端到端测试

- 测试从 Webhook 到任务完成
- 测试异步审批流程

## 11. 未来改进

### 11.1 短期改进

- [ ] 实现审批记录持久化
- [ ] 实现完整的平台通知(GitHub, Jira)
- [ ] 添加更多检查点验证
- [ ] 添加错误处理和重试机制

### 11.2 长期改进

- [ ] 支持分布式部署
- [ ] 支持任务优先级调度
- [ ] 支持任务队列管理
- [ ] 提供 Web UI 管理界面
- [ ] 支持多种审批系统集成

## 12. 参考资料

- [Claude Code Plugins Reference](https://code.claude.com/docs/zh-CN/plugins-reference)
- [Claude Code Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)
- [Claude Code Hooks Reference](https://code.claude.com/docs/zh-CN/hooks)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [PRD](./PRD.md)
- [HOOKS 说明](./HOOKS.md)
- [使用示例](./EXAMPLES.md)
