# MCP Channels 技术方案总结

**文档版本**: 1.0
**创建日期**: 2025-04-09
**参考文档**: [Claude Code Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)

---

## 📋 概述

### 什么是 Channel?

Channel 是一个 MCP 服务器，将外部事件（webhooks、警报、聊天消息）推送到 Claude Code 会话中，使 Claude 能够对终端外发生的事情做出反应。

### 核心特性

- **单向频道**: 转发警报、webhooks 或监控事件供 Claude 处理
- **双向频道**: 如聊天桥接，公开回复工具，Claude 可以发送消息回复
- **权限中继**: 受信任的频道可以远程批准或拒绝工具使用

---

## 🏗️ 技术架构

### 通信方式

```
外部系统 (GitHub/Jira/CI)
    ↓ HTTP Webhook
Channel MCP Server (本地或远程运行)
    ↓ MCP over WebSocket (双向通信)
Claude Code
```

**重要**：
- Channel 服务器可以作为：
  - **本地子进程**：通过 stdio 通信（开发环境）
  - **远程服务器**：通过 WebSocket 通信（生产环境）✅ 我们使用这个
- **WebSocket** 支持 MCP 双向通信
- 不需要额外的协议层

### 双向通信机制

MCP 协议支持双向通信：

1. **Client → Server**: MCP Tools（Claude 调用服务器工具）
2. **Server → Client**: MCP Notifications（服务器主动推送消息）

```typescript
// 服务器主动推送消息给 Claude
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: "消息内容",
    meta: { /* 属性 */ }
  }
})
```

---

## 🔧 核心组件

### 1. 能力声明 (Capabilities)

```typescript
const mcp = new Server(
  { name: 'my-channel', version: '1.0.0' },
  {
    capabilities: {
      // 必需：声明为 Channel
      experimental: {
        'claude/channel': {},
        // 可选：权限中继
        'claude/channel/permission': {}
      },
      // 双向频道需要
      tools: {}
    },
    // 添加到 Claude 的系统提示
    instructions: '告诉 Claude 如何处理事件'
  }
)
```

**能力字段说明**：

| 字段 | 类型 | 必需 | 描述 |
|------|------|------|------|
| `capabilities.experimental['claude/channel']` | object | ✅ | 始终为 `{}`，注册通知侦听器 |
| `capabilities.experimental['claude/channel/permission']` | object | ❌ | 权限中继，远程审批工具使用 |
| `capabilities.tools` | object | ❌ | 双向频道需要，声明提供工具 |
| `instructions` | string | 📝 | 推荐，告诉 Claude 如何处理事件 |

### 2. 通知格式 (Notification)

**发送通知**：

```typescript
await mcp.notification({
  method: 'notifications/claude/channel',
  params: {
    content: '事件主体内容',
    meta: {
      // 每个键成为 <channel> 标签的属性
      severity: 'high',
      task_id: '123',
      source: 'github'
    }
  }
})
```

**参数说明**：

| 字段 | 类型 | 描述 |
|------|------|------|
| `content` | string | 事件主体，成为 `<channel>` 标签的内容 |
| `meta` | Record<string, string> | 可选，每个条目成为标签属性（键必须是标识符：字母、数字、下划线） |

**在 Claude 中的呈现**：

```xml
<channel source="my-channel" severity="high" task_id="123">
事件主体内容
</channel>
```

### 3. 回复工具 (Reply Tools)

**注册工具**：

```typescript
mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: 'reply',
    description: 'Send a message back over this channel',
    inputSchema: {
      type: 'object',
      properties: {
        chat_id: { type: 'string', description: '对话 ID' },
        text: { type: 'string', description: '消息内容' }
      },
      required: ['chat_id', 'text']
    }
  }]
}))

mcp.setRequestHandler(CallToolRequestSchema, async req => {
  if (req.params.name === 'reply') {
    const { chat_id, text } = req.params.arguments
    // 发送消息到外部系统
    await sendMessage(chat_id, text)
    return { content: [{ type: 'text', text: 'sent' }] }
  }
})
```

### 4. 权限中继 (Permission Relay)

**接收权限请求**：

```typescript
const PermissionRequestSchema = z.object({
  method: z.literal('notifications/claude/channel/permission_request'),
  params: z.object({
    request_id: z.string(),      // 5 个小写字母（不含 'l'）
    tool_name: z.string(),       // 工具名称（Bash、Write 等）
    description: z.string(),     // 操作描述
    input_preview: z.string()    // 参数预览（~200 字符）
  })
})

mcp.setNotificationHandler(PermissionRequestSchema, async ({ params }) => {
  // 格式化提示并发送到外部系统
  send(`
    Claude wants to run ${params.tool_name}: ${params.description}

    Reply "yes ${params.request_id}" or "no ${params.request_id}"
  `)
})
```

**发送权限判决**：

```typescript
// 解析用户回复（格式：yes abcde 或 no abcde）
const PERMISSION_REPLY_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i
const match = PERMISSION_REPLY_RE.exec(message.text)

if (match) {
  await mcp.notification({
    method: 'notifications/claude/channel/permission',
    params: {
      request_id: match[2].toLowerCase(),
      behavior: match[1].toLowerCase().startsWith('y') ? 'allow' : 'deny'
    }
  })
}
```

---

## 🔐 安全考虑

### 发送者门控 (Sender Gating)

**防止提示注入**：

```typescript
const allowed = new Set(['user-id-1', 'user-id-2'])

// 在发送通知前检查发送者
if (!allowed.has(message.from.id)) {
  return // 静默丢弃
}
await mcp.notification({ ... })
```

**重要原则**：
- 根据发送者身份门控，而不是房间/聊天身份
- 在群组聊天中，`message.from.id` ≠ `message.chat.id`
- 只有受信任的发送者才能触发权限中继

---

## 📦 快速开始示例

### 最小 Webhook 接收器

```typescript
#!/usr/bin/env bun
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'

const mcp = new Server(
  { name: 'webhook', version: '1.0.0' },
  {
    capabilities: {
      experimental: { 'claude/channel': {} }
    },
    instructions: 'Events arrive as <channel source="webhook">. Read and act.'
  }
)

await mcp.connect(new StdioServerTransport())

Bun.serve({
  port: 8788,
  hostname: '127.0.0.1',
  async fetch(req) {
    const body = await req.text()
    await mcp.notification({
      method: 'notifications/claude/channel',
      params: {
        content: body,
        meta: {
          path: new URL(req.url).pathname,
          method: req.method
        }
      }
    })
    return new Response('ok')
  }
})
```

### MCP 配置

**`.mcp.json`**（项目级）：

```json
{
  "mcpServers": {
    "webhook": {
      "command": "bun",
      "args": ["./webhook.ts"]
    }
  }
}
```

**`~/.claude.json`**（用户级）：

```json
{
  "mcpServers": {
    "webhook": {
      "command": "bun",
      "args": ["/absolute/path/to/webhook.ts"]
    }
  }
}
```

### 测试

```bash
# 启动 Claude Code（研究预览需要开发标志）
claude --dangerously-load-development-channels server:webhook

# 发送测试 webhook
curl -X POST localhost:8788 -d "Hello from webhook!"

# Claude 会收到：
# <channel source="webhook" path="/" method="POST">Hello from webhook!</channel>
```

---

## 🚀 部署架构

### 本地部署（开发环境）

```
Claude Code（本地）
    ↓ spawn 子进程
Channel MCP Server（本地）
    ↓ HTTP
外部系统（本地 CI）
```

### 远程部署（生产环境）

```
外部系统（GitHub/Jira - 公网）
    ↓ Webhook
fast-task-server（云服务器）
    ↓ WebSocket (wss://)
Claude Code（内网开发机）
    ↓ MCP over WebSocket
双向通信
```

**WebSocket 配置**：

```json
// .mcp.json
{
  "mcpServers": {
    "task-channel": {
      "transport": {
        "type": "websocket",
        "url": "wss://task-server.com:8080/mcp"
      }
    }
  }
}
```

**服务器端实现**：

```python
# FastAPI WebSocket 端点
@app.websocket("/mcp")
async def websocket_mcp(websocket: WebSocket):
    await websocket.accept()

    # 验证 token
    token = websocket.query_params.get("token")
    employee = await verify_employee(token)

    # 建立 MCP 连接
    transport = WebSocketServerTransport(websocket)
    await mcp_server.connect(transport)
```

---

## 📊 事件流

### 单向频道（Webhook/警报）

```
1. 外部系统发送 HTTP POST
2. Channel Server 接收请求
3. 发送 MCP Notification 给 Claude
4. Claude 处理事件（执行工具、运行命令等）
```

### 双向频道（聊天桥接）

```
1. 外部系统有新消息
2. Channel Server 接收消息
3. 发送 MCP Notification 给 Claude
4. Claude 调用 reply 工具
5. Channel Server 发送回复到外部系统
```

### 权限中继

```
1. Claude 想要执行需要批准的工具
2. 本地终端对话打开
3. 同时发送 permission_request 通知到 Channel
4. Channel 转发到外部系统（手机/聊天）
5. 用户在外部系统回复 yes/no <request_id>
6. Channel 发送 permission 判决通知
7. Claude Code 应用第一个到达的答案（本地或远程）
```

---

## 📝 系统提示 (Instructions)

**推荐写法**：

```typescript
instructions: `
Messages arrive as <channel source="my-channel" chat_id="..." severity="...">.

The 'chat_id' attribute identifies the conversation.
The 'severity' attribute indicates urgency (low/medium/high).

Reply with the 'reply' tool, passing the 'chat_id' from the tag.
`
```

**关键信息**：
- `<channel>` 标签的外观和属性含义
- 是否需要回复，使用哪个工具
- 需要传回哪些属性（如 `chat_id`）

---

## ⚠️ 重要限制

### 研究预览限制

1. **需要 Claude Code v2.1.80+**
2. **需要 claude.ai 登录**（不支持 API 密钥）
3. **Team/Enterprise 需要管理员启用**
4. **需要开发标志**（自定义频道不在批准列表）：
   ```bash
   claude --dangerously-load-development-channels server:my-channel
   ```

### ID 格式（权限中继）

- 请求 ID：5 个小写字母（`a-km-z`，不含 `l`）
- 示例：`abcde`、`xyzpq`
- 设计目的：避免在手机上与 `1` 或 `I` 混淆

---

## 📚 相关资源

- **官方文档**: [Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)
- **使用指南**: [Channels](https://code.claude.com/docs/zh-CN/channels) - 安装和使用预构建频道
- **MCP 协议**: [Model Context Protocol](https://modelcontextprotocol.io/)
- **插件系统**: [Plugins Reference](https://code.claude.com/docs/zh-CN/plugins-reference)

---

## 🎯 最佳实践

### 1. 发送者验证
- 始终根据 `message.from.id`（发送者）进行门控
- 不要只根据 `message.chat.id`（房间）门控
- 使用配对流程添加受信任发送者

### 2. 错误处理
- 权限判决格式不匹配时，作为普通消息处理
- ID 不匹配时静默丢弃（防止重放攻击）
- 记录所有拒绝的事件用于调试

### 3. 性能考虑
- 使用 SSE（Server-Sent Events）流式传输出站消息
- 设置合理的 `idleTimeout`（或禁用）
- 批量处理多个 webhook 请求

### 4. 安全建议
- 使用 HTTPS 接收 webhook
- 验证 webhook 签名（GitHub、Jira）
- 限制 `hostname` 为 `127.0.0.1`（仅本地访问）
- 使用环境变量存储敏感信息

---

## 🔍 调试技巧

### 检查连接状态

```bash
# 在 Claude Code 会话中运行
/mcp
```

### 查看调试日志

```bash
# 查看服务器 stderr
~/.claude/debug/<session-id>.txt
```

### 检查端口占用

```bash
# 查看端口绑定情况
lsof -i :8788

# 杀死占用端口的进程
kill -9 <PID>
```

---

## 📌 总结

### 核心要点

1. **Channel = MCP Server + Notification 能力**
2. **双向通信 = MCP Tools + MCP Notifications**
3. **不需要 WebSocket** - stdio 本身支持双向
4. **权限中继** = 远程审批工具使用
5. **安全第一** - 发送者门控防止提示注入

### 适用场景

- ✅ CI/CD 失败通知
- ✅ 监控警报推送
- ✅ 聊天桥接（Telegram、Discord）
- ✅ GitHub Issues/Jira 集成
- ✅ 远程审批工具使用
- ❌ 高频实时数据（考虑轮询或 SSE）

### 下一步

1. 阅读完整 [Channels Reference](https://code.claude.com/docs/zh-CN/channels-reference)
2. 查看 [预构建频道](https://code.claude.com/docs/zh-CN/channels) 示例
3. 参考 [MCP SDK](https://github.com/modelcontextprotocol/typescript-sdk) 实现细节
4. 构建你的第一个 Channel！

---

**文档更新**: 2025-04-09
**作者**: Claude Code 技术团队
**许可证**: MIT
