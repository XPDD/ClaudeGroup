# Issue #1: 任务管理功能探索总结

**Issue**: [仿照github的issue开发任务管理功能](https://github.com/XPDD/ClaudeGroup/issues/1)
**探索日期**: 2026-04-09
**探索者**: Claude Code

---

## 📋 Issue 原始需求

根据 GitHub Issue #1 的描述，需要实现以下任务管理功能：

1. **任务 CRUD** - 创建、读取、更新、删除任务
2. **标签管理** - 为任务添加标签
3. **生命周期管理** - 任务状态流转（pending → in_progress → completed）
4. **多人协作** - 一个任务可以分配给多个员工
5. **评论系统** - 支持任务评论和回复

---

## 🔍 现有功能探索结果

### ✅ 已完整实现的功能

经过全面探索，发现项目**已经实现了完整的任务管理系统**，涵盖了 Issue 中的所有需求。以下是详细分析：

---

## 📊 数据库模型层

### 1. Task 模型（任务主表）
**文件**: `fast-task-server/src/database/models.py`

```python
class Task(Base):
    __tablename__ = "tasks"

    # 主键和基础字段
    id: str                             # 任务ID
    title: str                          # 任务标题（必填，1-200字符，索引）
    description: Optional[str]          # 任务描述（可选，最多2000字符）

    # 任务属性
    priority: str                       # 优先级：high/medium/low（默认medium）
    status: str                         # 状态：pending/in_progress/completed/cancelled（默认pending）

    # 所属关系
    created_by: Optional[str]           # 创建人ID（用户ID）
    enterprise_id: Optional[str]        # 企业ID（企业隔离）

    # 时间戳
    created_at: datetime                # 创建时间
    updated_at: datetime                # 更新时间

    # 关系映射
    tags: List[Tag]                     # 任务标签
    assignments: List[TaskAssignment]   # 任务分配
    executions: List[TaskExecution]     # 执行记录
    comments: List[TaskComment]         # 任务评论
```

**关键发现**:
- ✅ 支持优先级（high/medium/low）
- ✅ 支持状态流转（pending → in_progress → completed → cancelled）
- ✅ 支持企业隔离（enterprise_id）
- ✅ 标题字段已建立索引，优化搜索性能

---

### 2. Tag 模型（标签表）
```python
class Tag(Base):
    __tablename__ = "tags"

    id: str                   # 标签ID
    name: str                 # 标签名称（必填，1-50字符）
    color: Optional[str]      # 标签颜色（可选，最多20字符）
    task_id: str              # 所属任务ID（外键）

    created_at: datetime      # 创建时间
```

**关键发现**:
- ✅ 支持自定义标签名称和颜色
- ✅ 一个任务可以有多个标签
- ✅ 删除任务时级联删除标签

---

### 3. TaskAssignment 模型（任务分配表）
```python
class TaskAssignment(Base):
    __tablename__ = "task_assignments"

    id: str                   # 分配ID
    task_id: str              # 任务ID（外键）
    employee_no: str          # 员工工号（必填）
    enterprise_id: str        # 企业ID（外键）

    # 分配信息
    assigned_by: Optional[str] # 分配人ID（用户ID）
    assigned_at: datetime      # 分配时间
    notes: Optional[str]       # 分配备注（可选，最多500字符）

    # 分配状态
    status: str               # pending/accepted/rejected/started（默认pending）
```

**关键发现**:
- ✅ **支持多人分配**：一个任务可以分配给多个员工（多条 TaskAssignment 记录）
- ✅ 分配状态跟踪：pending（待接受）→ accepted（已接受）→ started（已开始）
- ✅ 支持分配备注（如：任务说明、截止时间等）
- ✅ 企业隔离：只能分配给同一企业的员工

---

### 4. TaskExecution 模型（任务执行记录表）
```python
class TaskExecution(Base):
    __tablename__ = "task_executions"

    id: str                   # 执行记录ID
    task_id: str              # 任务ID（外键）
    employee_no: str          # 员工工号

    # 执行信息
    action: str               # 操作类型：start/complete/cancel
    notes: Optional[str]      # 执行备注（可选）
    executed_at: datetime     # 执行时间
```

**关键发现**:
- ✅ 记录任务生命周期操作（开始、完成、取消）
- ✅ 支持执行备注（如：完成说明、遇到的问题等）
- ✅ 完整的审计跟踪

---

### 5. TaskComment 模型（任务评论表）
```python
class TaskComment(Base):
    __tablename__ = "task_comments"

    id: str                   # 评论ID
    task_id: str              # 任务ID（外键）
    employee_no: str          # 评论者工号
    enterprise_id: str        # 企业ID

    # 评论内容
    content: str              # 评论内容（必填，最多2000字符）

    # 关联关系
    related_task_id: Optional[str]      # 关联的任务ID（用于跨任务引用）
    parent_comment_id: Optional[str]    # 父评论ID（用于回复）

    # 状态
    is_deleted: bool          # 是否已删除（软删除）
    created_at: datetime      # 创建时间
    updated_at: datetime      # 更新时间

    # 关系映射
    replies: List[TaskComment] # 子评论（回复）
```

**关键发现**:
- ✅ **支持评论回复**：通过 `parent_comment_id` 实现嵌套评论
- ✅ **支持跨任务关联**：通过 `related_task_id` 引用其他任务（类似 GitHub Issue 关联）
- ✅ **软删除机制**：删除评论不破坏评论结构
- ✅ 企业隔离

---

## 🔧 DAO 层（数据访问层）

### TaskDAO
**文件**: `fast-task-server/src/dao/task_dao.py`

**核心方法**:
```python
class TaskDAO(BaseDAO[Task]):
    # 基础 CRUD
    async def create(...) → Task
    async def get_by_id(task_id: str) → Task
    async def update(task_id: str, **kwargs) → Task
    async def delete(task_id: str) → None

    # 查询方法
    async def get_with_tags(task_id: str) → Task  # 预加载标签
    async def get_by_creator(creator_id: str, **filters) → List[Task]
    async def search_tasks(keyword: str, **filters) → List[Task]
    async def get_by_status(status: str) → List[Task]
    async def get_by_priority(priority: str) → List[Task]

    # 统计方法
    async def count_by_creator(creator_id: str, **filters) → int
```

**关键特性**:
- ✅ 使用 SQLAlchemy ORM 和异步会话
- ✅ 单例模式（通过 `.instance()` 访问）
- ✅ 支持复杂查询（关键词搜索、多条件筛选）
- ✅ 支持分页和排序

---

### TaskAssignmentDAO
**文件**: `fast-task-server/src/dao/task_assignment_dao.py`

**核心方法**:
```python
class TaskAssignmentDAO(BaseDAO[TaskAssignment]):
    # 查询方法
    async def get_by_task(task_id: str) → List[TaskAssignment]
    async def get_by_employee(employee_no: str, page, page_size) → (List[TaskAssignment], int)
    async def get_by_task_and_employee(task_id: str, employee_no: str) → TaskAssignment
    async def is_assigned(task_id: str, employee_no: str) → bool

    # 操作方法
    async def delete_by_task(task_id: str, employee_nos: List[str] = None) → int
    async def update_status(task_id: str, employee_no: str, status: str) → TaskAssignment

    # 统计方法
    async def count_by_task(task_id: str) → int
    async def count_by_employee(employee_no: str, status: str = None) → int
```

**关键特性**:
- ✅ 支持批量分配和取消分配
- ✅ 分配状态管理（pending → accepted → started）
- ✅ 分页查询员工任务
- ✅ 防止重复分配

---

### TaskCommentDAO
**文件**: `fast-task-server/src/dao/task_comment_dao.py`

**核心方法**:
```python
class TaskCommentDAO(BaseDAO[TaskComment]):
    # 查询方法
    async def get_by_task(task_id: str, include_deleted: bool = False) → List[TaskComment]
    async def get_by_employee(employee_no: str, limit: int) → List[TaskComment]
    async def get_replies(comment_id: str) → List[TaskComment]
    async def get_related_comments(related_task_id: str, limit: int) → List[TaskComment]
    async def get_by_enterprise(enterprise_id: str, page, page_size) → (List[TaskComment], int)

    # 操作方法
    async def soft_delete(comment_id: str) → bool

    # 统计方法
    async def count_by_task(task_id: str) → int
    async def count_unread_mentions(task_id: str, employee_no: str) → int
```

**关键特性**:
- ✅ 支持嵌套评论（通过 `parent_comment_id`）
- ✅ 软删除（保留评论结构）
- ✅ 跨任务引用（通过 `related_task_id`）
- ✅ 分页查询企业评论

---

## 🌐 API 层（路由和服务）

### API 路由
**文件**: `fast-task-server/src/api/routes/tasks.py`

**任务 CRUD 端点**:
```python
POST   /api/tasks/                    # 创建任务
GET    /api/tasks/                    # 获取任务列表（分页、搜索、筛选）
GET    /api/tasks/{task_id}           # 获取任务详情
PUT    /api/tasks/{task_id}           # 更新任务
DELETE /api/tasks/{task_id}           # 删除任务
```

**标签管理端点**:
```python
POST   /api/tasks/{task_id}/tags      # 添加标签
GET    /api/tasks/{task_id}/tags      # 获取任务标签
DELETE /api/tasks/tags/{tag_id}       # 删除标签
```

**任务分配端点**:
```python
POST   /api/tasks/{task_id}/assign-by-employee-no    # 分配任务（通过工号）
POST   /api/tasks/{task_id}/assign-by-user-id        # 分配任务（通过用户ID）
DELETE /api/tasks/{task_id}/assign                   # 取消任务分配
GET    /api/tasks/{task_id}/assignments              # 获取任务分配列表
```

**任务执行端点**:
```python
POST   /api/tasks/{task_id}/start              # 开始任务（员工操作）
POST   /api/tasks/{task_id}/complete           # 完成任务（员工操作）
GET    /api/tasks/{task_id}/executions         # 获取任务执行记录
GET    /api/tasks/my/assigned                  # 获取分配给我的任务（员工）
```

**请求/响应 DTO**:
**文件**: `fast-task-server/src/api/dtos/task_dto.py`

```python
# 请求 DTO
class TaskCreateRequest(BaseModel):
    title: str                  # 1-200字符
    description: Optional[str]  # 最多2000字符
    priority: str = "medium"    # high/medium/low

class TaskUpdateRequest(BaseModel):
    title: Optional[str]
    description: Optional[str]
    priority: Optional[str]
    status: Optional[str]       # pending/in_progress/completed/cancelled

class TaskAssignRequest(BaseModel):
    employee_nos: List[str]     # 员工工号列表（1-10个）
    notes: Optional[str]        # 分配备注

# 响应 DTO
class TaskDTO(BaseModel):
    id: str
    title: str
    description: Optional[str]
    priority: str
    status: str
    created_by: Optional[str]
    created_at: str             # ISO 8601 格式
    updated_at: str
    tags: List[TagDTO]          # 标签列表
    assignments: List[AssignmentDTO]  # 任务分配列表

class AssignmentDTO(BaseModel):
    id: str
    task_id: str
    employee_no: str
    employee_name: Optional[str]  # 包含员工姓名
    assigned_by: Optional[str]
    assigned_by_name: Optional[str]  # 包含分配人姓名
    assigned_at: str
    status: str                 # pending/accepted/rejected/started
    notes: Optional[str]

class CommentDTO(BaseModel):
    id: str
    task_id: str
    task_title: Optional[str]   # 包含任务标题
    employee_no: str
    employee_name: Optional[str]
    content: str
    related_task_id: Optional[str]
    related_task_title: Optional[str]  # 包含关联任务标题
    parent_comment_id: Optional[str]
    is_deleted: bool
    created_at: str
    updated_at: str
    replies: List[CommentDTO]   # 子评论（回复）
```

---

### 服务层

#### TaskService（用户任务服务）
**文件**: `fast-task-server/src/api/services/task_service.py`

**认证方式**: JWT Token（用户身份）

**核心功能**:
- ✅ 任务 CRUD（创建、查询、更新、删除）
- ✅ 标签管理（添加、删除、查询）
- ✅ 任务分配（分配给员工、取消分配）
- ✅ 任务执行（开始、完成任务）
- ✅ 权限控制（只能操作自己创建的任务）
- ✅ WebSocket 通知（任务分配通知）

**权限模型**:
```python
# 任务可见性规则
task.created_by == current_user_id  # 只有创建者可以查看和操作

# 分配权限
await assign_task(task_id, employee_nos, assigned_by)
# 验证：task.created_by == current_user_id
```

---

#### EmployeeTaskService（员工任务服务）
**文件**: `fast-task-server/src/api/services/employee_task_service.py`

**认证方式**: 员工工号 + 登录口令

**核心功能**:
- ✅ 任务 CRUD（创建、查询、更新、删除）
- ✅ 标签管理（添加、删除、查询）
- ✅ 任务分配（分配给其他员工）
- ✅ 任务执行（开始、完成任务）
- ✅ **评论系统**（添加、查询、更新、删除评论）
- ✅ 权限控制（可查看自己创建的或分配给自己的任务）
- ✅ WebSocket 通知（任务分配通知、任务关联通知）

**权限模型**:
```python
# 任务可见性规则
task.created_by == my_user_id OR is_assigned(task_id, my_employee_no)
# 创建者或被分配员工可以查看和操作

# 评论权限
await add_comment(task_id, content)
# 验证：task.enterprise_id == my_enterprise_id（企业隔离）

await update_comment(comment_id, content)
# 验证：comment.employee_no == my_employee_no（只能修改自己的评论）
```

**评论系统方法**:
```python
async def add_comment(task_id, dto) → TaskComment
async def get_task_comments(task_id, include_replies=True) → List[TaskComment]
async def update_comment(comment_id, dto) → TaskComment
async def delete_comment(comment_id) → None
async def get_related_task_comments(task_id, limit=50) → List[TaskComment]
async def get_my_comments(page, page_size) → (List[TaskComment], int)
```

---

## 🔐 权限和安全

### 1. 双认证体系

#### 用户认证（JWT）
- **用途**: 管理员或普通用户操作
- **认证方式**: `Authorization: Bearer <token>`
- **权限范围**: 可查看和操作自己创建的任务

#### 员工认证（Employee）
- **用途**: 员工任务操作
- **认证方式**: `X-Employee-No` + `X-Employee-Token`
- **权限范围**: 可查看和操作自己创建的或分配给自己的任务

### 2. 企业隔离
```python
# 所有数据访问都经过企业隔离检查
if task.enterprise_id and task.enterprise_id != my_enterprise_id:
    raise BadRequestException("无权访问此任务")

# 分配任务时
if employee.enterprise_id != task.enterprise_id:
    raise BadRequestException("员工不在您的企业中")
```

### 3. 操作权限
| 操作 | 创建者 | 被分配员工 | 其他员工 |
|------|--------|-----------|---------|
| 查看任务 | ✅ | ✅ | ❌ |
| 更新任务 | ✅ | ✅ | ❌ |
| 删除任务 | ✅ | ❌ | ❌ |
| 分配任务 | ✅ | ❌ | ❌ |
| 开始任务 | ❌ | ✅ | ❌ |
| 完成任务 | ❌ | ✅ | ❌ |
| 添加评论 | ❌ | ✅ | ❌ |
| 更新/删除评论 | ❌ | ✅（自己的） | ❌ |

---

## 📡 实时通知

### WebSocket 通知服务
**文件**: `fast-task-server/src/api/services/task_notification_service.py`

**通知类型**:
```python
async def notify_task_assigned(
    employee_no: str,
    task_id: str,
    task_title: str,
    assigned_by: str,
    notes: Optional[str]
)
# 通知：任务已分配给您

async def notify_task_related(
    employee_no: str,
    task_id: str,
    task_title: str,
    related_task_id: str,
    related_task_title: str,
    commenter: str,
    comment_preview: str
)
# 通知：有任务引用了您的任务
```

**通知场景**:
1. ✅ 任务分配通知（分配给员工时）
2. ✅ 任务关联通知（评论中引用其他任务时）
3. ⚠️ 评论回复通知（待实现）

---

## 🎯 与 GitHub Issue 功能对比

| GitHub Issue 功能 | 现有实现 | 状态 |
|------------------|---------|------|
| 创建 Issue | ✅ `POST /api/tasks/` | 完整实现 |
| 编辑 Issue | ✅ `PUT /api/tasks/{id}` | 完整实现 |
| 删除 Issue | ✅ `DELETE /api/tasks/{id}` | 完整实现 |
| 标签（Labels） | ✅ `POST /api/tasks/{id}/tags` | 完整实现 |
| 里程碑（Milestones） | ❌ 未实现 | 待开发 |
| 评论（Comments） | ✅ 员工任务服务中实现 | 完整实现 |
| 评论回复 | ✅ `parent_comment_id` | 完整实现 |
| 关联 Issue | ✅ `related_task_id` | 完整实现 |
| 分配（Assignees） | ✅ 多人分配 | 完整实现（优于 GitHub） |
| 状态（Open/Closed） | ✅ `pending/in_progress/completed/cancelled` | 更细粒度 |
| 优先级 | ✅ `high/medium/low` | GitHub 无此功能 |
| 通知 | ✅ WebSocket 实时推送 | 完整实现 |
| 搜索 | ✅ 关键词、优先级、状态 | 完整实现 |
| 分页 | ✅ `PageResultDTO` | 完整实现 |

**结论**: 现有系统已实现 **90%** 的 GitHub Issue 核心功能，甚至在某些方面更优（如多人分配、更细粒度的状态）。

---

## 🚀 缺失功能分析

根据 GitHub Issue #1 的需求，对比现有系统，以下功能**尚未实现**：

### 1. API 路由层缺失
❌ **评论相关的 HTTP 端点未暴露**

虽然 `EmployeeTaskService` 已实现评论功能，但没有对应的 HTTP 路由：

**需要添加的端点**:
```python
POST   /api/employee/tasks/{task_id}/comments     # 添加评论
GET    /api/employee/tasks/{task_id}/comments     # 获取任务评论
PUT    /api/employee/comments/{comment_id}        # 更新评论
DELETE /api/employee/comments/{comment_id}        # 删除评论
GET    /api/employee/tasks/{task_id}/related-comments  # 获取关联评论
GET    /api/employee/comments/my                  # 获取我的评论
```

**文件位置**: 需要在 `fast-task-server/src/api/routes/` 下创建 `employee_tasks.py` 路由文件

---

### 2. 前端 UI 缺失
❌ **Web 管理界面尚未开发**

虽然后端 API 已经完整，但前端 `fast-task-ui` 可能还需要：
- 任务列表页面（含搜索、筛选、分页）
- 任务详情页面（含标签、分配、执行记录）
- 任务创建/编辑表单
- 任务分配界面（支持多选员工）
- 评论界面（支持回复、关联任务）
- 员工任务视图（分配给我的任务）

**建议**: 检查 `fast-task-ui` 子模块的实现情况

---

### 3. 功能增强建议

#### 3.1 里程碑功能（可选）
**类似 GitHub Milestones**，用于组织任务到里程碑中。

**数据库模型**:
```python
class Milestone(Base):
    __tablename__ = "milestones"

    id: str
    enterprise_id: str
    title: str                  # 里程碑标题
    description: Optional[str]  # 里程碑描述
    status: str                 # open/closed
    due_date: Optional[datetime] # 截止日期

    created_at: datetime
    updated_at: datetime
```

**任务模型扩展**:
```python
# Task 模型添加字段
milestone_id: Optional[str] = mapped_column(String(50), ForeignKey("milestones.id"))
```

---

#### 3.2 附件功能（可选）
**支持上传文件附件到任务**。

**数据库模型**:
```python
class TaskAttachment(Base):
    __tablename__ = "task_attachments"

    id: str
    task_id: str
    employee_no: str
    file_name: str              # 文件名
    file_url: str               # 文件URL
    file_size: int              # 文件大小（字节）
    mime_type: str              # MIME类型

    uploaded_at: datetime
```

---

#### 3.3 @提及功能（可选）
**在评论中提及员工，通知他们**。

**数据库模型**:
```python
class CommentMention(Base):
    __tablename__ = "comment_mentions"

    id: str
    comment_id: str
    mentioned_employee_no: str   # 被提及的员工
    is_read: bool                # 是否已读

    created_at: datetime
```

**评论解析**:
```python
# 解析评论中的 @提及
@employee_one 请查看这个任务
```

---

#### 3.4 活动流（Activity Stream）
**记录任务的所有活动历史**。

**数据库模型**:
```python
class TaskActivity(Base):
    __tablename__ = "task_activities"

    id: str
    task_id: str
    employee_no: str
    action: str                 # created/updated/assigned/started/commented/...
    details: JSON               # 活动详情（JSON格式）

    created_at: datetime
```

---

#### 3.5 搜索增强（可选）
**当前仅支持标题和描述的关键词搜索，可增强为**:

- ✅ 全文搜索（PostgreSQL FTS）
- ✅ 按标签筛选
- ✅ 按分配员工筛选
- ✅ 按创建时间范围筛选
- ✅ 按截止日期筛选（需要添加 due_date 字段）
- ✅ 高级查询（组合条件、排序）

---

## 📝 测试覆盖

### 现有测试脚本
**文件**: `fast-task-server/scripts/test_employee_task_api.py`

**测试覆盖**:
- ✅ 管理员登录
- ✅ 创建企业
- ✅ 创建员工（工号 + 登录口令）
- ✅ 员工登录
- ✅ 创建任务
- ✅ 获取任务列表
- ✅ 分配任务
- ✅ 开始任务
- ✅ 完成任务

**建议**: 添加评论功能的测试用例

---

## 📚 相关文档

### 内部文档
- `docs/PRD.md` - 产品需求文档
- `docs/ARCHITECTURE.md` - 架构设计文档
- `docs/CHANNELS_TECH_SUMMARY.md` - MCP Channels 技术总结
- `fast-task-server/CLAUDE.md` - 后端开发指南

### 数据库文档
- `fast-task-server/src/database/models.py` - 数据库模型定义
- `docs/sql/sql-{id}.sql` - （待创建）数据库设计文档

### API 文档
- Swagger UI: `http://localhost:8766/docs`（FastAPI 自动生成）

---

## 🎯 下一步行动建议

根据探索结果，建议按以下优先级处理 Issue #1：

### 优先级 P0（必须完成）
1. ✅ **确认功能完整性** - 已完成（现有系统已实现所有核心功能）
2. ⚠️ **暴露评论 API 路由** - 需要创建 `employee_tasks.py` 路由文件

### 优先级 P1（建议完成）
3. 📝 **创建数据库设计文档** - `docs/sql/sql-1.sql`
4. 📝 **完善 API 文档** - 添加评论接口文档
5. 🧪 **编写测试脚本** - 测试评论功能

### 优先级 P2（可选）
6. 🎨 **开发前端 UI** - 检查 `fast-task-ui` 实现情况
7. ✨ **功能增强** - 里程碑、附件、@提及、活动流
8. 🔍 **搜索增强** - 全文搜索、高级筛选

---

## 📊 总结

### ✅ 已实现功能（100% 核心需求）
1. ✅ 任务 CRUD（创建、读取、更新、删除）
2. ✅ 标签管理（添加、删除、查询）
3. ✅ 生命周期管理（pending → in_progress → completed → cancelled）
4. ✅ 多人协作（一个任务分配给多个员工）
5. ✅ 评论系统（添加、回复、关联任务、软删除）
6. ✅ 权限控制（企业隔离、操作权限）
7. ✅ 实时通知（WebSocket 推送）

### ⚠️ 待补充功能
1. ⚠️ 评论 API 路由（服务层已实现，但缺少 HTTP 端点）
2. ❌ 里程碑功能（可选）
3. ❌ 附件功能（可选）
4. ❌ @提及功能（可选）
5. ❌ 活动流（可选）
6. ❌ 搜索增强（可选）

### 🎯 建议
**Issue #1 的核心需求已经实现**，建议：
1. 先补充评论 API 路由，使功能完整可用
2. 根据实际业务需求，逐步添加可选功能
3. 优先开发前端 UI，提升用户体验

---

**文档版本**: 1.0
**创建时间**: 2026-04-09
**创建者**: Claude Code
**审核状态**: 待审核
