# ClaudeGroup

> 为 Claude Code 提供任务通道和执行控制能力的插件系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Plugin-blue)](https://code.claude.com/docs/zh-CN/plugins-reference)

## 📋 项目简介

**ClaudeGroup** 是一个 Claude Code 插件系统，通过 MCP (Model Context Protocol) 实现任务下发、执行控制和异步审批功能。

### 核心能力

- **🎯 任务下发**: 通过 HTTP Webhook 接收任务，自动转换为 Channel 事件发送给 Claude Code
- **🔐 执行控制**: 基于 Hook 的审批机制，支持同步/异步审批流程
- **⏱️ 异步审批**: 支持长时间人工审批场景（几小时到几天），不阻塞 Claude 执行
- **✅ 检查点验证**: 自动验证测试、Lint、安全扫描等检查点
- **🔔 平台通知**: 任务完成后自动通知 GitHub、Jira 等外部平台

## 🎯 使用场景

### 1. CI/CD 失败自动修复
```
Jenkins 构建失败 → Webhook 通知 → Claude 分析日志 → 自动修复 → PR 回调
```

### 2. 敏感操作审批
```
Claude 尝试删除数据 → Hook 触发审批 → 钉钉/企微审批 → 审批通过 → Claude 继续执行
```

### 3. GitHub Issue 自动处理
```
GitHub Issue 创建 → Webhook 转发 → Claude 处理 Issue → 更新 Issue 状态
```

### 4. 生产部署审批
```
Claude 发起部署 → 创建审批单 → 运维负责人审批 → 审批通过 → 自动部署
```

## 🏗️ 项目架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         ClaudeGroup                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  fast-task-claude-plugin (TypeScript)                      │ │
│  │  • Hook 配置与脚本                                          │ │
│  │  • Agents 定义 (产品/开发/测试/运维)                         │ │
│  │  • MCP 连接配置                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  fast-task-server (Python + FastAPI)                       │ │
│  │  • Webhook 接收端点                                         │ │
│  │  • Hook 回调处理                                            │ │
│  │  • 审批管理                                                 │ │
│  │  • 平台通知 (GitHub/Jira)                                   │ │
│  │  • MCP Channel 服务器 (WebSocket)                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  fast-task-ui (Nuxt 4 + Vue 3)                             │ │
│  │  • Web 管理界面                                             │ │
│  │  • 任务管理与监控                                           │ │
│  │  • 审批流管理                                               │ │
│  │  • Agent 状态可视化                                          │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  openclaw-plugin-fast-task (OpenClaw Plugin)               │ │
│  │  • WebSocket 通信节点                                       │ │
│  │  • 节点注册 (whoIAm)                                       │ │
│  │  • 点对点聊天                                               │ │
│  │  • Workspace 文件操作                                       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                   │
└────────────┬──────────────────────────┬──────────────────────────┘
             │                          │
             │ MCP/WebSocket            │ HTTP/WebSocket
             ▼                          ▼
┌─────────────────────────┐  ┌─────────────────────────────────┐
│      Claude Code        │  │      外部平台                    │
│  • 接收任务              │  │  • GitHub Issues               │
│  • 执行任务              │  │  • Jira                        │
│  • Hook 触发             │  │  • Jenkins/GitLab CI           │
│  • 审批交互              │  │  • 钉钉/企微审批                │
└─────────────────────────┘  └─────────────────────────────────┘
```

## 🔑 核心功能

### 1. 任务下发（Channel）

通过 HTTP Webhook 接收任务，转换为 MCP Channel 事件：

```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "task-123",
    "title": "修复登录页面崩溃",
    "description": "用户反馈在 iOS 15 上登录后崩溃",
    "priority": "high",
    "config": {
      "require_approval": true,
      "checkpoints": ["test", "lint"]
    }
  }'
```

### 2. 执行控制（Hook）

基于 Claude Code Hooks 机制实现执行过程控制：

| Hook 事件 | 用途 | 响应类型 |
|----------|------|---------|
| SessionStart | 加载项目上下文 | 初始化 |
| PreToolUse | 审批控制 | allow/deny/ask/pending_approval |
| PostToolUse | 检查点验证 | 记录 |
| TaskCreated | 子任务通知 | 记录 |
| TaskCompleted | 完成验证与平台通知 | allow/deny |
| SessionEnd | 保存状态 | 清理 |

### 3. 异步审批机制

支持长时间人工审批流程：

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Claude 尝试执行敏感操作                                    │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. PreToolUse Hook 触发                                      │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 服务器创建审批（立即返回 deny + pending_approval）        │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. [几小时后] 人工审批通过                                    │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. 服务器通过 Channel 通知 Claude                            │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Claude 收到通知，重新执行操作                              │
└─────────────────────────────────────────────────────────────┘
```

### 4. 平台通知

任务完成后自动通知外部平台：

- **GitHub**: 更新 Issue 状态、添加评论
- **Jira**: 更新任务状态、添加工作日志
- **自建平台**: 通用 Webhook 回调

## 📁 项目结构

```
fast-task-for-claude-code/
├── fast-task-claude-plugin/          # Claude Code 插件 (TypeScript)
│   ├── .claude-plugin/
│   │   ├── plugin.json              # 插件配置
│   │   └── hooks.json               # Hook 配置
│   ├── agents/                       # Agent 定义
│   │   ├── product-manager.md       # 产品经理 Agent
│   │   ├── developer.md             # 开发 Agent
│   │   ├── qa-engineer.md           # 测试 Agent
│   │   └── devops-engineer.md       # 运维 Agent
│   ├── scripts/                      # Hook 脚本
│   │   ├── load-context.sh
│   │   └── save-state.sh
│   └── skills/                       # 技能定义（待实现）
│
├── fast-task-server/                 # MCP Channel 服务器 (Python)
│   └── src/
│       ├── webhook/                  # Webhook 接收
│       ├── handlers/                 # Hook 处理器
│       │   ├── pre_tool_use.py      # PreToolUse 处理
│       │   ├── task_created.py      # TaskCreated 处理
│       │   ├── task_completed.py    # TaskCompleted 处理
│       │   └── post_tool_use.py     # PostToolUse 处理
│       ├── approval/                 # 审批管理
│       ├── platforms/                # 平台通知
│       │   ├── github.py
│       │   ├── jira.py
│       │   └── webhook.py
│       └── mcp/                      # MCP 服务
│
└── docs/                             # 文档
    ├── PRD.md                       # 产品需求文档
    ├── ARCHITECTURE.md              # 架构设计文档
    ├── HOOKS.md                     # Hooks 参考文档
    └── EXAMPLES.md                  # 使用示例
```

## 🚀 快速开始

### 前置要求

- Claude Code (最新版本)
- Python 3.10+
- Node.js 18+

### 安装插件

```bash
# 1. 克隆仓库
git clone https://github.com/your-org/fast-task-for-claude-code.git
cd fast-task-for-claude-code

# 2. 安装 Claude Code 插件
claude plugin install ./fast-task-claude-plugin

# 3. 安装 Python 依赖
cd fast-task-server
pip install -r requirements.txt

# 4. 启动 MCP 服务器
python -m uvicorn main:app --host 127.0.0.1 --port 8080
```

### 配置插件

编辑 `~/.claude/plugins/fast-task-channel/user-config.json`:

```json
{
  "server_port": "8080",
  "webhook_token": "your-webhook-token",
  "github_token": "your-github-token",
  "approval_mode": "async"
}
```

### 发送测试任务

```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-webhook-token" \
  -d '{
    "task_id": "test-001",
    "title": "测试任务",
    "description": "这是一个测试任务，请帮我创建一个 Hello World 文件",
    "priority": "low"
  }'
```

## 📖 文档

- [产品需求文档 (PRD)](./docs/PRD.md) - 详细的产品需求和功能说明
- [架构设计文档](./docs/ARCHITECTURE.md) - 系统架构和模块设计
- [Hooks 参考文档](./docs/HOOKS.md) - Claude Code Hooks 事件详解
- [使用示例](./docs/EXAMPLES.md) - 实际使用场景和示例
- [Channels 技术总结](./docs/CHANNELS_TECH_SUMMARY.md) - MCP Channels 技术方案

## 🔗 子模块

本项目包含三个子模块：

- **[fast-task-server](https://github.com/XPDD/fast-task)** - Python 后端服务，提供 MCP Channel、Webhook 接收和审批管理
- **[fast-task-ui](https://github.com/XPDD/fast-task-ui)** - Nuxt 4 前端界面，提供 Web 管理平台
- **[openclaw-plugin-fast-task](https://github.com/XPDD/openclaw-plugin-fast-task)** - OpenClaw 插件，支持节点注册、点对点聊天和 Workspace 文件操作

### 初始化子模块

克隆仓库后，需要初始化子模块：

```bash
git clone https://github.com/XPDD/ClaudeGroup.git
cd ClaudeGroup
git submodule update --init --recursive
```

### 更新子模块

更新子模块到最新版本：

```bash
git submodule update --remote fast-task-server
git submodule update --remote fast-task-ui
git submodule update --remote openclaw-plugin-fast-task
```

## 🔧 技术栈

### 插件部分 (TypeScript)
- Claude Code Plugin System
- MCP (Model Context Protocol)
- Shell Scripts

### 服务器部分 (Python)
- FastAPI - Web 框架
- uvicorn - ASGI 服务器
- Pydantic - 数据验证
- httpx - HTTP 客户端
- python-mcp - MCP SDK
- WebSocket - MCP 传输协议

### 前端部分 (Nuxt + Vue)
- Nuxt 4 - Web 框架
- Vue 3 - UI 框架
- TypeScript - 类型安全
- WebSocket - 实时通信

### OpenClaw 插件 (TypeScript)
- OpenClaw Plugin System
- WebSocket 通信
- 节点注册与发现
- Workspace 文件操作

## 📦 项目结构

```
fast-task-for-claude-code/
├── fast-task-claude-plugin/      # Claude Code 插件
│   ├── agents/                   # Agent 定义（产品/开发/测试/运维）
│   ├── commands/                 # 自定义命令
│   ├── scripts/                  # Hook 脚本
│   ├── skills/                   # 技能包
│   ├── hooks/                    # Hook 配置
│   └── .mcp.json                 # MCP 配置
├── fast-task-server/             # 后端服务（子模块）
│   └── [Python MCP Server]
├── fast-task-ui/                 # 前端界面（子模块）
│   └── [Nuxt 4 Web UI]
├── openclaw-plugin-fast-task/    # OpenClaw 插件（子模块）
│   └── [OpenClaw Plugin]
└── docs/                         # 文档
    ├── PRD.md                    # 产品需求文档
    ├── ARCHITECTURE.md            # 架构设计文档
    ├── HOOKS.md                  # Hooks 参考文档
    ├── EXAMPLES.md              # 使用示例
    └── CHANNELS_TECH_SUMMARY.md # Channels 技术总结
```

## 🎯 设计原则

1. **单一职责**: Channel 只负责任务下发，不包含任务创建方式
2. **异步优先**: 支持长时间审批流程，不阻塞 Claude 执行
3. **平台无关**: 支持多种外部平台（GitHub、Jira、自建平台）
4. **安全可控**: 基于风险等级的审批策略
5. **可扩展性**: 易于添加新的平台和审批策略

## 🛣️ 路线图

### v1.0（当前版本）
- ✅ 基础插件架构
- ✅ MCP Channel 服务器
- ✅ 核心Hooks（SessionStart/End、PreToolUse、TaskCreated、TaskCompleted、PostToolUse）
- ✅ 同步/异步审批机制
- ✅ 基础平台通知

### v1.1（计划中）
- [ ] 完整的平台集成（GitHub、Jira）
- [ ] 审批记录持久化
- [ ] CLI 工具
- [ ] 更多检查点验证

### v2.0（未来）
- [ ] 分布式部署支持
- [ ] 任务优先级调度
- [ ] Web UI 管理界面
- [ ] 多种审批系统集成

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🔗 相关资源

- [Claude Code 官方文档](https://code.claude.com/docs)
- [MCP 协议规范](https://modelcontextprotocol.io/)
- [Claude Code Plugins 参考](https://code.claude.com/docs/zh-CN/plugins-reference)
- [Claude Code Channels 参考](https://code.claude.com/docs/zh-CN/channels-reference)

## 💬 联系方式

- Issues: [GitHub Issues](https://github.com/your-org/fast-task-for-claude-code/issues)
- Discussions: [GitHub Discussions](https://github.com/your-org/fast-task-for-claude-code/discussions)

---

**注意**: 本项目需要 Claude Code 的最新版本才能正常运行。请确保已安装并配置好 Claude Code。
