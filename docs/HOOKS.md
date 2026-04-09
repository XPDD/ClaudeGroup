# Claude Code Hooks 参考文档

**文档版本**: 1.0
**创建日期**: 2025-04-09
**来源**: [Claude Code Hooks Reference](https://code.claude.com/docs/zh-CN/hooks)

本文档详细记录了 Claude Code 所有 Hook 事件及其用法，用于任务执行控制系统的架构设计。

---

## 目录

- [Hook 概述](#hook-概述)
- [会话级别 Hooks](#会话级别-hooks)
- [输入级别 Hooks](#输入级别-hooks)
- [工具级别 Hooks](#工具级别-hooks)
- [任务级别 Hooks](#任务级别-hooks)
- [通知 Hooks](#通知-hooks)
- [Agent Hooks](#agent-hooks)
- [配置 Hooks](#配置-hooks)
- [目录 Hooks](#目录-hooks)
- [Worktree Hooks](#worktree-hooks)
- [压缩 Hooks](#压缩-hooks)
- [引导 Hooks](#引导-hooks)
- [协作 Hooks](#协作-hooks)
- [Hook 配置示例](#hook-配置示例)

---

## Hook 概述

### 什么是 Hook?

Hook 是在 Claude Code 执行过程中特定时机触发的自动化机制。通过配置 Hook，可以：
- 在特定事件发生时执行自定义逻辑
- 控制操作流程（允许/拒绝/请求审批）
- 记录和监控执行状态
- 与外部系统集成

### Hook 类型

1. **Command Hook**: 执行 shell 命令
2. **HTTP Hook**: 发送 HTTP 请求到外部服务
3. **Notify Hook**: 发送 Channel 通知

### Hook 决定类型

| 决定类型 | 说明 | 适用 Hook |
|---------|------|----------|
| `allow` | 允许操作继续 | PreToolUse, TaskCompleted, PermissionRequest |
| `deny` | 拒绝操作 | PreToolUse, TaskCompleted, PermissionRequest |
| `ask` | 询问用户 | PreToolUse, PermissionRequest |
| `block` | 阻止并等待 | UserPromptSubmit |
| `pending_approval` | 等待异步审批 | PreToolUse |

### Hook 配置位置

- **插件级别**: `fast-task-claude-plugin/hooks/hooks.json`
- **用户级别**: `~/.claude/hooks.json`

---

## 会话级别 Hooks

### SessionStart

**触发时机**: Claude Code 会话启动时

**输入 Schema**:
```json
{
  "cwd": "/path/to/working/directory",
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

**输出控制**: 无（仅记录）

**使用场景**:
- 加载项目上下文和配置
- 初始化任务状态
- 检查环境依赖
- 初始化外部连接

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/scripts/load-context.sh"
  }]
}
```

---

### SessionEnd

**触发时机**: Claude Code 会话结束时

**输入 Schema**:
```json
{
  "duration_ms": 3600000,
  "cwd": "/path/to/working/directory"
}
```

**输出控制**: 无

**使用场景**:
- 清理临时文件
- 保存会话状态
- 发送会话总结
- 关闭外部连接

---

## 输入级别 Hooks

### UserPromptSubmit

**触发时机**: 用户提交新输入时

**输入 Schema**:
```json
{
  "prompt": "请修复登录页面的 bug",
  "attachments": ["file1.png"]
}
```

**输出控制**:
- `allow`: 正常处理
- `block`: 阻止处理（可用于预检查）

**使用场景**:
- 输入验证和过滤
- 预处理用户请求
- 记录用户输入
- 检测恶意指令

---

### Stop

**触发时机**: 用户按下 Ctrl+C 或执行 `/stop` 命令

**输入 Schema**:
```json
{
  "reason": "user_interrupt"
}
```

**输出控制**: 无

**使用场景**:
- 清理进行中的操作
- 保存中间状态
- 通知外部系统中断

---

### StopFailure

**触发时机**: 停止操作失败时

**输入 Schema**:
```json
{
  "error": "Failed to stop background task"
}
```

**输出控制**: 无

**使用场景**:
- 记录停止失败
- 强制清理资源
- 发送告警通知

---

## 工具级别 Hooks

### PreToolUse

**触发时机**: 工具执行前

**输入 Schema**:
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "rm -rf node_modules"
  },
  "permissionMode": "auto"
}
```

**输出控制**:
- `allow`: 允许执行
- `deny`: 拒绝执行
- `ask`: 询问用户
- `pending_approval`: 发起异步审批

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "http",
    "url": "http://localhost:8080/hooks/pre-tool-use",
    "timeout": 5000
  }]
}
```

**响应示例**:
```json
{
  "decision": "deny",
  "error_message": "需要审批才能删除 node_modules",
  "pending_approval": {
    "approval_id": "approval-12345",
    "message": "正在等待审批"
  }
}
```

---

### PostToolUse

**触发时机**: 工具执行成功后

**输入 Schema**:
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "npm install"
  },
  "toolResult": {
    "exitCode": 0,
    "stdout": "...",
    "stderr": "..."
  },
  "duration_ms": 15000
}
```

**输出控制**: 无

**使用场景**:
- 记录工具执行结果
- 触发后续操作
- 检查点验证
- 进度通知

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "http",
    "url": "http://localhost:8080/hooks/post-tool-use"
  }]
}
```

---

### PostToolUseFailure

**触发时机**: 工具执行失败时

**输入 Schema**:
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "make build"
  },
  "error": "Command failed with exit code 1",
  "duration_ms": 5000
}
```

**输出控制**: 无

**使用场景**:
- 错误日志记录
- 失败原因分析
- 自动重试逻辑
- 发送错误通知

**任务系统应用**: 由 Claude Code 自己处理错误，Hook 仅记录

---

### PermissionRequest

**触发时机**: 用户尝试执行需要权限的操作

**输入 Schema**:
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "rm -rf /tmp/data"
  },
  "permissionMode": "manual"
}
```

**输出控制**:
- `allow`: 自动允许
- `deny`: 自动拒绝
- `ask`: 询问用户

**使用场景**:
- 权限预检查
- 基于策略的授权
- 审计日志

---

### PermissionDenied

**触发时机**: 权限请求被拒绝时

**输入 Schema**:
```json
{
  "toolName": "Bash",
  "toolInput": {
    "command": "rm -rf /tmp/data"
  },
  "reason": "User denied permission"
}
```

**输出控制**: 无

**使用场景**:
- 记录拒绝事件
- 触发替代方案
- 安全审计

---

## 任务级别 Hooks

### TaskCreated

**触发时机**: 创建新任务时

**输入 Schema**:
```json
{
  "taskId": "task-123",
  "subject": "修复登录页面崩溃问题",
  "description": "用户报告登录后页面崩溃",
  "activeForm": "修复登录页面崩溃问题",
  "status": "pending"
}
```

**输出控制**: 无

**使用场景**:
- 记录任务创建
- 通知外部系统
- 初始化任务上下文
- 分配任务资源

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "http",
    "url": "http://localhost:8080/hooks/task-created"
  }]
}
```

---

### TaskCompleted

**触发时机**: 任务完成时

**输入 Schema**:
```json
{
  "taskId": "task-123",
  "subject": "修复登录页面崩溃问题",
  "status": "completed",
  "result": {
    "files_changed": ["src/login.tsx"],
    "tests_passed": true
  }
}
```

**输出控制**:
- `allow`: 允许标记为完成
- `deny`: 拒绝完成（需要继续工作）

**使用场景**:
- 验证任务完成条件
- 通知外部平台（GitHub、Jira）
- 触发后续任务
- 生成完成报告

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "http",
    "url": "http://localhost:8080/hooks/task-completed",
    "timeout": 10000
  }]
}
```

---

## 通知 Hooks

### Notification

**触发时机**: 系统发送通知时

**输入 Schema**:
```json
{
  "type": "background_task_completed",
  "message": "Background task 'test-runner' completed",
  "metadata": {
    "taskId": "bg-123"
  }
}
```

**输出控制**: 无

**使用场景**:
- 转发通知到外部系统
- 自定义通知格式
- 通知过滤和聚合

---

## Agent Hooks

### SubagentStart

**触发时机**: 子 Agent 启动时

**输入 Schema**:
```json
{
  "agentId": "agent-456",
  "agentType": "product-manager",
  "parentTaskId": "task-123"
}
```

**输出控制**: 无

**使用场景**:
- 记录 Agent 启动
- 分配 Agent 资源
- 监控 Agent 状态

---

### SubagentStop

**触发时机**: 子 Agent 停止时

**输入 Schema**:
```json
{
  "agentId": "agent-456",
  "agentType": "product-manager",
  "result": {
    "status": "success",
    "output": "..."
  }
}
```

**输出控制**: 无

**使用场景**:
- 记录 Agent 结果
- 清理 Agent 资源
- 聚合 Agent 输出

---

## 配置 Hooks

### ConfigChange

**触发时机**: 配置更改时

**输入 Schema**:
```json
{
  "key": "approval_mode",
  "oldValue": "sync",
  "newValue": "async"
}
```

**输出控制**: 无

**使用场景**:
- 配置审计日志
- 验证配置变更
- 重新加载配置

---

### InstructionsLoaded

**触发时机**: 加载项目指令时

**输入 Schema**:
```json
{
  "path": "/path/to/CLAUDE.md",
  "source": "project"
}
```

**输出控制**: 无

**使用场景**:
- 验证指令格式
- 缓存指令内容
- 指令版本管理

---

## 目录 Hooks

### CwdChanged

**触发时机**: 工作目录更改时

**输入 Schema**:
```json
{
  "oldCwd": "/old/path",
  "newCwd": "/new/path"
}
```

**输出控制**: 无

**使用场景**:
- 更新上下文
- 检查目录权限
- 重新加载项目配置

**任务系统应用**:
```json
{
  "hooks": [{
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-dir-change.sh"
  }]
}
```

---

### FileChanged

**触发时机**: 文件内容发生变化时（通过文件监听）

**输入 Schema**:
```json
{
  "path": "/path/to/file.txt",
  "changeType": "modified"
}
```

**输出控制**: 无

**使用场景**:
- 热重载配置
- 触发测试
- 自动同步

---

## Worktree Hooks

### WorktreeCreate

**触发时机**: 创建 Git worktree 时

**输入 Schema**:
```json
{
  "path": "/path/to/worktree",
  "branch": "feature-branch"
}
```

**输出控制**: 无

**使用场景**:
- 初始化 worktree 环境
- 安装依赖
- 配置 IDE

---

### WorktreeRemove

**触发时机**: 删除 Git worktree 时

**输入 Schema**:
```json
{
  "path": "/path/to/worktree",
  "branch": "feature-branch"
}
```

**输出控制**: 无

**使用场景**:
- 清理 worktree 资源
- 保存工作结果
- 通知团队

---

## 压缩 Hooks

### PreCompact

**触发时机**: 压缩上下文前

**输入 Schema**:
```json
{
  "currentSize": 180000,
  "targetSize": 150000
}
```

**输出控制**: 无

**使用场景**:
- 保存重要上下文
- 准备压缩数据

---

### PostCompact

**触发时机**: 压缩上下文后

**输入 Schema**:
```json
{
  "originalSize": 180000,
  "compressedSize": 150000,
  "removedMessages": 50
}
```

**输出控制**: 无

**使用场景**:
- 记录压缩结果
- 恢复必要上下文

---

## 引导 Hooks

### Elicitation

**触发时机**: 系统请求用户澄清时

**输入 Schema**:
```json
{
  "question": "您希望使用哪个数据库?",
  "options": ["PostgreSQL", "MySQL", "MongoDB"]
}
```

**输出控制**: 无

**使用场景**:
- 记录用户选择
- 预设默认选项
- 引导流程优化

---

### ElicitationResult

**触发时机**: 用户完成选择时

**输入 Schema**:
```json
{
  "question": "您希望使用哪个数据库?",
  "answer": "PostgreSQL"
}
```

**输出控制**: 无

**使用场景**:
- 记录用户偏好
- 更新项目配置
- 学习用户习惯

---

## 协作 Hooks

### TeammateIdle

**触发时机**: 检测到团队成员空闲时

**输入 Schema**:
```json
{
  "teammate": "user@example.com",
  "idleTime_ms": 300000
}
```

**输出控制**: 无

**使用场景**:
- 任务分配建议
- 通知可接手任务
- 团队协作优化

---

## Hook 配置示例

### 完整的 hooks.json

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
        "timeout": 5000
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

    "CwdChanged": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-dir-change.sh"
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

### Hook Matcher

使用 `matcher` 字段过滤特定工具或事件：

```json
{
  "PreToolUse": [{
    "matcher": "Bash|Write|Edit",
    "hooks": [...]
  }, {
    "matcher": "Read|Grep",
    "hooks": [...]  // 只监听读取操作
  }]
}
```

### Hook 超时配置

```json
{
  "hooks": [{
    "type": "http",
    "url": "http://localhost:8080/hooks/approval",
    "timeout": 30000  // 30秒超时
  }]
}
```

### 条件 Hook

```json
{
  "PreToolUse": [{
    "matcher": "Bash",
    "when": {
      "toolInput.command": "rm -rf*"
    },
    "hooks": [{
      "type": "http",
      "url": "http://localhost:8080/hooks/dangerous-operation"
    }]
  }]
}
```

---

## 任务执行生命周期 Hook 流程

```
┌─────────────────────────────────────────────────────────────┐
│  1. SessionStart                                             │
│     加载项目上下文、初始化状态                                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  2. UserPromptSubmit                                         │
│     用户提交任务请求                                          │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  3. TaskCreated                                              │
│     创建任务记录、通知外部系统                                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  4. SubagentStart (如果使用子 Agent)                         │
│     启动专门的执行 Agent                                      │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  5. PreToolUse (循环执行)                                    │
│     • 风险评估                                                │
│     • 低风险: allow                                          │
│     • 中风险: 同步审批                                        │
│     • 高风险: deny + pending_approval                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  6. PostToolUse / PostToolUseFailure                         │
│     • 记录执行结果                                            │
│     • 检查点验证                                              │
│     • 进度通知                                                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  7. TaskCompleted                                            │
│     • 验证任务完成条件                                        │
│     • 通知外部平台 (GitHub/Jira)                             │
│     • 返回 allow/deny                                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  8. SubagentStop (如果使用子 Agent)                          │
│     停止执行 Agent、汇总结果                                  │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  9. SessionEnd                                               │
│     清理资源、保存状态                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Hook 最佳实践

### 1. 性能考虑

- HTTP Hook 应设置合理的超时（5-10秒）
- 避免在 Hook 中执行长时间操作
- 使用异步处理而非阻塞等待

### 2. 错误处理

- Hook 失败不应阻塞 Claude Code 执行
- 记录所有 Hook 错误日志
- 提供降级策略

### 3. 安全考虑

- 验证 Hook 请求来源
- 敏感数据使用加密传输
- 记录所有审计日志

### 4. 测试策略

- 单元测试每个 Hook 处理器
- 集成测试完整 Hook 流程
- 模拟各种失败场景

---

## 参考资料

- [Claude Code Plugins Reference](https://code.claude.com/docs/zh-CN/plugins-reference)
- [Claude Code Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)
- [Claude Code Hooks Reference](https://code.claude.com/docs/zh-CN/hooks)
- [PRD](./PRD.md)
- [架构设计](./ARCHITECTURE.md)
- [HOOKS说明](./HOOKS.md)
