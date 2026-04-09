# Claude Code 任务通道与执行控制系统 产品需求文档 (PRD)

**文档版本**: 3.1
**创建日期**: 2025-04-09
**最后更新**: 2025-04-09
**面向对象**: 产品团队、开发团队、设计团队

**版本历史**:
- **v3.1** (2025-04-09): 添加平台通知功能 - 任务完成后通知外部平台更新状态
- **v3.0** (2025-04-09): 明确 Channel 职责 - 任务下发与执行控制，不包含任务创建方式
- **v2.1** (2025-04-09): 修正核心理解 - Claude 只负责任务执行
- **v2.0** (2025-04-09): 添加异步审批机制（Deny + Channel 通知）
- **v1.0** (2025-04-09): 初始版本

---

## 📋 文档摘要

本文档定义了 **Claude Code 任务通道（Channel）与执行控制机制** 的产品需求。

### 核心功能

1. **任务下发（Channel，单向）**
   - 通过 HTTP Webhook 接收任务
   - 转换为 Channel 事件发送给 Claude Code
   - Claude Code 接收任务并开始执行

2. **执行过程控制（Hook，双向）**
   - Claude 执行任务时，通过 Hook 将审批、检查点等请求发送到 HTTP 服务器
   - 服务器返回决定（allow/deny/block），控制任务执行流程
   - 支持同步审批（快速响应）和异步审批（长时间人工审批）

### 范围说明

**本 PRD 包含**：
- Channel 服务器的设计与实现
- Hook 回调机制
- 审批流程（同步/异步）
- 检查点验证
- 任务执行监控

**本 PRD 不包含**：
- 任务创建方式（通过 CLI 工具、GitHub Issues 或其他方式）
- 任务管理系统
- 任务优先级调度
- 任务队列管理

**核心价值**:
- 提供可靠的任务下发通道
- 确保任务执行过程中的审批和监控
- 支持长时间人工审批场景
- 提供灵活的执行控制机制

---

## 🎯 产品概述

### 产品背景

当前 Claude Code 主要通过用户交互式对话来接收任务,存在以下痛点:
1. **任务下发方式单一**: 只能通过对话输入，无法自动化接收任务
2. **执行过程不可控**: Claude 执行任务时无法进行远程审批、质量检查等干预
3. **审批流程缺失**: 敏感操作需要审批，但缺乏集成审批系统的机制
4. **执行监控不足**: 缺乏对任务执行过程的监控和检查点验证
5. **长时间审批困难**: 人工审批可能需要几小时甚至几天，现有机制无法支持

### 产品愿景

构建一个开放、灵活的任务执行控制系统:
- **任务下发**: 通过 Channel 接收任务并发送给 Claude
- **执行控制**: 通过 Hook 进行审批、检查点验证、质量门禁
- **异步审批**: 支持长时间人工审批场景
- **执行监控**: 实时监控任务执行状态，及时发现问题
- **平台通知**: 任务完成后通知外部平台（GitHub、Jira、自建平台等）

---

## 🏗️ 核心架构

### 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                    Channel 服务器                                │
├─────────────────────────────────────────────────────────────────┤
│  • Webhook 接收端点（POST /webhook）                             │
│  • 转换为 <channel> 事件发送给 Claude                             │
│  • 处理 Hook 回调（审批、检查点、验证）                            │
│  • 管理审批状态和待审批操作                                        │
│  • 通过 Channel 发送异步通知（审批结果）                           │
│  • 任务完成后通知外部平台                                        │
└────────────┬──────────────────────┬────────────────────────────────┘
             │                      │
             │ MCP stdio              │ HTTP/HTTPS
             ▼                      ▼
┌─────────────────────────┐  ┌─────────────────────────────────┐
│      Claude Code        │  │      外部平台                    │
├─────────────────────────┤  ├─────────────────────────────────┤
│  • 接收任务              │  │  • GitHub Issues               │
│  • 执行任务              │  │  • Jira                        │
│  • Hook 触发             │  │  • 自建平台                    │
│  • 接收审批通知          │  │  • CLI 工具                    │
└─────────────────────────┘  └─────────────────────────────────┘
```

### 数据流向

#### 1. 任务下发（单向）
```
HTTP Webhook → Channel 服务器 → Channel 事件 → Claude Code
```
**说明**：任务来源不限（CLI 工具、GitHub Issues、其他系统），Channel 只负责转发

#### 2. 任务执行
```
Claude Code 接收任务 → 理解任务 → 执行操作
```

#### 3. 执行过程控制（双向）
```
Claude Code 执行任务
        ↓
Hook 触发（PreToolUse / PostToolUse / TaskCompleted）
        ↓
HTTP Hook → Channel 服务器
        ↓
服务器处理并返回决定
        ↓
Claude Code 根据决定继续/停止
```

#### 4. 异步审批通知
```
Hook 触发 → 服务器创建审批 → 立即返回 deny
        ↓
[几小时后] 人工审批通过
        ↓
服务器 → Channel 通知 → Claude Code 继续执行
```

#### 5. 平台通知（任务完成后）
```
Claude Code 任务完成
        ↓
TaskCompleted Hook → Channel 服务器
        ↓
服务器验证任务结果
        ↓
服务器通知外部平台（GitHub/Jira/自建平台）
        ↓
平台更新任务状态
```

### 🔑 关键概念：异步审批机制

**问题**：人工审批需要很长时间（几小时到几天），但 HTTP Hook 有超时限制（默认 10 分钟）

**解决方案**：Deny + Channel 异步通知

```
同步模式（快速审批）:
  Claude → Hook → 服务器 → 立即返回 allow/deny → Claude 继续/停止

异步模式（长时间审批）:
  Claude → Hook → 服务器 → 立即返回 deny + pending_approval → Claude 暂停
                                      ↓ 创建审批
                                      ↓ [几小时后] 人工审批通过
                                      ↓ 服务器 → Channel 通知 → Claude 继续
```

**核心要点**：
1. **Hook 不等待**：服务器收到 Hook 请求后，立即返回 deny（不等待审批）
2. **保存上下文**：服务器保存待审批的操作详情
3. **Channel 通知**：审批通过后，通过 Channel 发送新消息给 Claude
4. **Claude 继续**：Claude 收到 Channel 消息后，重新执行被拒绝的操作

**适用场景**：
- ✅ 生产环境部署（需要运维负责人审批）
- ✅ 数据库变更（需要 DBA 审批）
- ✅ 删除重要数据（需要多级审批）
- ✅ 发版上线（需要产品经理审批）
- ❌ 快速自动化（使用同步模式）

### 数据流向

#### 1. 任务下发（单向）

```
外部系统 → HTTP POST → Webhook 服务器
                                    ↓
                          MCP notification (channel 事件)
                                    ↓
                            Claude Code 创建任务
```

#### 2. 执行过程交互（双向）

```
Claude Code 执行任务
        ↓
Hook 触发（PreToolUse / TaskCreated / TaskCompleted 等）
        ↓
HTTP Hook 发送到服务器
        ↓
服务器处理并返回决定
        ↓
Claude Code 根据决定继续/停止
```

---

## 🎨 核心功能

### 1. HTTP Webhook 任务接收（Channel，单向）

**功能描述**: 通过 HTTP Webhook 接收任务并发送给 Claude Code

#### 1.1 Webhook 接收端点

**端点**: `POST /webhook`

**请求格式**:
```json
{
  "task_id": "task-123",
  "title": "主分支构建失败",
  "description": "构建 #1234 在 main 分支失败，单元测试出错\n\n请分析失败原因并修复。",
  "priority": "high",
  "metadata": {
    "build_url": "https://jenkins.example.com/job/main/1234",
    "branch": "main",
    "commit": "abc123"
  },
  "config": {
    "require_approval": true,  // 是否需要审批
    "checkpoints": ["test", "lint", "security_scan"]  // 检查点
  }
}
```

**响应**:
```json
{
  "status": "received",
  "message": "Task sent to Claude Code"
}
```

**说明**：
- `task_id`: 任务唯一标识（由任务创建方生成）
- `title`: 任务标题
- `description`: 任务描述（Claude 会读取这部分内容）
- `priority`: 任务优先级（low/medium/high/critical）
- `metadata`: 额外的元数据（作为 context 传递给 Claude）
- `config`: 执行配置（审批要求、检查点等）

#### 1.2 Channel 事件格式

Webhook 服务器将任务转换为 MCP Channel 事件发送给 Claude：

```xml
<channel task_id="task-123" priority="high">
主分支构建失败
构建 #1234 在 main 分支失败，单元测试出错

详细信息:
- 构建URL: https://jenkins.example.com/job/main/1234
- 分支: main
- 提交: abc123
- 失败阶段: test

请分析构建失败原因并修复问题。
</channel>
```

**Claude 接收并执行**:
Claude 直接读取 Channel 内容，理解任务要求，开始执行。

#### 1.3 任务执行流程

```
Claude 接收 Channel 事件
    ↓
理解任务内容
    ↓
制定执行计划
    ↓
开始执行（调用工具）
    ↓
[可选] Hook 触发（审批、检查点）
    ↓
完成任务
    ↓
[可选] 回调外部系统
```

### 2. HTTP Hook 回调机制（执行过程控制）

**功能描述**: Claude 执行任务时，通过 Hook 将请求发送到 HTTP 服务器，并根据返回结果决定是否继续

#### 2.1 Hook 触发点

| Hook 事件 | 触发时机 | 用途 | HTTP 回调 |
|-----------|---------|------|----------|
| **PreToolUse** | 工具执行前 | 审批权限 | 请求批准 → allow/deny |
| **TaskCreated** | Hook 创建子任务时 | 通知服务器子任务已创建 | 返回子任务列表 |
| **TaskCompleted** | 任务完成前 | 完成验证/关闭任务 | 验证是否可完成/拒绝完成 |
| **PostToolUse** | 工具执行成功后 | 检查点验证 | 通知进度/请求下一步 |
| **PostToolUseFailure** | 工具执行失败后 | 错误处理 | 请求错误处理指示 |

**说明**：
- Claude 不通过 Hook 创建主任务（主任务来自 Channel）
- Hook 可以在执行过程中创建子任务（TaskCreated）
- Hook 主要用于执行过程中的控制（审批、检查点、验证）

#### 2.2 HTTP Hook 配置

**Hook 配置示例**:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/pre-tool-use",
            "timeout": 30,
            "headers": {
              "Content-Type": "application/json",
              "Authorization": "Bearer ${WEBHOOK_TOKEN}"
            }
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/task-completed",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

#### 2.3 PreToolUse Hook - 远程审批

**场景**: Claude 执行敏感操作前需要外部审批

**Claude 发送的请求**:
```json
POST /hooks/pre-tool-use
{
  "session_id": "abc123",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf node_modules",
    "description": "删除 node_modules 目录"
  },
  "task_info": {
    "task_id": "task-456",
    "external_task_id": "external-task-123",
    "source": "jenkins"
  }
}
```

---

#### 2.3.1 同步审批（快速响应）

**适用场景**: 自动化审批或审批时间 < 30 秒

**HTTP 服务器立即返回决定**:

**方案 1: 允许执行**
```json
{
  "decision": "allow",
  "reason": "已审批通过"
}
```

**方案 2: 拒绝执行**
```json
{
  "decision": "deny",
  "reason": "该操作需要更高级别的审批"
}
```

**方案 3: 修改后执行**
```json
{
  "decision": "allow",
  "reason": "已修改命令为更安全的版本",
  "updatedInput": {
    "command": "rm -rf ./node_modules",
    "description": "删除 node_modules 目录（限当前目录）"
  }
}
```

**方案 4: 请求更多信息（转为 ask）**
```json
{
  "decision": "ask",
  "reason": "请确认是否真的要删除所有依赖"
}
```

---

#### 2.3.2 异步审批（长时间人工审批）

**适用场景**: 需要人工审批，审批时间可能很长（几小时到几天）

**问题**: HTTP Hook 有 timeout 限制（默认 600 秒），无法等待长时间审批

**解决方案**: Deny + Channel 通知继续

**完整流程**:

```
┌─────────────────────────────────────────────────────────────┐
│ 第 1 步: Claude 尝试执行操作                                 │
└─────────────────────────────────────────────────────────────┘
Claude: 我要执行 rm -rf node_modules
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 2 步: PreToolUse Hook 触发                               │
└─────────────────────────────────────────────────────────────┘
Hook → HTTP POST /hooks/pre-tool-use
{
  "tool_name": "Bash",
  "tool_input": {"command": "rm -rf node_modules"}
}
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 3 步: 服务器创建审批任务（立即返回 deny）                │
└─────────────────────────────────────────────────────────────┘
服务器:
  1. 创建审批记录（ID: approval-123）
  2. 发送通知到审批系统（钉钉/企微/OA）
  3. 立即返回 HTTP 响应

HTTP 200 OK:
{
  "decision": "deny",
  "reason": "操作需要人工审批，审批单号: approval-123",
  "approval_id": "approval-123",
  "pending_approval": true
}
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 4 步: Claude 收到 deny，操作被阻止                       │
└─────────────────────────────────────────────────────────────┘
Claude: 收到拒绝，操作未执行
系统消息: "操作需要人工审批，审批单号: approval-123"
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 5 步: 人工审批（可能几小时后）                           │
└─────────────────────────────────────────────────────────────┘
审批人:
  - 在钉钉/企微收到审批通知
  - 查看操作详情
  - 点击"同意"
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 6 步: 审批通过，服务器通过 Channel 通知 Claude          │
└─────────────────────────────────────────────────────────────┘
服务器 → MCP Channel:
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: '审批 approval-123 已通过，请继续执行: rm -rf node_modules',
    meta: {
      type: 'approval_result',
      approval_id: 'approval-123',
      decision: 'allow',
      original_command: 'rm -rf node_modules'
    }
  }
})
          ↓
┌─────────────────────────────────────────────────────────────┐
│ 第 7 步: Claude 收到 Channel 消息，重新执行操作             │
└─────────────────────────────────────────────────────────────┘
Claude: 收到审批通过通知，执行: rm -rf node_modules
```

**关键技术点**:

1. **Hook 立即返回**: 服务器不能等待审批，必须立即返回 deny
2. **保存操作上下文**: 服务器需要保存待审批的操作详情
3. **Channel 通知**: 审批通过后，通过 Channel 发送新消息给 Claude
4. **Claude 识别消息**: Claude 需要识别这是审批结果，重新执行操作

**HTTP 服务器代码示例**:

```typescript
// 审批记录存储
const pendingApprovals = new Map<string, {
  tool_name: string
  tool_input: any
  session_id: string
  created_at: Date
}>

// Hook 处理
app.post('/hooks/pre-tool-use', async (req) => {
  const { tool_name, tool_input, session_id } = req.body

  // 检查是否需要审批
  if (requiresApproval(tool_name, tool_input)) {
    // 创建审批记录
    const approvalId = generateId()

    pendingApprovals.set(approvalId, {
      tool_name,
      tool_input,
      session_id,
      created_at: new Date()
    })

    // 发送审批通知到钉钉/企微
    await sendApprovalNotification({
      approval_id: approvalId,
      operation: `${tool_name}: ${JSON.stringify(tool_input)}`,
      approve_url: `https://approval-system.example.com/approve/${approvalId}`
    })

    // 立即返回 deny（不等待审批）
    return {
      decision: 'deny',
      reason: `操作需要人工审批，审批单号: ${approvalId}`,
      approval_id: approvalId,
      pending_approval: true
    }
  }

  // 不需要审批，直接允许
  return { decision: 'allow' }
})

// 审批回调接口（来自审批系统）
app.post('/approval/:id/approve', async (req) => {
  const { id } = req.params
  const { decision } = req.body  // 'approve' | 'reject'

  // 获取审批记录
  const approval = pendingApprovals.get(id)
  if (!approval) {
    return { error: 'Approval not found' }
  }

  if (decision === 'approve') {
    // 审批通过，通过 Channel 通知 Claude
    await mcp.notification({
      method: 'notifications/claude/channel',
      params: {
        content: `审批 ${id} 已通过，请继续执行`,
        meta: {
          type: 'approval_result',
          approval_id: id,
          decision: 'allow',
          original_tool: approval.tool_name,
          original_input: approval.tool_input
        }
      }
    })
  }

  // 清理审批记录
  pendingApprovals.delete(id)

  return { success: true }
})
```

**Claude 的 Hook 脚本处理 deny**:

```bash
#!/bin/bash
# hooks/process-pre-tool-use-response.sh

INPUT=$(cat)
DECISION=$(echo "$INPUT" | jq -r '.decision')
REASON=$(echo "$INPUT" | jq -r '.reason')
PENDING=$(echo "$INPUT" | jq -r '.pending_approval // false')

if [ "$DECISION" = "deny" ] && [ "$PENDING" = "true" ]; then
  # 是待审批的拒绝，输出友好提示
  echo "⏳ 操作已提交审批，等待审批通过后自动继续执行"
  echo "审批信息: $REASON"
  echo ""
  echo "审批通过后，我会收到通知并自动继续执行操作"
fi

exit 0
```

**Claude 识别审批结果并继续执行**:

当 Claude 收到 Channel 消息时，UserPromptSubmit Hook 可以识别：

```bash
#!/bin/bash
# hooks/recognize-approval-result.sh

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt')

# 检查是否是审批结果通知
if echo "$PROMPT" | grep -q "审批.*已通过"; then
  # 提取原始操作
  ORIGINAL_COMMAND=$(echo "$PROMPT" | grep -oP "请继续执行: \K.*")

  echo "✅ 审批已通过，现在执行: $ORIGINAL_COMMAND"

  # 输出原始命令，让 Claude 继续执行
  # 这里 Claude 会识别并执行
fi

exit 0
```

**或者更直接的方式**：

Channel 消息直接包含可执行的指令：

```typescript
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: '/exec Bash rm -rf node_modules',
    meta: {
      type: 'approval_result',
      approval_id: approvalId
    }
  }
})
```

Claude 收到后会直接执行这个命令。

---

#### 2.3.3 同步 vs 异步审批对比

| 特性 | 同步审批 | 异步审批 |
|-----|---------|---------|
| **适用场景** | 自动审批、快速审批（<30秒） | 人工审批（几小时/几天） |
| **Hook 返回** | 立即返回 allow/deny | 立即返回 deny + pending_approval |
| **等待时间** | HTTP 请求等待审批 | 不等待，立即返回 |
| **后续处理** | Claude 立即继续或停止 | Channel 通知后重新执行 |
| **用户体验** | 无感知，快速响应 | 明确知道需要等待审批 |
| **复杂度** | 简单 | 需要审批系统 + Channel 通知 |

---

#### 2.3.4 混合审批策略

实际应用中，可以结合两种模式：

```typescript
async function handlePreToolUse(hookData) {
  const { tool_name, tool_input } = hookData

  // 1. 自动审批：低风险操作
  if (isLowRisk(tool_name, tool_input)) {
    return { decision: 'allow' }
  }

  // 2. 同步审批：中等风险，审批系统可以快速响应
  if (isMediumRisk(tool_name, tool_input)) {
    const result = await quickApprovalCheck(tool_name, tool_input)
    return result
  }

  // 3. 异步审批：高风险，需要人工审批
  if (isHighRisk(tool_name, tool_input)) {
    const approvalId = await createManualApproval(tool_name, tool_input)
    return {
      decision: 'deny',
      reason: `操作需要人工审批，审批单号: ${approvalId}`,
      approval_id: approvalId,
      pending_approval: true
    }
  }
}
```

---

#### 2.4 TaskCreated Hook - 创建子任务

**场景**: 一个任务触发多个子任务

**Hook 配置**:
```json
{
  "hooks": {
    "TaskCreated": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/task-created"
          }
        ]
      }
    ]
  }
}
```

**Claude 发送的请求**:
```json
POST /hooks/task-created
{
  "session_id": "abc123",
  "hook_event_name": "TaskCreated",
  "task_id": "task-456",
  "task_subject": "修复登录页面崩溃问题",
  "task_description": "用户反馈登录页面在 iOS 15 上崩溃..."
}
```

**HTTP 服务器返回子任务列表**:
```json
{
  "action": "create_subtasks",
  "subtasks": [
    {
      "subject": "分析崩溃日志",
      "description": "从 Crashlytics 获取崩溃日志并分析原因",
      "priority": 1
    },
    {
      "subject": "定位崩溃代码",
      "description": "根据日志定位到具体的代码行",
      "priority": 2
    },
    {
      "subject": "实现修复方案",
      "description": "修复崩溃 bug",
      "priority": 3
    },
    {
      "subject": "编写测试用例",
      "description": "添加测试用例防止回归",
      "priority": 4
    }
  ]
}
```

**Hook 脚本处理返回结果**:
```bash
#!/bin/bash
# hooks/process-task-created.sh

INPUT=$(cat)
SUBTASKS=$(echo "$INPUT" | jq -r '.subtasks // []')

# 遍历创建子任务
for subtask in $(echo "$SUBTASKS" | jq -r '.[] | @base64'); do
  _jq() {
    echo ${subtask} | base64 --decode | jq -r ${1}
  }

  SUBJECT=$(_jq '.subject')
  DESCRIPTION=$(_jq '.description')
  PRIORITY=$(_jq '.priority')

  # 创建子任务（通过输出 JSON 给 Claude）
  cat <<EOF
请创建子任务: $SUBJECT
描述: $DESCRIPTION
优先级: $PRIORITY
EOF
done

exit 0
```

#### 2.5 TaskCompleted Hook - 完成验证与平台通知

**场景**:
1. 验证任务是否真的可以完成
2. 任务完成后通知外部平台（更新任务状态）

**Hook 配置**:
```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/task-completed"
          }
        ]
      }
    ]
  }
}
```

**Claude 发送的请求**:
```json
POST /hooks/task-completed
{
  "session_id": "abc123",
  "hook_event_name": "TaskCompleted",
  "task_id": "task-456",
  "task_subject": "修复登录页面崩溃问题",
  "task_description": "用户反馈登录页面在 iOS 15 上崩溃...",
  "execution_result": {
    "status": "success",
    "summary": "已成功修复 iOS 15 WKWebView 崩溃问题",
    "artifacts": {
      "commit": "abc123",
      "pr_url": "https://github.com/repo/pull/456",
      "files_changed": ["src/LoginView.tsx"]
    }
  }
}
```

**HTTP 服务器处理流程**:

```typescript
app.post('/hooks/task-completed', async (req) => {
  const {
    task_id,
    task_subject,
    execution_result
  } = req.body

  // 1. 验证任务是否可以完成
  const validation = await validateTaskCompletion(execution_result)

  if (!validation.can_complete) {
    return {
      decision: 'deny',
      reason: validation.reason,
      continue: false,
      stopReason: validation.reason
    }
  }

  // 2. 任务验证通过，通知外部平台
  await notifyPlatform({
    task_id: task_id,
    status: 'completed',
    result: execution_result,
    completed_at: new Date()
  })

  // 3. 返回允许完成
  return {
    decision: 'allow',
    reason: '任务已完成并通知平台'
  }
})
```

**平台通知示例**:

```typescript
async function notifyPlatform(data) {
  const { task_id, status, result } = data

  // 根据任务来源通知不同平台
  const platform = getTaskPlatform(task_id)

  switch (platform) {
    case 'github':
      // 通知 GitHub（更新 Issue 状态）
      await octokit.issues.createComment({
        owner: 'owner',
        repo: 'repo',
        issue_number: extractIssueNumber(task_id),
        body: `✅ 任务完成\n\n${result.summary}\n\nPR: ${result.artifacts.pr_url}`
      })
      break

    case 'jira':
      // 通知 Jira（更新任务状态）
      await jira.updateIssue({
        issueId: task_id,
        status: 'Done',
        comment: `任务完成: ${result.summary}`
      })
      break

    case 'webhook':
      // 通用 Webhook 回调
      await axios.post(result.callback_url, {
        task_id: task_id,
        status: status,
        result: result
      })
      break
  }
}
```

**服务器返回决定**:

**方案 1: 允许完成**
```json
{
  "decision": "allow",
  "reason": "任务已完成并通知平台",
  "platform_notified": true
}
```

**方案 2: 拒绝完成**
```json
{
  "decision": "deny",
  "reason": "验证失败，不能完成任务",
  "continue": false,
  "stopReason": "请先修复问题"
}
```

**方案 3: 阻止完成但继续工作**
```json
{
  "decision": "block",
  "reason": "代码审查未通过",
  "additionalContext": "需要补充注释和错误处理"
}
```

---

#### 2.6 任务完成通知端点（可选）

除了通过 Hook 通知，也可以提供独立的任务完成通知端点：

**端点**: `POST /task-completed`

**请求格式**:
```json
{
  "task_id": "task-456",
  "status": "completed",
  "result": {
    "summary": "成功修复登录页面崩溃问题",
    "details": "..."
  }
}
```

**服务器处理**:
```typescript
app.post('/task-completed', async (req) => {
  const { task_id, status, result } = req.body

  // 通知外部平台
  await notifyPlatform({
    task_id: task_id,
    status: status,
    result: result,
    completed_at: new Date()
  })

  return {
    success: true,
    message: '平台已通知'
  }
})
```
        ]
      }
    ]
  }
}
```

**Claude 发送的请求**:
```json
POST /hooks/task-completed
{
  "session_id": "abc123",
  "hook_event_name": "TaskCompleted",
  "task_id": "task-456",
  "task_subject": "修复登录页面崩溃问题",
  "task_description": "用户反馈登录页面在 iOS 15 上崩溃..."
}
```

**HTTP 服务器返回验证结果**:

**方案 1: 允许完成**
```json
{
  "decision": "allow",
  "reason": "任务已完成所有验收标准"
}
```

**方案 2: 拒绝完成（关闭任务）**
```json
{
  "decision": "deny",
  "reason": "测试未通过，不能完成任务",
  "continue": false,
  "stopReason": "请先修复失败的测试用例"
}
```

**方案 3: 阻止完成但继续工作**
```json
{
  "decision": "block",
  "reason": "代码审查未通过，需要修改",
  "additionalContext": "审查意见: 1. 缺少错误处理 2. 缺少注释"
}
```

#### 2.6 PostToolUse Hook - 检查点验证

**场景**: 任务执行到关键检查点，需要验证

**Hook 配置**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(npm test)",
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/checkpoint"
          }
        ]
      }
    ]
  }
}
```

**Claude 发送的请求**:
```json
POST /hooks/checkpoint
{
  "session_id": "abc123",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "tool_response": {
    "exit_code": 0,
    "output": "Test suites: 10 passed, 0 failed"
  },
  "checkpoint": "test"
}
```

**HTTP 服务器返回检查结果**:

**方案 1: 检查通过**
```json
{
  "decision": "continue",
  "message": "测试检查点通过，可以继续"
}
```

**方案 2: 检查失败**
```json
{
  "decision": "block",
  "reason": "测试覆盖率不足，当前 60%，要求 80%",
  "additionalContext": "请补充测试用例以提高覆盖率"
}
```

### 3. 平台通知

**功能描述**: 任务完成后，通过 Hook 通知外部平台更新任务状态

#### 3.1 通知流程

```
Claude Code 任务完成
        ↓
TaskCompleted Hook 触发
        ↓
Channel 服务器接收并验证
        ↓
通知外部平台（GitHub/Jira/自建平台）
        ↓
平台更新任务状态
        ↓
Hook 返回 allow/deny
```

#### 3.2 支持的平台

| 平台 | 通知方式 | 更新内容 |
|-----|---------|---------|
| **GitHub** | Issue 评论、状态更新 | 完成总结、PR 链接、代码变更 |
| **Jira** | API 调用 | 任务状态、评论、附件 |
| **GitLab** | Merge Request 备注 | 完成状态、代码审查结果 |
| **自建平台** | Webhook 回调 | 任务状态、执行结果、日志 |
| **钉钉/企微** | 消息推送 | 完成通知、结果摘要 |

#### 3.3 通知配置

**方式 1: Webhook 请求中配置**

```json
{
  "task_id": "task-001",
  "title": "修复登录 Bug",
  "notification": {
    "type": "github",
    "issue_number": 42,
    "repo": "owner/repo"
  }
}
```

**方式 2: 服务器端配置映射**

```typescript
const platformMappings = {
  'task-001': {
    platform: 'github',
    repo: 'owner/repo',
    issue_number: 42
  },
  'task-002': {
    platform: 'jira',
    issue_id: 'PROJ-123'
  }
}
```

#### 3.4 通知内容格式

**GitHub Issue 评论示例**:
```markdown
✅ 任务完成

## 执行结果
成功修复登录页面在 iOS 15 上的崩溃问题

## 相关链接
- PR: #456
- Commit: abc123

---
_Automated by Claude Code_
```

**自建平台 Webhook 示例**:
```json
{
  "task_id": "task-001",
  "status": "completed",
  "result": {
    "summary": "成功修复登录 Bug",
    "artifacts": {
      "commit": "abc123",
      "pr_url": "https://github.com/repo/pull/456"
    },
    "completed_at": "2025-04-09T12:00:00Z"
  }
}
```

---

### 4. 任务链式管理

**功能描述**: Hook 可以关闭当前任务，也可以创建新的子任务

#### 3.1 关闭当前任务

**场景**: 任务已不需要继续执行

**Hook 返回**:
```json
{
  "continue": false,
  "stopReason": "相关 Feature 已被取消，停止任务"
}
```

**或者通过 exit code**:
```bash
#!/bin/bash
# 检查任务是否仍然有效
if ! is_task_still_valid; then
  echo "任务已失效，停止执行" >&2
  exit 2  # 非 0 退出码会关闭任务
fi

exit 0
```

#### 3.2 创建子任务链

**场景**: 一个父任务触发多个子任务，形成任务链

**Hook 脚本**:
```bash
#!/bin/bash
# hooks/create-subtasks.sh

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject')

# 根据任务类型创建子任务
case "$TASK_SUBJECT" in
  *"部署"*"生产环境"*)
    # 创建部署前的检查任务
    cat <<EOF
请创建以下子任务链:

1. 部署前检查
   - 运行所有测试
   - 检查代码覆盖率
   - 运行安全扫描

2. 备份数据库
   - 备份生产数据库
   - 验证备份完整性

3. 灰度发布
   - 发布到 10% 流量
   - 监控错误率
   - 逐步扩大流量

4. 验证
   - 冒烟测试
   - 性能测试
   - 回滚准备
EOF
    ;;
esac

exit 0
```

**Hook 配置**:
```json
{
  "hooks": {
    "TaskCreated": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/create-subtasks.sh"
          }
        ]
      }
    ]
  }
}
```

### 4. 任务完成回调

**功能描述**: 任务完成后，通过回调通知外部系统

#### 4.1 回调端点

**端点**: `POST /callback/{task_id}`

**请求格式**:
```json
{
  "claude_task_id": "task-456",
  "external_task_id": "external-task-123",
  "status": "completed",
  "result": {
    "summary": "已成功修复登录页面崩溃问题",
    "details": {
      "root_cause": "iOS 15 WKWebView 已知 bug",
      "fix": "添加降级方案",
      "test_results": "10 个测试用例全部通过"
    },
    "artifacts": {
      "commit": "abc123",
      "pr_url": "https://github.com/repo/pull/456"
    }
  },
  "completed_at": "2025-04-09T10:30:00Z"
}
```

**回调处理**:
- 更新外部系统任务状态
- 发送通知（邮件/IM）
- 触发后续流程

---


### 场景 1: CI/CD 失败自动修复（带审批）

**角色**: DevOps 工程师

**流程**:

1. **Jenkins 构建失败，发送 Webhook**:
```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "jenkins-1234",
    "source": "jenkins",
    "type": "build_failure",
    "title": "主分支构建失败",
    "description": "单元测试失败: UserService.test.js",
    "callback_url": "http://jenkins.example.com/callback/1234",
    "config": {
      "require_approval": true
    }
  }'
```

2. **Webhook 服务器转换为 Channel 事件**:
```typescript
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: `主分支构建失败\n单元测试失败: UserService.test.js`,
    meta: {
      task_id: 'jenkins-1234',
      source: 'jenkins',
      type: 'build_failure',
      callback_url: 'http://jenkins.example.com/callback/1234'
    }
  }
})
```

3. **Claude 接收任务并开始执行**:
```bash
Claude 收到任务: 修复主分支构建失败

任务详情:
- 源: Jenkins #1234
- 问题: 单元测试失败
- 失败测试: UserService.test.js

开始执行任务...
```

4. **Claude 开始执行，触发 PreToolUse Hook**:

Claude 尝试运行 `npm run build`，Hook 触发 HTTP 回调:
```json
POST /hooks/pre-tool-use
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm run build"
  }
}
```

5. **HTTP 服务器返回审批结果**:
```json
{
  "decision": "allow",
  "reason": "已批准构建操作"
}
```

6. **Claude 执行构建，构建失败，Hook 触发**:
```json
POST /hooks/post-tool-use-failure
{
  "tool_name": "Bash",
  "error": "Command failed with exit code 1"
}
```

7. **HTTP 服务器返回处理指示**:
```json
{
  "action": "analyze_and_fix",
  "instructions": "分析构建日志并修复问题"
}
```

8. **Claude 分析并修复问题**:
- 读取构建日志
- 识别失败的测试
- 修复代码
- 重新运行测试

9. **任务完成，触发 TaskCompleted Hook**:
```json
POST /hooks/task-completed
{
  "task_id": "task-456",
  "status": "completed"
}
```

10. **HTTP 服务器验证并返回**:
```json
{
  "decision": "allow",
  "reason": "测试已通过，允许完成任务"
}
```

11. **Webhook 服务器回调 Jenkins**:
```bash
curl -X POST http://jenkins.example.com/callback/1234 \
  -H "Content-Type: application/json" \
  -d '{
    "status": "completed",
    "result": {
      "summary": "已修复单元测试失败问题",
      "commit": "abc123"
    }
  }'
```

**价值**:
- 自动化修复流程，减少人工干预
- 关键操作有审批保障
- 实时反馈修复进度

---

### 场景 1.5: 生产环境部署（异步人工审批）

**角色**: SRE 工程师 + 运维负责人

**背景**: 需要部署到生产环境，必须经过运维负责人审批，但审批可能需要几小时

**完整流程**:

#### 阶段 1: Claude 尝试部署

1. **监控系统触发部署任务**:
```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "deploy-prod-456",
    "source": "monitoring",
    "type": "deploy_to_production",
    "title": "部署 v2.3.0 到生产环境",
    "description": "新版本包含性能优化和安全修复",
    "config": {
      "require_manual_approval": true,
      "approver": "ops-manager"
    }
  }'
```

2. **Claude 接收任务并开始执行**:
```bash
Claude 收到任务: 部署 v2.3.0 到生产环境

任务详情:
- 版本: v2.3.0
- 需要审批: 是
- 审批人: ops-manager

开始执行任务...
```

3. **Claude 尝试执行部署命令**:
```bash
Claude: 开始部署到生产环境...
        执行: kubectl apply -f deployment-prod.yaml
```

#### 阶段 2: Hook 触发，创建审批

4. **PreToolUse Hook 触发**:
```json
POST /hooks/pre-tool-use
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "kubectl apply -f deployment-prod.yaml",
    "description": "部署到生产环境"
  }
}
```

5. **HTTP 服务器识别为高风险操作，创建人工审批**:
```typescript
// 服务器代码
if (tool_input.command.includes('kubectl') && tool_input.command.includes('prod')) {
  const approvalId = `approval-${Date.now()}`

  // 保存待审批操作
  pendingApprovals.set(approvalId, {
    tool_name: 'Bash',
    tool_input: tool_input,
    session_id: 'session-abc',
    created_at: new Date()
  })

  // 发送钉钉审批通知
  await sendDingTalkApproval({
    approval_id: approvalId,
    title: '生产环境部署审批',
    content: `操作: kubectl apply -f deployment-prod.yaml\n版本: v2.3.0`,
    approve_url: `https://approval-system.example.com/${approvalId}`
  })

  // 立即返回 deny（不等待审批）
  return {
    decision: 'deny',
    reason: `⏳ 生产环境部署需要运维负责人审批\n\n审批单号: ${approvalId}\n已发送审批通知到钉钉，审批通过后将自动继续部署`,
    approval_id: approvalId,
    pending_approval: true
  }
}
```

6. **Claude 收到 deny，停止操作**:
```bash
Claude: ⏸️ 部署操作已暂停

系统消息:
⏳ 生产环境部署需要运维负责人审批

审批单号: approval-1234567890
已发送审批通知到钉钉，审批通过后将自动继续部署

我会等待审批结果，收到通知后立即继续部署...
```

#### 阶段 3: 人工审批（3 小时后）

7. **运维负责人在钉钉收到审批通知**:
```
【生产环境部署审批】

操作: kubectl apply -f deployment-prod.yaml
版本: v2.3.0
环境: production

申请人: Claude 自动化系统
时间: 2025-04-09 10:30:00

[查看详情]  [同意]  [拒绝]
```

8. **运维负责人点击"同意"**:
```bash
# 钉钉回调到审批系统
curl -X POST https://approval-system.example.com/approve/approval-1234567890 \
  -d '{
    "decision": "approve",
    "approver": "ops-manager",
    "comment": "检查了变更内容，同意部署",
    "approved_at": "2025-04-09 13:45:00"
  }'
```

#### 阶段 4: 审批通过，Channel 通知

9. **审批系统通知 Webhook 服务器**:
```bash
curl -X POST http://localhost:8080/approval-callback \
  -d '{
    "approval_id": "approval-1234567890",
    "decision": "approve",
    "approver": "ops-manager"
  }'
```

10. **Webhook 服务器通过 Channel 通知 Claude**:
```typescript
// 服务器获取审批记录
const approval = pendingApprovals.get('approval-1234567890')

// 通过 Channel 发送审批结果
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: `✅ 审批已通过

审批单号: approval-1234567890
审批人: ops-manager
审批意见: 检查了变更内容，同意部署

请继续执行部署操作`,
    meta: {
      type: 'approval_result',
      approval_id: 'approval-1234567890',
      decision: 'allow',
      original_command: 'kubectl apply -f deployment-prod.yaml'
    }
  }
})
```

#### 阶段 5: Claude 继续部署

11. **Claude 收到 Channel 消息**:
```xml
<channel source="approval-system" type="approval_result" approval_id="approval-1234567890" decision="allow">
✅ 审批已通过

审批单号: approval-1234567890
审批人: ops-manager
审批意见: 检查了变更内容，同意部署

请继续执行部署操作
</channel>
```

12. **Claude 识别审批结果，继续执行**:
```bash
Claude: ✅ 收到审批通过通知！

审批单号: approval-1234567890
审批人: ops-manager

继续执行部署操作...

→ 执行: kubectl apply -f deployment-prod.yaml
deployment.apps/myapp configured
service/myapp unchanged

✅ 部署成功！
版本 v2.3.0 已部署到生产环境
```

13. **部署完成，通知运维负责人**:
```typescript
// 服务器发送钉钉通知
await sendDingTalkMessage({
  to: 'ops-manager',
  message: `✅ 部署完成

审批单号: approval-1234567890
版本: v2.3.0
状态: 部署成功
时间: ${new Date().toISOString()}

查看详情: https://dashboard.example.com/deploy/456`
})
```

**关键时间点**:
- 10:30 - Claude 尝试部署
- 10:30 - Hook 创建审批，立即返回 deny
- 10:31 - 运维负责人收到钉钉通知
- 13:45 - 运维负责人审批通过（3 小时后）
- 13:45 - Channel 通知 Claude
- 13:46 - Claude 继续完成部署

**价值**:
- ✅ 支持长时间人工审批（几小时到几天）
- ✅ Claude 不阻塞，可以处理其他任务
- ✅ 审批通过后自动继续，无需人工干预
- ✅ 完整的审批流程追踪和通知
- ✅ 符合企业合规要求

---

### 场景 2: GitHub Issue 执行（带子任务）

**角色**: 开源项目维护者

**流程**:

1. **GitHub Issue 创建，Webhook 触发**:
```json
{
  "action": "opened",
  "issue": {
    "number": 42,
    "title": "实现用户头像上传功能",
    "body": "需要支持上传和裁剪用户头像..."
  }
}
```

2. **Webhook 服务器发送任务给 Claude**:
```xml
<channel source="github" issue_number="42">
实现用户头像上传功能
需要支持上传和裁剪用户头像...
</channel>
```

3. **Claude 接收任务并开始执行**:
```
Claude 收到任务: 实现用户头像上传功能

分析需求后，决定将任务分解为以下步骤：
1. 设计 API 接口
2. 实现后端上传逻辑
3. 实现前端裁剪组件
4. 添加单元测试
5. 更新文档

开始执行第 1 步...
```

4. **Claude 创建子任务**（TaskCreated Hook 触发）:

当 Claude 调用 TaskCreate 工具创建子任务时，TaskCreated Hook 触发：

```json
POST /hooks/task-created
{
  "task_id": "subtask-1",
  "task_subject": "设计 API 接口"
}
```

HTTP 服务器记录子任务创建：
```json
{
  "status": "recorded",
  "message": "子任务已记录"
}
```

5. **子任务串行执行**:

```
✓ 子任务 1 完成: 设计 API 接口
  → PostToolUse Hook → 检查点验证 → 通过

✓ 子任务 2 完成: 实现后端上传逻辑
  → PostToolUse Hook → 检查点验证 → 通过

✓ 子任务 3 完成: 实现前端裁剪组件
  → PostToolUse Hook → 检查点验证 → 通过

✓ 子任务 4 完成: 添加单元测试
  → PostToolUse Hook → 检查点验证 → 通过

✓ 子任务 5 完成: 更新文档
  → PostToolUse Hook → 检查点验证 → 通过
```

6. **所有子任务完成，主任务完成**:
```json
POST /hooks/task-completed
{
  "task_subject": "实现用户头像上传功能"
}
```

7. **HTTP 服务器验证并回调 GitHub**:
```bash
curl -X POST https://api.github.com/repos/owner/repo/issues/42/comments \
  -d '{
    "body": "✅ 已完成所有开发任务\n\n- API 接口设计\n- 后端实现\n- 前端实现\n- 单元测试\n- 文档更新\n\nPR: #456"
  }'
```

**价值**:
- 大任务自动分解为可管理的小任务
- 确保每个步骤都有质量检查
- 自动更新 Issue 状态

---

### 场景 3: 监控告警自动处理（带关闭任务）

**角色**: SRE 工程师

**流程**:

1. **Prometheus 告警触发**:
```json
{
  "alertname": "DatabaseConnectionsHigh",
  "severity": "critical",
  "description": "数据库连接数超过阈值: 90%"
}
```

2. **Webhook 服务器创建任务**:
```xml
<channel source="prometheus" severity="critical">
数据库连接数告警
数据库连接数超过阈值: 90%
</channel>
```

3. **Claude 开始诊断，触发检查点**:

检查点 1: 数据库连接池检查
```json
POST /hooks/checkpoint
{
  "checkpoint": "connection_pool",
  "data": {"current_connections": 900, "max_connections": 1000}
}
```

HTTP 服务器返回:
```json
{
  "decision": "continue",
  "message": "连接池使用率 90%，需要优化"
}
```

4. **Claude 优化连接池配置**:
```bash
# 修改配置
max_connections = 1500
connection_timeout = 30
```

5. **检查点 2: 验证优化效果**:
```json
POST /hooks/checkpoint
{
  "checkpoint": "verify_optimization",
  "data": {"current_connections": 600, "max_connections": 1500}
}
```

HTTP 服务器返回:
```json
{
  "decision": "continue",
  "message": "连接池使用率降至 40%，优化成功"
}
```

6. **任务完成，TaskCompleted Hook**:
```json
POST /hooks/task-completed
{
  "task_subject": "处理数据库连接数告警"
}
```

HTTP 服务器验证:
```json
{
  "decision": "allow",
  "reason": "告警已解除，连接数恢复正常"
}
```

7. **但告警仍然存在，Hook 决定关闭任务**:

实际上，告警未完全解除，HTTP 服务器返回:
```json
{
  "decision": "deny",
  "reason": "告警仍然存在，需要进一步处理",
  "continue": false,
  "stopReason": "请检查是否需要重启应用服务"
}
```

任务被关闭，等待人工介入。

**价值**:
- 自动化问题诊断和修复
- 关键检查点确保修复质量
- 知道何时停止并请求人工帮助

---

### 场景 4: 任务完成并通知平台

**场景**: Claude 完成任务后，自动通知外部平台更新状态

**流程**:

1. **任务发送（带平台通知配置）**:
```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "task-001",
    "title": "修复登录 Bug",
    "description": "用户反馈登录页面在 iOS 15 上崩溃",
    "notification": {
      "type": "github",
      "repo": "owner/repo",
      "issue_number": 42
    }
  }'
```

2. **Claude 接收并执行任务**:
```bash
Claude 收到任务: 修复登录 Bug

开始执行...
→ 分析崩溃日志
→ 定位问题代码
→ 修复代码
→ 运行测试
→ 提交 PR
```

3. **任务完成，TaskCompleted Hook 触发**:
```json
POST /hooks/task-completed
{
  "task_id": "task-001",
  "task_subject": "修复登录 Bug",
  "execution_result": {
    "status": "success",
    "summary": "成功修复 iOS 15 WKWebView 崩溃问题",
    "artifacts": {
      "commit": "abc123",
      "pr_url": "https://github.com/owner/repo/pull/456"
    }
  }
}
```

4. **服务器验证任务结果**:
```typescript
// 服务器验证
const validation = await validateTaskCompletion(execution_result)

if (!validation.tests_passed) {
  return {
    decision: 'deny',
    reason: '单元测试未通过，不能完成任务'
  }
}

// 验证通过，通知平台
await notifyPlatform({
  platform: 'github',
  repo: 'owner/repo',
  issue_number: 42,
  content: {
    title: '✅ 任务完成',
    body: `成功修复 iOS 15 WKWebView 崩溃问题

## 根本原因
iOS 15 WKWebView 的已知 bug

## 修复方案
添加了 WKWebView 的降级处理

## 验证结果
- ✅ 在 iOS 15.0 模拟器测试通过
- ✅ 在 iOS 16.0 真机测试通过
- ✅ 单元测试全部通过

## 相关链接
- PR: #456
- Commit: abc123

---
_Automated by Claude Code_`
  }
})
```

5. **服务器返回允许完成**:
```json
{
  "decision": "allow",
  "reason": "任务已完成并通知平台",
  "platform_notified": true
}
```

6. **GitHub Issue 自动更新**:
```
GitHub Issue #42 添加评论:

✅ 任务完成

成功修复 iOS 15 WKWebView 崩溃问题
...

---
_Automated by Claude Code_
```

**关键点**:
- ✅ 任务完成后自动通知平台
- ✅ 平台更新任务状态
- ✅ 无需手动同步状态

---

## 🔧 技术实现

### HTTP Webhook 服务器实现

**技术栈**: Node.js + TypeScript + Bun

**核心代码**:

```typescript
#!/usr/bin/env bun
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'

// 创建 MCP Server
const mcp = new Server(
  { name: 'task-webhook', version: '1.0.0' },
  {
    capabilities: {
      experimental: { 'claude/channel': {} }
    },
    instructions: '任务以 <channel source="task-webhook"> 格式到达。执行任务时 Hook 会回调到此服务器。'
  }
)

// 连接到 Claude Code
await mcp.connect(new StdioServerTransport())

// HTTP 服务器
Bun.serve({
  port: 8080,
  hostname: '127.0.0.1',
  async fetch(req) {
    const url = new URL(req.url)

    // 1. Webhook 接收端点
    if (url.pathname === '/webhook' && req.method === 'POST') {
      const body = await req.json()

      // 转换为 Channel 事件
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: {
          content: `${body.title}\n\n${body.description}`,
          meta: {
            task_id: body.task_id,
            source: body.source,
            type: body.type,
            priority: body.priority,
            callback_url: body.callback_url
          }
        }
      })

      return Response.json({
        status: 'received',
        message: 'Task sent to Claude'
      })
    }

    // 2. PreToolUse Hook 回调
    if (url.pathname === '/hooks/pre-tool-use' && req.method === 'POST') {
      const hookData = await req.json()

      // 审批逻辑
      const decision = await approveToolUse(hookData)

      return Response.json({
        decision: decision.allow ? 'allow' : 'deny',
        reason: decision.reason
      })
    }

    // 3. TaskCreated Hook 回调
    if (url.pathname === '/hooks/task-created' && req.method === 'POST') {
      const hookData = await req.json()

      // 创建子任务
      const subtasks = await createSubtasks(hookData)

      return Response.json({
        action: 'create_subtasks',
        subtasks: subtasks
      })
    }

    // 4. TaskCompleted Hook 回调
    if (url.pathname === '/hooks/task-completed' && req.method === 'POST') {
      const hookData = await req.json()

      // 验证任务完成
      const validation = await validateTaskCompletion(hookData)

      return Response.json({
        decision: validation.allow ? 'allow' : 'deny',
        reason: validation.reason
      })
    }

    // 5. 检查点回调
    if (url.pathname === '/hooks/checkpoint' && req.method === 'POST') {
      const checkpointData = await req.json()

      // 验证检查点
      const validation = await validateCheckpoint(checkpointData)

      return Response.json({
        decision: validation.passed ? 'continue' : 'block',
        message: validation.message
      })
    }

    return new Response('Not found', { status: 404 })
  }
})

// 审批逻辑
async function approveToolUse(hookData: any): Promise<{allow: boolean, reason: string}> {
  const { tool_name, tool_input } = hookData

  // 敏感操作需要审批
  if (tool_name === 'Bash' && tool_input.command.includes('rm -rf')) {
    // 这里可以集成审批系统（OA、钉钉等）
    // 为了演示，直接拒绝
    return {
      allow: false,
      reason: '危险操作需要人工审批'
    }
  }

  return {
    allow: true,
    reason: '已批准'
  }
}

// 创建子任务
async function createSubtasks(hookData: any): Promise<Array<any>> {
  const { task_subject } = hookData

  // 根据任务类型创建子任务
  if (task_subject.includes('部署')) {
    return [
      { subject: '部署前检查', priority: 1 },
      { subject: '备份数据库', priority: 2 },
      { subject: '灰度发布', priority: 3 },
      { subject: '验证', priority: 4 }
    ]
  }

  return []
}

// 验证任务完成
async function validateTaskCompletion(hookData: any): Promise<{allow: boolean, reason: string}> {
  // 检查任务是否真的完成了所有要求
  // 这里可以调用测试系统、代码审查系统等

  return {
    allow: true,
    reason: '任务已完成所有验收标准'
  }
}

// 验证检查点
async function validateCheckpoint(checkpointData: any): Promise<{passed: boolean, message: string}> {
  const { checkpoint, data } = checkpointData

  if (checkpoint === 'test') {
    const passRate = data.pass_rate || 0
    if (passRate < 80) {
      return {
        passed: false,
        message: `测试通过率 ${passRate}% 低于要求的 80%`
      }
    }
  }

  return {
    passed: true,
    message: '检查点通过'
  }
}
```

### Hook 配置示例

**完整配置** (`.claude/settings.json`):
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/parse-channel-task.sh",
            "description": "从 Channel 事件创建任务"
          }
        ]
      }
    ],
    "TaskCreated": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/task-created",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/pre-tool-use",
            "timeout": 30,
            "headers": {
              "Authorization": "Bearer ${WEBHOOK_TOKEN}"
            }
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "if": "Bash(npm test)",
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/checkpoint",
            "timeout": 60
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "http://localhost:8080/hooks/task-completed",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

---




$(cat /tmp/new_scenarios.md)
## 📊 成功指标

| 指标 | 目标值 | 测量方式 |
|-----|--------|---------|
| **任务响应时间** | < 5 分钟 | Webhook 到 Claude 开始执行的时间 |
| **审批响应时间** | < 2 分钟 | Hook 回调到返回决定的时间（同步审批） |
| **异步审批等待时间** | < 4 小时 | 提交审批到收到 Channel 通知的时间 |
| **任务完成率** | > 85% | 完成的任务 / 接收的任务总数 |
| **自动化率** | > 60% | 无需人工干预的任务比例 |
| **检查点拦截率** | > 95% | 发现问题的检查点比例 |

---

## 🚀 上线计划

### Phase 1: 基础任务接收 (2 周)

- ✅ Webhook 接收端点
- ✅ Channel 事件转换
- ✅ 任务接收与执行
- ✅ GitHub 集成

### Phase 2: Hook 回调机制 (2 周)

- ✅ PreToolUse Hook (审批)
- ✅ TaskCreated Hook (子任务)
- ✅ TaskCompleted Hook (验证)
- ✅ HTTP 回调端点

### Phase 3: 检查点与任务链 (2 周)

- ✅ PostToolUse Hook (检查点)
- ✅ 子任务链式创建
- ✅ 任务关闭机制
- ✅ Jenkins/Prometheus 集成

### Phase 4: 企业级功能 (2 周)

- ✅ 审批系统集成 (OA/BPM)
- ✅ 任务完成回调
- ✅ Jira/Tapd 集成
- ✅ 审计日志

---

## 📝 附录

### A. Hook 事件与 HTTP 回调映射

| Hook 事件 | 回调端点 | 返回字段 | 说明 |
|-----------|---------|---------|------|
| PreToolUse | /hooks/pre-tool-use | decision (allow/deny/ask), reason, updatedInput | 审批权限 |
| TaskCreated | /hooks/task-created | status (recorded), message | 记录子任务创建（Claude 自行创建子任务） |
| TaskCompleted | /hooks/task-completed | decision (allow/deny/block), reason, continue, stopReason | 验证是否可完成 |
| PostToolUse | /hooks/checkpoint | decision (continue/block), message | 检查点验证 |
| PostToolUseFailure | /hooks/error-handler | action (retry/abort), instructions | 错误处理 |

### B. 任务数据模型

```typescript
interface WebhookRequest {
  task_id: string           // 外部系统任务 ID
  source: string            // 任务来源（jenkins, github, jira等）
  type: string              // 任务类型
  title: string             // 任务标题
  description: string       // 任务描述
  priority: 'low' | 'medium' | 'high' | 'critical'
  metadata: Record<string, any>  // 额外元数据
  callback_url?: string     // 完成回调 URL
  config?: {
    require_approval?: boolean   // 是否需要审批
    checkpoints?: string[]       // 检查点列表
  }
}

interface PreToolUseCallback {
  decision: 'allow' | 'deny' | 'ask'
  reason?: string
  updatedInput?: any         // 修改后的工具输入
  approval_id?: string       // 审批 ID（异步审批）
  pending_approval?: boolean // 是否等待审批
}

interface TaskCreatedCallback {
  status: 'recorded'         // 子任务已记录
  message: string            // 附加信息
  // 注意：服务器不再返回子任务列表，Claude 自行决定是否创建子任务
}

interface TaskCompletedCallback {
  decision: 'allow' | 'deny' | 'block'
  reason?: string
  continue?: boolean
  stopReason?: string
}

interface CheckpointCallback {
  decision: 'continue' | 'block'
  message: string
}
```

---

**文档结束**

_版本 3.0 - Channel 只负责任务下发与执行控制（审批、监控、检查点），不包含任务创建方式（通过 CLI 工具或 GitHub Issues）。_
