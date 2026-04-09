---
description: 管理任务生命周期的技能，包括任务创建、状态跟踪、审批管理等
---

# Task Manager Skill

任务管理技能，帮助你管理从 Channel 接收的任务。

## 功能

### 1. 任务状态跟踪

自动跟踪任务状态：
- `pending`: 待处理
- `in_progress`: 进行中
- `waiting_approval`: 等待审批
- `completed`: 已完成
- `failed`: 失败

### 2. 审批管理

处理审批流程：
- 创建审批请求
- 跟踪审批状态
- 接收审批结果
- 继续或停止操作

### 3. 平台集成

与外部平台集成：
- GitHub Issues
- Jira Tickets
- 自建平台（Webhook）

## 使用场景

当你从 Channel 接收到任务时：

```
<channel task_id="task-123" priority="high">
修复登录页面崩溃问题
</channel>
```

你应该：
1. 理解任务要求
2. 创建任务记录
3. 开始执行
4. 遇到敏感操作时，等待审批
5. 完成后验证结果
6. 通过 Hook 通知平台

## 审批结果处理

当你收到审批结果通知时：

```
<channel type="approval_result" approval_id="approval-123" decision="allow">
审批已通过，请继续执行: rm -rf node_modules
</channel>
```

你应该：
1. 识别这是审批结果
2. 提取原始操作
3. 执行该操作
4. 继续任务
