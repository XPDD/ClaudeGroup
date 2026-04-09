# 架构设计文档 - Issue #1 任务管理系统

**文档版本**: 1.0
**创建日期**: 2026-04-09
**最后更新**: 2026-04-09
**架构师**: Claude Code
**相关文档**:
- [PRD](../prd/prd-1.md) - 产品需求文档
- [数据库设计](../sql/sql-1.sql) - 数据库设计文档（待创建）
- [探索文档](../task/issue-1.md) - 现有功能分析

---

## 📋 文档概述

### 文档目的

本文档描述 ClaudeGroup 任务管理系统的系统架构，为开发团队提供架构层面的指导。

### 适用范围

- **系统**: ClaudeGroup 任务管理系统
- **模块**: 任务管理核心模块
- **层次**: 从数据库到 API 的完整架构

### 参考架构

- **分层架构**: Database → DAO → Service → API
- **设计模式**: Singleton（DAO）、Dependency Injection（Service）
- **通信协议**: HTTP REST API + WebSocket（实时通知）

---

## 🏗️ 系统架构

### 1. 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         客户端层                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Web UI     │  │  Mobile App  │  │  CLI Tool    │          │
│  │ (Nuxt 4/Vue) │  │   (Future)   │  │   (Future)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         API 网关层                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              FastAPI Server (Port 8766)                   │ │
│  │  • REST API • CORS • JWT Auth • Rate Limiting             │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         业务逻辑层                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      Service Layer                         │ │
│  │  ┌──────────────┐  ┌──────────────────┐                   │ │
│  │  │  TaskService │  │ EmployeeTaskService│                   │ │
│  │  │  (User Auth) │  │ (Employee Auth)  │                   │ │
│  │  └──────────────┘  └──────────────────┘                   │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         数据访问层                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                       DAO Layer                            │ │
│  │  ┌──────┐ ┌──────┐ ┌──────────┐ ┌────────┐ ┌─────────┐   │ │
│  │  │ Task │ │ Tag  │ │TaskAssign│ │TaskExec│ │TaskComm│   │ │
│  │  │ DAO  │ │ DAO  │ │   DAO    │ │  DAO   │ │  DAO    │   │ │
│  │  └──────┘ └──────┘ └──────────┘ └────────┘ └─────────┘   │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         数据存储层                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              PostgreSQL Database (Async)                  │ │
│  │  • Tasks • Tags • TaskAssignments • TaskExecutions        │ │
│  │  • TaskComments • Users • UserEnterprises                │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         实时通信层                                │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              WebSocket Server (Port 8765)                 │ │
│  │  • Real-time Notifications • Channel Events              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2. 模块划分

#### 2.1 客户端层（Client Layer）
**职责**: 用户交互界面

**组件**:
- **Web UI**（Nuxt 4 + Vue 3）
  - 任务列表页
  - 任务详情页
  - 任务创建/编辑表单
  - 评论界面
- **Mobile App**（未来）
- **CLI Tool**（未来）

**技术栈**:
- Nuxt 4
- Vue 3
- TypeScript
- WebSocket Client

---

#### 2.2 API 网关层（API Gateway Layer）
**职责**: HTTP 请求处理、认证、路由

**组件**:
- **FastAPI Server**
  - REST API 端点
  - JWT 认证
  - 员工认证
  - CORS 处理
  - 请求验证

**技术栈**:
- FastAPI
- Python 3.10+
- Pydantic（数据验证）

**端口**: `8766`

---

#### 2.3 业务逻辑层（Service Layer）
**职责**: 业务逻辑处理、事务管理

**组件**:
- **TaskService**（用户任务服务）
  - 任务 CRUD
  - 标签管理
  - 任务分配
  - 任务执行

- **EmployeeTaskService**（员工任务服务）
  - 任务 CRUD
  - 标签管理
  - 任务分配
  - 任务执行
  - **评论管理**（核心功能）

**设计模式**:
- 依赖注入（Dependency Injection）
- 上下文管理器（Context Manager）
- 事务管理（Transaction Management）

---

#### 2.4 数据访问层（DAO Layer）
**职责**: 数据库操作、SQL 执行

**组件**:
- **TaskDAO** - 任务数据访问
- **TagDAO** - 标签数据访问
- **TaskAssignmentDAO** - 任务分配数据访问
- **TaskExecutionDAO** - 任务执行记录数据访问
- **TaskCommentDAO** - 任务评论数据访问

**设计模式**:
- **Singleton Pattern**（单例模式）
- **Repository Pattern**（仓储模式）
- **Active Record Pattern**（活动记录模式）

**关键特性**:
```python
# 单例模式访问
await TaskDAO.instance().get_by_id(task_id)

# 上下文管理器（事务）
async with TaskDAO.instance() as dao:
    await dao.create(...)
    await dao.update(...)
    # 自动提交或回滚
```

---

#### 2.5 数据存储层（Database Layer）
**职责**: 数据持久化、数据一致性

**组件**:
- **PostgreSQL Database**
  - 表：tasks, tags, task_assignments, task_executions, task_comments
  - 索引：title, status, priority, created_at
  - 外键：企业隔离
  - 级联删除：标签、评论

**技术栈**:
- PostgreSQL 14+
- SQLAlchemy 2.0（异步 ORM）
- AsyncPG（异步驱动）

---

#### 2.6 实时通信层（Real-time Layer）
**职责**: 实时通知、事件推送

**组件**:
- **WebSocket Server**
  - 任务分配通知
  - 任务关联通知
  - 评论回复通知

**技术栈**:
- Python WebSocket
- FastAPI WebSocket

**端口**: `8765`

---

## 🔧 分层架构详解

### 1. 数据库层（Database Layer）

#### 1.1 表结构
```sql
-- 任务表
CREATE TABLE tasks (
    id VARCHAR(50) PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    priority VARCHAR(20) DEFAULT 'medium',
    status VARCHAR(20) DEFAULT 'pending',
    created_by VARCHAR(50),
    enterprise_id VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tasks_title ON tasks(title);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_created_by ON tasks(created_by);

-- 标签表
CREATE TABLE tags (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    color VARCHAR(20),
    task_id VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- 任务分配表
CREATE TABLE task_assignments (
    id VARCHAR(50) PRIMARY KEY,
    task_id VARCHAR(50) NOT NULL,
    employee_no VARCHAR(50) NOT NULL,
    enterprise_id VARCHAR(50) NOT NULL,
    assigned_by VARCHAR(50),
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes VARCHAR(500),
    status VARCHAR(20) DEFAULT 'pending',
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

CREATE INDEX idx_assignments_task ON task_assignments(task_id);
CREATE INDEX idx_assignments_employee ON task_assignments(employee_no);

-- 任务执行记录表
CREATE TABLE task_executions (
    id VARCHAR(50) PRIMARY KEY,
    task_id VARCHAR(50) NOT NULL,
    employee_no VARCHAR(50) NOT NULL,
    action VARCHAR(20) NOT NULL,
    notes TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

-- 任务评论表
CREATE TABLE task_comments (
    id VARCHAR(50) PRIMARY KEY,
    task_id VARCHAR(50) NOT NULL,
    employee_no VARCHAR(50) NOT NULL,
    enterprise_id VARCHAR(50) NOT NULL,
    content TEXT NOT NULL,
    related_task_id VARCHAR(50),
    parent_comment_id VARCHAR(50),
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_comment_id) REFERENCES task_comments(id)
);

CREATE INDEX idx_comments_task ON task_comments(task_id);
CREATE INDEX idx_comments_employee ON task_comments(employee_no);
```

#### 1.2 ER 图

```
┌──────────────┐
│    tasks     │
├──────────────┤
│ id (PK)      │──┐
│ title        │  │
│ description  │  │
│ priority     │  │
│ status       │  │
│ created_by   │  │
│ enterprise_id│  │
│ created_at   │  │
│ updated_at   │  │
└──────────────┘  │
                   │
      ┌────────────┼────────────┐
      │            │            │
      ▼            ▼            ▼
┌───────────┐ ┌────────────┐ ┌──────────────┐
│   tags    │ │task_assign.│ │task_executions│
├───────────┤ ├────────────┤ ├──────────────┤
│ id (PK)   │ │ id (PK)    │ │ id (PK)      │
│ name      │ │ task_id(FK)│ │ task_id(FK)  │
│ color     │ │ employee_no│ │ employee_no  │
│ task_id(FK)│ │ status     │ │ action       │
│ created_at│ │ assigned_at│ │ executed_at  │
└───────────┘ └────────────┘ └──────────────┘
                   │
                   ▼
            ┌──────────────┐
            │task_comments │
            ├──────────────┤
            │ id (PK)      │
            │ task_id(FK)  │
            │ employee_no  │
            │ content      │
            │ related_task │
            │ parent_comm  │──┐
            │ is_deleted   │  │
            │ created_at   │  │
            │ updated_at   │  │
            └──────────────┘  │
                               │
                               ▼
                        ┌──────────────┐
                        │task_comments │
                        │ (self-ref)   │
                        └──────────────┘
```

---

### 2. DAO 层（Data Access Object Layer）

#### 2.1 基础 DAO 架构
```python
class BaseDAO(Generic[T]):
    """基础 DAO 类"""

    @classmethod
    def instance(cls) -> "BaseDAO[T]":
        """单例模式"""
        pass

    def __init__(self, model_class, session: AsyncSession):
        self.model_class = model_class
        self.session = session

    # 基础 CRUD
    async def create(**kwargs) -> T
    async def get_by_id(id: str) -> Optional[T]
    async def get_by_filter(**kwargs) -> List[T]
    async def update(id: str, **kwargs) -> T
    async def delete(id: str) -> None
    async def count(**kwargs) -> int
```

#### 2.2 具体 DAO 实现

**TaskDAO**:
```python
class TaskDAO(BaseDAO[Task]):
    async def get_with_tags(task_id: str) -> Task
    async def get_by_creator(creator_id: str, **filters) -> List[Task]
    async def search_tasks(keyword: str, **filters) -> List[Task]
    async def get_by_status(status: str) -> List[Task]
    async def get_by_priority(priority: str) -> List[Task]
```

**TaskCommentDAO**:
```python
class TaskCommentDAO(BaseDAO[TaskComment]):
    async def get_by_task(task_id: str, include_deleted: bool) -> List[TaskComment]
    async def get_by_employee(employee_no: str, limit: int) -> List[TaskComment]
    async def get_replies(comment_id: str) -> List[TaskComment]
    async def get_related_comments(related_task_id: str, limit: int) -> List[TaskComment]
    async def soft_delete(comment_id: str) -> bool
```

#### 2.3 DAO 使用模式

**模式 1: 直接调用**（推荐）
```python
task = await TaskDAO.instance().get_by_id("task-123")
```

**模式 2: 上下文管理器**（事务）
```python
async with TaskDAO.instance() as dao:
    await dao.create(id="task-123", title="New Task")
    await dao.update("task-123", status="in_progress")
    # 自动提交或回滚
```

**模式 3: 共享会话**（跨 DAO 事务）
```python
async with get_db_client().get_session() as session:
    task_dao = TaskDAO(session=session)
    comment_dao = TaskCommentDAO(session=session)
    # 两个 DAO 共享同一个会话和事务
```

---

### 3. 服务层（Service Layer）

#### 3.1 服务架构

**TaskService**（用户任务服务）:
```python
class TaskService:
    """用户任务服务（JWT 认证）"""

    def __init__(self, session, current_user_id, employee, enterprise_id):
        self.session = session
        self.current_user_id = current_user_id
        self.employee = employee
        self.enterprise_id = enterprise_id

        # DAOs
        self.task_dao = TaskDAO(session=session)
        self.tag_dao = TagDAO(session=session)
        self.assignment_dao = TaskAssignmentDAO(session=session)

    # 任务 CRUD
    async def create_task(dto) -> Task
    async def get_task(task_id: str) -> Task
    async def update_task(task_id: str, dto) -> Task
    async def delete_task(task_id: str) -> None
    async def list_tasks(page, page_size, query) -> Tuple[List[Task], int]

    # 标签管理
    async def add_tag(task_id: str, dto) -> Tag
    async def remove_tag(tag_id: str) -> None
    async def get_task_tags(task_id: str) -> List[Tag]

    # 任务分配
    async def assign_task(task_id: str, dto, assigned_by: str) -> List[TaskAssignment]
    async def unassign_task(task_id: str, employee_nos: List[str]) -> int

    # 任务执行
    async def start_task(task_id: str, dto) -> Task
    async def complete_task(task_id: str, dto) -> Task
```

**EmployeeTaskService**（员工任务服务）:
```python
class EmployeeTaskService:
    """员工任务服务（员工认证）"""

    def __init__(self, session, employee: UserEnterprise):
        self.session = session
        self.employee = employee
        self.employee_no = employee.employee_no
        self.user_id = employee.user_id
        self.enterprise_id = employee.enterprise_id

        # DAOs
        self.task_dao = TaskDAO(session=session)
        self.tag_dao = TagDAO(session=session)
        self.assignment_dao = TaskAssignmentDAO(session=session)
        self.comment_dao = TaskCommentDAO(session=session)

    # 任务 CRUD（与 TaskService 类似）
    async def create_task(dto) -> Task
    async def get_task(task_id: str) -> Task
    # ... 其他方法

    # **评论管理**（核心功能）
    async def add_comment(task_id: str, dto) -> TaskComment
    async def get_task_comments(task_id: str, include_replies: bool) -> List[TaskComment]
    async def update_comment(comment_id: str, dto) -> TaskComment
    async def delete_comment(comment_id: str) -> None
    async def get_related_task_comments(task_id: str, limit: int) -> List[TaskComment]
    async def get_my_comments(page: int, page_size: int) -> Tuple[List[TaskComment], int]
```

#### 3.2 服务层特性

**依赖注入**:
```python
async def get_task_service(
    request: Request,
    current_user: User = Depends(get_current_user_from_state)
) -> AsyncGenerator[TaskService, None]:
    async with get_db_client().get_session() as session:
        try:
            yield TaskService(session, current_user.id, employee, enterprise_id)
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

**事务管理**:
- 自动提交：正常执行时提交
- 自动回滚：异常时回滚
- 会话管理：使用完毕后自动关闭

---

### 4. API 层（API Layer）

#### 4.1 路由架构

**任务管理路由**（`/api/tasks/`）:
```python
router = APIRouter(prefix="/api/tasks", tags=["任务管理"])

# 任务 CRUD
POST   /api/tasks/                    # 创建任务
GET    /api/tasks/                    # 获取任务列表（分页）
GET    /api/tasks/{task_id}           # 获取任务详情
PUT    /api/tasks/{task_id}           # 更新任务
DELETE /api/tasks/{task_id}           # 删除任务

# 标签管理
POST   /api/tasks/{task_id}/tags      # 添加标签
GET    /api/tasks/{task_id}/tags      # 获取任务标签
DELETE /api/tasks/tags/{tag_id}       # 删除标签

# 任务分配
POST   /api/tasks/{task_id}/assign-by-employee-no    # 分配任务（工号）
POST   /api/tasks/{task_id}/assign-by-user-id        # 分配任务（用户ID）
DELETE /api/tasks/{task_id}/assign                   # 取消分配
GET    /api/tasks/{task_id}/assignments              # 获取分配列表

# 任务执行
POST   /api/tasks/{task_id}/start       # 开始任务
POST   /api/tasks/{task_id}/complete    # 完成任务
GET    /api/tasks/{task_id}/executions  # 获取执行记录

# 员工任务
GET    /api/tasks/my/assigned           # 获取分配给我的任务
```

**员工任务路由**（待添加）:
```python
router = APIRouter(prefix="/api/employee/tasks", tags=["员工任务管理"])

# **评论管理**（核心功能，待实现）
POST   /api/employee/tasks/{task_id}/comments              # 添加评论
GET    /api/employee/tasks/{task_id}/comments              # 获取评论列表
PUT    /api/employee/comments/{comment_id}                 # 更新评论
DELETE /api/employee/comments/{comment_id}                 # 删除评论
GET    /api/employee/tasks/{task_id}/related-comments      # 获取关联评论
GET    /api/employee/comments/my                           # 获取我的评论
```

#### 4.2 API 设计规范

**RESTful 设计**:
- 使用标准 HTTP 方法（GET, POST, PUT, DELETE）
- 资源命名使用名词复数（`/api/tasks/`）
- 使用路径参数标识资源（`{task_id}`, `{comment_id}`）
- 使用查询参数进行筛选（`?page=1&pageSize=10`）

**统一响应格式**:
```python
# 成功响应
{
  "success": true,
  "code": 200,
  "message": "操作成功",
  "data": { ... }
}

# 错误响应
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "错误描述",
    "details": { ... },
    "path": "/api/endpoint",
    "method": "GET"
  }
}
```

**分页响应**:
```python
{
  "success": true,
  "data": {
    "items": [ ... ],
    "total": 100,
    "page": 1,
    "pageSize": 10,
    "totalPages": 10
  }
}
```

---

### 5. 通知层（Notification Layer）

#### 5.1 WebSocket 通知架构

```python
class TaskNotificationService:
    """任务通知服务（单例）"""

    async def notify_task_assigned(
        employee_no: str,
        task_id: str,
        task_title: str,
        assigned_by: str,
        notes: Optional[str]
    ):
        """通知员工：任务已分配"""
        # 通过 WebSocket 推送消息
        message = {
            "type": "task_assigned",
            "data": {
                "task_id": task_id,
                "task_title": task_title,
                "assigned_by": assigned_by,
                "notes": notes
            }
        }
        await self.websocket_manager.send_to_employee(employee_no, message)

    async def notify_task_related(
        employee_no: str,
        task_id: str,
        task_title: str,
        related_task_id: str,
        related_task_title: str,
        commenter: str,
        comment_preview: str
    ):
        """通知员工：任务被关联"""
        message = {
            "type": "task_related",
            "data": {
                "task_id": task_id,
                "task_title": task_title,
                "related_task_id": related_task_id,
                "related_task_title": related_task_title,
                "commenter": commenter,
                "comment_preview": comment_preview
            }
        }
        await self.websocket_manager.send_to_employee(employee_no, message)
```

#### 5.2 通知触发时机

**任务分配通知**:
- 触发：`TaskService.assign_task_by_employee_no()`
- 接收者：被分配的员工
- 内容：任务标题、分配人、分配备注

**任务关联通知**:
- 触发：`EmployeeTaskService.add_comment()`（评论中关联其他任务）
- 接收者：被关联任务的被分配员工
- 内容：评论者、评论内容、关联任务

---

## 🔐 权限控制架构

### 1. 双认证体系

#### 1.1 用户认证（JWT）
```python
# 依赖注入
async def get_current_user_from_state(
    request: Request
) -> User:
    """从请求状态中获取当前用户"""
    token = request.headers.get("Authorization")
    if not token:
        raise UnauthorizedException("缺少认证令牌")

    # 验证 JWT token
    user = verify_token(token)
    if not user:
        raise UnauthorizedException("无效的令牌")

    return user

# 使用
@router.get("/api/tasks/")
async def list_tasks(
    current_user: User = Depends(get_current_user_from_state)
):
    # current_user 是已认证的用户
    pass
```

#### 1.2 员工认证（工号 + 登录口令）
```python
# 依赖注入
async def get_current_employee_from_state(
    request: Request
) -> UserEnterprise:
    """从请求状态中获取当前员工"""
    employee_no = request.headers.get("X-Employee-No")
    login_token = request.headers.get("X-Employee-Token")

    if not employee_no or not login_token:
        raise UnauthorizedException("缺少员工认证信息")

    # 验证员工身份
    employee = verify_employee(employee_no, login_token)
    if not employee:
        raise UnauthorizedException("无效的员工认证")

    return employee

# 使用
@router.post("/api/employee/tasks/{task_id}/comments")
async def add_comment(
    task_id: str,
    dto: CommentCreateRequest,
    employee: UserEnterprise = Depends(get_current_employee_from_state)
):
    # employee 是已认证的员工
    pass
```

---

### 2. 权限检查矩阵

| 操作 | 创建者检查 | 分配检查 | 企业隔离检查 |
|------|-----------|---------|------------|
| 查看任务 | ✅ | ✅ | ✅ |
| 更新任务 | ✅ | ✅ | ✅ |
| 删除任务 | ✅ | ❌ | ✅ |
| 分配任务 | ✅ | ❌ | ✅ |
| 开始任务 | ❌ | ✅ | ✅ |
| 完成任务 | ❌ | ✅ | ✅ |
| 添加评论 | ❌ | ✅ | ✅ |
| 更新评论 | ❌ | ✅（自己的） | ✅ |
| 删除评论 | ❌ | ✅（自己的） | ✅ |

**实现示例**:
```python
async def get_task(task_id: str) -> Task:
    task = await self.task_dao.get_by_id(task_id)
    if not task:
        raise NotFoundException(f"任务不存在: {task_id}")

    # 企业隔离检查
    if task.enterprise_id and task.enterprise_id != self.enterprise_id:
        raise BadRequestException("无权访问此任务")

    # 权限检查：创建者或被分配员工
    is_assigned = await self.assignment_dao.is_assigned(task_id, self.employee_no)
    if task.created_by != self.user_id and not is_assigned:
        raise BadRequestException("无权访问此任务")

    return task
```

---

## 🚀 接口设计

### 1. REST API 规范

#### 1.1 URL 设计
```
# 资源命名（名词复数）
/api/tasks/
/api/tags/
/api/comments/

# 层级关系
/api/tasks/{task_id}/tags
/api/tasks/{task_id}/assignments
/api/tasks/{task_id}/comments

# 特殊操作
/api/tasks/my/assigned          # 我的任务
/api/comments/my                # 我的评论
```

#### 1.2 HTTP 方法
```
GET    /api/tasks/               # 查询列表
GET    /api/tasks/{id}           # 查询单个
POST   /api/tasks/               # 创建资源
PUT    /api/tasks/{id}           # 更新资源
DELETE /api/tasks/{id}           # 删除资源
PATCH  /api/tasks/{id}           # 部分更新（可选）
```

#### 1.3 状态码
```
200  OK                          # 成功
201  Created                     # 创建成功
204  No Content                  # 删除成功
400  Bad Request                 # 参数错误
401  Unauthorized                # 未认证
403  Forbidden                   # 无权限
404  Not Found                   # 资源不存在
500  Internal Server Error       # 服务器错误
```

---

### 2. 请求/响应格式

#### 2.1 请求格式
**创建任务**:
```http
POST /api/tasks/ HTTP/1.1
Content-Type: application/json
Authorization: Bearer <token>

{
  "title": "修复登录页面崩溃",
  "description": "用户反馈在 iOS 15 上登录后崩溃",
  "priority": "high"
}
```

**查询任务**:
```http
GET /api/tasks/?page=1&pageSize=10&keyword=登录&priority=high HTTP/1.1
Authorization: Bearer <token>
```

#### 2.2 响应格式
**成功响应**:
```json
{
  "success": true,
  "code": 200,
  "message": "任务创建成功",
  "data": {
    "id": "task-123",
    "title": "修复登录页面崩溃",
    "description": "用户反馈在 iOS 15 上登录后崩溃",
    "priority": "high",
    "status": "pending",
    "created_at": "2026-04-09T10:00:00Z",
    "updated_at": "2026-04-09T10:00:00Z",
    "tags": [],
    "assignments": []
  }
}
```

**错误响应**:
```json
{
  "success": false,
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "任务不存在: task-123",
    "details": {},
    "path": "/api/tasks/task-123",
    "method": "GET"
  }
}
```

---

### 3. DTO 设计

#### 3.1 请求 DTO
```python
class TaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=2000)
    priority: str = Field("medium", pattern="^(high|medium|low)$")

class CommentCreateRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=2000)
    related_task_id: Optional[str] = None
    parent_comment_id: Optional[str] = None
```

#### 3.2 响应 DTO
```python
class TaskDTO(BaseModel):
    id: str
    title: str
    description: Optional[str]
    priority: str
    status: str
    created_at: str  # ISO 8601 格式
    updated_at: str
    tags: List[TagDTO]
    assignments: List[AssignmentDTO]

    @classmethod
    def from_task(cls, task, **kwargs) -> "TaskDTO":
        return cls(
            id=task.id,
            title=task.title,
            # ... 其他字段
        )
```

---

## 📡 扩展性设计

### 1. 如何添加新功能

#### 1.1 添加新数据模型
```python
# 1. 在 models.py 中定义模型
class Milestone(Base):
    __tablename__ = "milestones"
    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    # ... 其他字段

# 2. 创建 DAO
class MilestoneDAO(BaseDAO[Milestone]):
    @classmethod
    def _get_model_class(cls):
        return Milestone

# 3. 导出 DAO
# 在 dao/__init__.py 中添加
from .milestone_dao import MilestoneDAO
```

#### 1.2 添加新 API 端点
```python
# 1. 创建路由文件
# fast-task-server/src/api/routes/milestones.py
router = APIRouter(prefix="/api/milestones", tags=["里程碑管理"])

@router.post("/")
async def create_milestone(
    dto: MilestoneCreateRequest,
    service: MilestoneService = Depends(get_milestone_service)
):
    pass

# 2. 注册路由
# 在 app.py 中添加
from api.routes.milestones import router as milestones_router
app.include_router(milestones_router)
```

#### 1.3 添加新服务
```python
# 1. 创建服务类
class MilestoneService:
    def __init__(self, session, current_user_id):
        self.session = session
        self.milestone_dao = MilestoneDAO(session=session)

    async def create_milestone(self, dto) -> Milestone:
        pass

# 2. 创建依赖注入
async def get_milestone_service(
    current_user: User = Depends(get_current_user_from_state)
) -> AsyncGenerator[MilestoneService, None]:
    async with get_db_client().get_session() as session:
        try:
            yield MilestoneService(session, current_user.id)
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

---

### 2. 插件化架构

#### 2.1 Hook 机制
```python
# 定义 Hook
class TaskHook:
    async def on_task_created(self, task: Task):
        """任务创建后触发"""
        pass

    async def on_task_assigned(self, assignment: TaskAssignment):
        """任务分配后触发"""
        pass

    async def on_task_completed(self, task: Task):
        """任务完成后触发"""
        pass

# 注册 Hook
task_hooks = []

# 触发 Hook
async def notify_hooks(event: str, **kwargs):
    for hook in task_hooks:
        if event == "task_created":
            await hook.on_task_created(**kwargs)
        elif event == "task_assigned":
            await hook.on_task_assigned(**kwargs)
```

#### 2.2 中间件机制
```python
# 添加中间件
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """记录所有请求"""
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time
    log.info(f"{request.method} {request.url} - {response.status_code} - {duration:.2f}s")
    return response
```

---

## 📊 性能优化

### 1. 数据库优化

#### 1.1 索引优化
```sql
-- 常用查询字段建立索引
CREATE INDEX idx_tasks_title ON tasks(title);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_created_by ON tasks(created_by);

-- 复合索引
CREATE INDEX idx_tasks_status_priority ON tasks(status, priority);
CREATE INDEX idx_assignments_task_employee ON task_assignments(task_id, employee_no);
```

#### 1.2 查询优化
```python
# 使用预加载（Eager Loading）
async def get_task_with_tags(task_id: str) -> Task:
    query = select(Task).where(Task.id == task_id).options(
        selectinload(Task.tags)
    )
    result = await session.execute(query)
    return result.scalar_one_or_none()

# 批量查询
async def get_tasks_with_assignments(task_ids: List[str]) -> Dict[str, List[TaskAssignment]]:
    query = select(TaskAssignment).where(TaskAssignment.task_id.in_(task_ids))
    result = await session.execute(query)
    assignments = result.scalars().all()

    # 按任务ID分组
    assignments_map = defaultdict(list)
    for assignment in assignments:
        assignments_map[assignment.task_id].append(assignment)

    return assignments_map
```

#### 1.3 分页优化
```python
# 使用游标分页（大数据量）
async def list_tasks_cursor(
    last_id: Optional[str] = None,
    limit: int = 20
) -> List[Task]:
    query = select(Task).order_by(Task.id)

    if last_id:
        query = query.where(Task.id > last_id)

    query = query.limit(limit)
    result = await session.execute(query)
    return list(result.scalars().all())
```

---

### 2. API 性能优化

#### 2.1 响应压缩
```python
from fastapi.middleware.gzip import GZipMiddleware

app.add_middleware(GZipMiddleware, minimum_size=1000)
```

#### 2.2 缓存机制
```python
from functools import lru_cache

@lru_cache(maxsize=128)
async def get_task_tags_cached(task_id: str) -> List[Tag]:
    """缓存任务标签"""
    return await TaskDAO.instance().get_task_tags(task_id)

# 或使用 Redis
import redis

redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

async def get_task_with_cache(task_id: str) -> Optional[Task]:
    # 先查缓存
    cache_key = f"task:{task_id}"
    cached = redis_client.get(cache_key)
    if cached:
        return Task.parse_raw(cached)

    # 查数据库
    task = await TaskDAO.instance().get_by_id(task_id)
    if task:
        # 写入缓存
        redis_client.setex(cache_key, 3600, task.json())

    return task
```

---

## 📝 附录

### A. 技术栈总结

| 层次 | 技术栈 | 版本 |
|------|--------|------|
| 客户端 | Nuxt 4, Vue 3, TypeScript | Latest |
| API 网关 | FastAPI, Python | 3.10+ |
| 业务逻辑 | Python, AsyncIO | 3.10+ |
| 数据访问 | SQLAlchemy, AsyncPG | 2.0+ |
| 数据存储 | PostgreSQL | 14+ |
| 实时通信 | WebSocket, Python | 3.10+ |

---

### B. 设计模式总结

| 模式 | 应用场景 | 实现位置 |
|------|---------|---------|
| Singleton | DAO 实例管理 | `BaseDAO.instance()` |
| Dependency Injection | Service 依赖注入 | `get_task_service()` |
| Repository | 数据访问抽象 | DAO Layer |
| Factory | 数据库会话创建 | `get_db_client()` |
| Observer | WebSocket 通知 | `TaskNotificationService` |

---

### C. 相关文档

- [PRD](../prd/prd-1.md) - 产品需求文档
- [数据库设计](../sql/sql-1.sql) - 数据库设计文档（待创建）
- [探索文档](../task/issue-1.md) - 现有功能分析
- [开发指南](../../fast-task-server/CLAUDE.md) - 开发规范

---

### D. 下一步

- [ ] 创建数据库设计文档（Issue #4）
- [ ] 实现评论 API 路由（Issue #5）
- [ ] 编写测试脚本（Issue #7）

---

**文档状态**: ✅ 完成
**审核状态**: 待审核
**下一步**: 数据库设计文档
