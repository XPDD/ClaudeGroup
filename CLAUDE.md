# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ClaudeGroup** is a Claude Code plugin system that provides task channel and execution control capabilities through MCP (Model Context Protocol).

The project consists of two main components:

1. **fast-task-claude-plugin** - Claude Code plugin (TypeScript configuration)
   - Defines agents, commands, skills, and hooks
   - Contains Shell scripts for hook processing
   - Configures MCP server connection

2. **fast-task-server** - MCP Channel server (Python, git submodule)
   - HTTP Webhook endpoint for receiving tasks
   - Hook callback handlers for execution control
   - Approval management system
   - Platform notification integrations (GitHub, Jira)

### Core Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         ClaudeGroup                             │
├─────────────────────────────────────────────────────────────────┤
│  Plugin Layer (TS Config)     │  Server Layer (Python)          │
│  ┌─────────────────────────┐  │  ┌─────────────────────────┐   │
│  │ Agents (6 domain agents)│  │  │ Webhook Receiver       │   │
│  │ Commands                │  │  │ Hook Handlers          │   │
│  │ Skills                  │  │  │ Approval Manager       │   │
│  │ Hooks Config            │  │  │ Platform Notifiers     │   │
│  └─────────────────────────┘  │  └─────────────────────────┘   │
│             │                  │              │                 │
└─────────────┼──────────────────┴──────────────┼─────────────────┘
              │                                 │
              │ MCP stdio                       │ HTTP/Webhook
              ▼                                 ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│      Claude Code        │     │      External Systems            │
│  • Receives tasks        │     │  • GitHub Issues               │
│  • Executes tasks        │     │  • Jira                        │
│  • Triggers hooks        │     │  • CI/CD (Jenkins/GitLab)      │
│  • Gets approvals        │     │  • Approval Systems            │
└─────────────────────────┘     └─────────────────────────────────┘
```

## Key Concepts

### Async Approval Mechanism

The plugin supports long-running approval workflows (hours to days) using a **deny + Channel notification** pattern:

1. Claude attempts sensitive operation
2. PreToolUse Hook triggers → HTTP POST to server
3. Server creates approval record, returns `deny + pending_approval`
4. [Hours later] Human approval completed
5. Server sends Channel notification to Claude
6. Claude receives notification, re-executes operation

**Critical**: The Hook returns `deny` immediately (no waiting). Approval happens asynchronously via Channel.

### Risk-Based Approval Strategy

| Risk Level | Operations | Approval Mode |
|------------|------------|---------------|
| Low | Read, Grep, file viewing | Auto allow |
| Medium | Normal file editing | Sync approval (<30s) |
| High | `rm -rf`, production deployment | Async approval (manual) |

### Hook Events

The plugin uses these Claude Code Hooks:

| Hook | Purpose | Response Type |
|------|---------|---------------|
| SessionStart | Load project context, init state | None (init only) |
| PreToolUse | Approval control | allow/deny/ask/pending_approval |
| PostToolUse | Checkpoint validation, progress | None (log only) |
| TaskCreated | Subtask notification | None (log only) |
| TaskCompleted | Completion verification, platform notify | allow/deny |
| SessionEnd | Save state, cleanup | None (cleanup) |

### Agent System

Six specialized agents for different domains:

- **product-manager**: Requirements analysis, task breakdown, acceptance criteria
- **developer**: Technical design, code implementation, code review
- **qa-engineer**: Testing strategy, test cases, quality assurance
- **devops-engineer**: Deployment, monitoring, troubleshooting, CI/CD
- **task-executor**: Task execution expert, executes operations and verifies results
- **code-reviewer**: Code quality review, security checks, best practices

## Quick Start Commands

### Plugin Development

```bash
# Install the plugin in Claude Code
claude plugin install ./fast-task-claude-plugin

# Test hook scripts manually
./fast-task-claude-plugin/scripts/load-context.sh < test-input.json
./fast-task-claude-plugin/scripts/save-state.sh < test-input.json
./fast-task-claude-plugin/scripts/on-dir-change.sh < test-input.json

# Validate plugin configuration
claude plugin validate ./fast-task-claude-plugin
```

### Python Server (fast-task-server)

```bash
# Navigate to server directory
cd fast-task-server

# Install dependencies
uv sync
# OR: pip install -r requirements.txt

# Start MCP server (default: both WebSocket + FastAPI)
python start.py

# Initialize database
python scripts/init_db.py

# Run tests
python scripts/test_user_api.py

# API docs (start server first)
open http://localhost:8766/docs
```

### Server Configuration

Edit `fast-task-server/config.yaml`:

```yaml
startup:
  mode: "both"  # "both", "websocket", or "api"
  websocket_first: true

server:
  websocket:
    port: 8765
  api:
    port: 8766

database:
  url: "postgresql+asyncpg://user:pass@localhost:5432/db"
```

### Testing the Full System

```bash
# 1. Start MCP server
cd fast-task-server && python start.py

# 2. Send test webhook
curl -X POST http://localhost:8766/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "test-001",
    "title": "Test Task",
    "description": "This is a test task",
    "priority": "low"
  }'

# 3. Check hook callbacks are received
# Monitor server logs for POST /hooks/* requests
```

## Architecture Details

### Plugin Configuration Structure

**`fast-task-claude-plugin/.claude-plugin/plugin.json`**:
- Defines plugin metadata
- Registers agents, commands, skills
- References hooks config and MCP servers config
- Defines userConfig schema (server_port, webhook_token, github_token, etc.)

**`fast-task-claude-plugin/hooks/hooks.json`**:
- Maps Hook events to HTTP callbacks
- Uses `${user_config.server_port}` variable substitution
- Configures timeouts for each hook

**`fast-task-claude-plugin/.mcp.json`**:
- Defines MCP server startup command
- Passes userConfig as environment variables
- Sets PYTHONPATH to fast-task-server/src

### Server Architecture (fast-task-server)

The Python server is a **dual-server application**:

1. **WebSocket Server** (`src/im/`):
   - Real-time bidirectional messaging
   - Message routing by `"type"` field to handler classes
   - Handlers in `src/im/handlers/`: ping, echo, broadcast, auth, etc.

2. **FastAPI Server** (`src/api/`):
   - REST API endpoints
   - JWT authentication (manual verification in dependencies)
   - OpenAPI docs at `/docs`

**CRITICAL: DAO Singleton Pattern**

All DAOs MUST be accessed via `.instance()`:

```python
# ✅ CORRECT
from dao import ClientDAO, UserDAO

client = await ClientDAO.instance().get_by_id("client-123")
user = await UserDAO.instance().get_by_name("alice")

# ❌ WRONG
dao = ClientDAO()  # Bypasses singleton
```

**Three DAO usage patterns**:

1. Direct call (single operations):
   ```python
   client = await ClientDAO.instance().get_by_id("client-123")
   ```

2. Context manager (transactional):
   ```python
   async with ClientDAO.instance() as dao:
       await dao.create(id="c1", config={}, is_online=True)
       await dao.update("c1", is_online=False)
   # Auto commits on success, rolls back on exception
   ```

3. Shared session (cross-DAO transactions):
   ```python
   from database.client import get_db_client

   async with get_db_client().get_session() as session:
       client_dao = ClientDAO(session=session)
       user_dao = UserDAO(session=session)
       # Both DAOs share the same session/transaction
   ```

### Key DAO Classes

- `ClientDAO` - WebSocket client connections
- `UserDAO` - User accounts with authentication
- `SessionDAO` - User sessions/tokens
- `MessageDAO` - Message history

### Authentication System

Authentication is **NOT handled by global middleware**. Each protected route uses a dependency:

```python
from api.dependencies import get_current_user_from_state, noauth
from database.models import User

# Protected endpoint
@router.get("/protected")
async def protected(current_user: User = Depends(get_current_user_from_state)):
    return {"user": current_user.name}

# Public endpoint
@router.get("/public")
@noauth
async def public():
    return {"message": "No auth required"}
```

**Key authentication files**:
- `src/api/auth.py` - JWT token creation/verification
- `src/api/dependencies.py` - `get_current_user_from_state()` dependency
- `src/api/routes/auth_jwt.py` - Auth endpoints
- `src/api/routes/users_jwt.py` - User management

## Adding Features

### Adding a New Agent

1. Create agent file in `fast-task-claude-plugin/agents/{agent-name}.md`
2. Add frontmatter with metadata:
   ```yaml
   ---
   name: agent-name
   description: Brief description
   model: sonnet
   effort: medium
   maxTurns: 30
   ---
   ```
3. Register in `plugin.json`:
   ```json
   "agents": ["./agents/{agent-name}.md"]
   ```

### Adding a New Hook Handler (Python)

1. Create handler in `fast-task-server/src/handlers/{hook_name}.py`
2. Register route in FastAPI app (`src/api/` or `src/app.py`):
   ```python
   @app.post("/hooks/{hook-name}")
   async def handle_hook(request: HookRequest):
       # Process hook
       return {"decision": "allow"}
   ```
3. Add hook configuration in `hooks/hooks.json`:
   ```json
   "{HookEvent}": [{
     "hooks": [{
       "type": "http",
       "url": "http://127.0.0.1:${user_config.server_port}/hooks/{hook-name}"
     }]
   }]
   ```

### Adding Platform Notification

1. Create notifier in `fast-task-server/src/platforms/{platform}.py`
2. Implement notification interface
3. Register in `src/handlers/task_completed.py`
4. Add platform-specific userConfig to `plugin.json`

## Important Files

### Plugin Files

- `fast-task-claude-plugin/.claude-plugin/plugin.json` - Plugin manifest
- `fast-task-claude-plugin/hooks/hooks.json` - Hook event mappings
- `fast-task-claude-plugin/.mcp.json` - MCP server configuration
- `fast-task-claude-plugin/scripts/*.sh` - Hook processing scripts
- `fast-task-claude-plugin/agents/*.md` - Agent definitions
- `fast-task-claude-plugin/commands/*.md` - Command definitions
- `fast-task-claude-plugin/skills/*/SKILL.md` - Skill definitions

### Server Files (fast-task-server)

- `src/app.py` - Dual server initialization
- `src/im/` - WebSocket server and message handlers
- `src/api/` - FastAPI routes and authentication
- `src/dao/` - Data access objects (singleton pattern)
- `src/database/models.py` - SQLAlchemy models
- `src/database/client.py` - Database connection management
- `config.yaml` - Server configuration

### Documentation

- `docs/PRD.md` - Product requirements document
- `docs/ARCHITECTURE.md` - Architecture design details
- `docs/HOOKS.md` - Complete Hooks reference
- `docs/EXAMPLES.md` - Usage examples
- `fast-task-server/CLAUDE.md` - Python server architecture

## Environment Variables

The plugin injects these environment variables into the MCP server:

- `WEBHOOK_PORT` - Server port (default: 8080)
- `WEBHOOK_TOKEN` - Webhook authentication token
- `GITHUB_TOKEN` - GitHub Personal Access Token
- `JIRA_URL` - Jira server URL
- `JIRA_EMAIL` - Jira email
- `JIRA_TOKEN` - Jira API Token
- `APPROVAL_MODE` - Approval mode (auto/sync/async)
- `PLUGIN_DATA` - Plugin data directory path
- `PYTHONPATH` - Points to `fast-task-server/src`

## Git Submodule

`fast-task-server/` is a git submodule pointing to `https://github.com/XPDD/fast-task.git`

**Updating the submodule**:
```bash
git submodule update --remote fast-task-server
git add fast-task-server
git commit -m "Update fast-task-server submodule"
```

**Cloning with submodules**:
```bash
git clone --recursive https://github.com/XPDD/ClaudeGroup.git
# OR after cloning:
git submodule update --init --recursive
```

## Design Principles

1. **Single Responsibility**: Channel only handles task delivery, not task creation
2. **Async First**: Support long-running approval workflows without blocking
3. **Platform Agnostic**: Support multiple external platforms (GitHub, Jira, custom)
4. **Security First**: Risk-based approval strategy
5. **Extensibility**: Easy to add new platforms and approval strategies
