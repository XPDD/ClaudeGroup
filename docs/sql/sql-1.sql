-- ============================================================================
-- ClaudeGroup 任务管理系统 - 数据库设计文档
-- ============================================================================
--
-- 文档版本: 1.0
-- 创建日期: 2026-04-09
-- 数据库: PostgreSQL 14+
-- 编码: UTF-8
--
-- 相关文档:
-- - PRD: ../prd/prd-1.md
-- - 架构设计: ../arc/arc-1.md
-- - 探索文档: ../task/issue-1.md
--
-- ============================================================================

-- ============================================================================
-- 表结构概览
-- ============================================================================
--
-- 核心表:
-- 1. tasks              - 任务表（主表）
-- 2. tags               - 标签表
-- 3. task_assignments   - 任务分配表
-- 4. task_executions    - 任务执行记录表
-- 5. task_comments      - 任务评论表
--
-- 关联表（已有，本文档不详细展开）:
-- - users               - 用户表
-- - user_enterprises    - 用户企业关联表
-- - enterprises         - 企业表
--
-- ============================================================================

-- ============================================================================
-- 1. 任务表 (tasks)
-- ============================================================================
--
-- 说明: 存储任务的基本信息
-- 关系: 一个任务可有多个标签、多个分配、多个执行记录、多条评论
--

CREATE TABLE IF NOT EXISTS tasks (
    -- 主键
    id VARCHAR(50) PRIMARY KEY,

    -- 基础信息
    title VARCHAR(200) NOT NULL,               -- 任务标题（必填）
    description TEXT,                          -- 任务描述（可选）

    -- 任务属性
    priority VARCHAR(20) NOT NULL DEFAULT 'medium',  -- 优先级: high/medium/low
    status VARCHAR(20) NOT NULL DEFAULT 'pending',   -- 状态: pending/in_progress/completed/cancelled

    -- 所属关系
    created_by VARCHAR(50),                    -- 创建人ID（用户ID）
    enterprise_id VARCHAR(50),                 -- 企业ID（企业隔离）

    -- 时间戳
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 约束
    CONSTRAINT chk_tasks_priority CHECK (priority IN ('high', 'medium', 'low')),
    CONSTRAINT chk_tasks_status CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled'))
);

-- 索引
CREATE INDEX idx_tasks_title ON tasks(title);                    -- 标题搜索
CREATE INDEX idx_tasks_status ON tasks(status);                  -- 状态筛选
CREATE INDEX idx_tasks_priority ON tasks(priority);              -- 优先级筛选
CREATE INDEX idx_tasks_created_by ON tasks(created_by);          -- 按创建人查询
CREATE INDEX idx_tasks_enterprise_id ON tasks(enterprise_id);    -- 企业隔离
CREATE INDEX idx_tasks_created_at ON tasks(created_at DESC);     -- 按创建时间排序

-- 复合索引（常用组合查询）
CREATE INDEX idx_tasks_status_priority ON tasks(status, priority);
CREATE INDEX idx_tasks_created_by_status ON tasks(created_by, status);

-- 注释
COMMENT ON TABLE tasks IS '任务表';
COMMENT ON COLUMN tasks.id IS '任务ID（UUID）';
COMMENT ON COLUMN tasks.title IS '任务标题（1-200字符）';
COMMENT ON COLUMN tasks.description IS '任务描述（最多2000字符）';
COMMENT ON COLUMN tasks.priority IS '优先级：high-高优先级，medium-中优先级，low-低优先级';
COMMENT ON COLUMN tasks.status IS '状态：pending-待处理，in_progress-进行中，completed-已完成，cancelled-已取消';
COMMENT ON COLUMN tasks.created_by IS '创建人ID（关联users表）';
COMMENT ON COLUMN tasks.enterprise_id IS '企业ID（企业隔离）';


-- ============================================================================
-- 2. 标签表 (tags)
-- ============================================================================
--
-- 说明: 存储任务的标签信息
-- 关系: 一个任务可有多个标签，删除任务时级联删除标签
--

CREATE TABLE IF NOT EXISTS tags (
    -- 主键
    id VARCHAR(50) PRIMARY KEY,

    -- 标签信息
    name VARCHAR(50) NOT NULL,                 -- 标签名称
    color VARCHAR(20),                         -- 标签颜色（十六进制，如 #FF5733）

    -- 关联关系
    task_id VARCHAR(50) NOT NULL,              -- 所属任务ID

    -- 时间戳
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 外键约束
    CONSTRAINT fk_tags_task FOREIGN KEY (task_id)
        REFERENCES tasks(id)
        ON DELETE CASCADE,                     -- 删除任务时级联删除标签

    -- 唯一约束（同一任务下标签名称不重复）
    CONSTRAINT uq_tags_task_name UNIQUE (task_id, name)
);

-- 索引
CREATE INDEX idx_tags_task_id ON tags(task_id);          -- 按任务查询标签
CREATE INDEX idx_tags_name ON tags(name);                -- 按标签名称搜索

-- 注释
COMMENT ON TABLE tags IS '标签表';
COMMENT ON COLUMN tags.name IS '标签名称（1-50字符）';
COMMENT ON COLUMN tags.color IS '标签颜色（如 #FF5733）';
COMMENT ON COLUMN tags.task_id IS '所属任务ID';


-- ============================================================================
-- 3. 任务分配表 (task_assignments)
-- ============================================================================
--
-- 说明: 存储任务分配给员工的信息
-- 关系: 一个任务可分配给多个员工（多人协作）
--

CREATE TABLE IF NOT EXISTS task_assignments (
    -- 主键
    id VARCHAR(50) PRIMARY KEY,

    -- 关联关系
    task_id VARCHAR(50) NOT NULL,              -- 任务ID
    employee_no VARCHAR(50) NOT NULL,         -- 员工工号
    enterprise_id VARCHAR(50) NOT NULL,        -- 企业ID

    -- 分配信息
    assigned_by VARCHAR(50),                   -- 分配人ID（用户ID）
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- 分配时间
    notes VARCHAR(500),                        -- 分配备注（如：任务说明、截止时间）

    -- 分配状态
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending/accepted/rejected/started

    -- 外键约束
    CONSTRAINT fk_assignments_task FOREIGN KEY (task_id)
        REFERENCES tasks(id)
        ON DELETE CASCADE,                     -- 删除任务时级联删除分配

    -- 约束
    CONSTRAINT chk_assignments_status CHECK (status IN ('pending', 'accepted', 'rejected', 'started'))
);

-- 索引
CREATE INDEX idx_assignments_task_id ON task_assignments(task_id);         -- 按任务查询分配
CREATE INDEX idx_assignments_employee_no ON task_assignments(employee_no); -- 按员工查询分配
CREATE INDEX idx_assignments_enterprise_id ON task_assignments(enterprise_id); -- 企业隔离

-- 复合索引（常用组合查询）
CREATE INDEX idx_assignments_task_employee ON task_assignments(task_id, employee_no);
CREATE INDEX idx_assignments_employee_status ON task_assignments(employee_no, status);

-- 注释
COMMENT ON TABLE task_assignments IS '任务分配表';
COMMENT ON COLUMN task_assignments.employee_no IS '员工工号';
COMMENT ON COLUMN task_assignments.assigned_by IS '分配人ID（谁分配的这个任务）';
COMMENT ON COLUMN task_assignments.notes IS '分配备注（如：任务说明、截止时间、注意事项）';
COMMENT ON COLUMN task_assignments.status IS '分配状态：pending-待接受，accepted-已接受，rejected-已拒绝，started-已开始';


-- ============================================================================
-- 4. 任务执行记录表 (task_executions)
-- ============================================================================
--
-- 说明: 记录任务的执行历史（开始、完成、取消等操作）
-- 关系: 一个任务可有多个执行记录
--

CREATE TABLE IF NOT EXISTS task_executions (
    -- 主键
    id VARCHAR(50) PRIMARY KEY,

    -- 关联关系
    task_id VARCHAR(50) NOT NULL,              -- 任务ID
    employee_no VARCHAR(50) NOT NULL,         -- 执行员工工号

    -- 执行信息
    action VARCHAR(20) NOT NULL,              -- 操作类型：start/complete/cancel
    notes TEXT,                               -- 执行备注（如：完成说明、遇到的问题）

    -- 时间戳
    executed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- 执行时间

    -- 外键约束
    CONSTRAINT fk_executions_task FOREIGN KEY (task_id)
        REFERENCES tasks(id)
        ON DELETE CASCADE,                     -- 删除任务时级联删除执行记录

    -- 约束
    CONSTRAINT chk_executions_action CHECK (action IN ('start', 'complete', 'cancel'))
);

-- 索引
CREATE INDEX idx_executions_task_id ON task_executions(task_id);         -- 按任务查询执行记录
CREATE INDEX idx_executions_employee_no ON task_executions(employee_no); -- 按员工查询执行记录
CREATE INDEX idx_executions_action ON task_executions(action);           -- 按操作类型查询
CREATE INDEX idx_executions_executed_at ON task_executions(executed_at DESC); -- 按时间排序

-- 复合索引
CREATE INDEX idx_executions_task_action ON task_executions(task_id, action);

-- 注释
COMMENT ON TABLE task_executions IS '任务执行记录表';
COMMENT ON COLUMN task_executions.employee_no IS '执行员工工号';
COMMENT ON COLUMN task_executions.action IS '操作类型：start-开始任务，complete-完成任务，cancel-取消任务';
COMMENT ON COLUMN task_executions.notes IS '执行备注（如：完成说明、遇到的问题）';


-- ============================================================================
-- 5. 任务评论表 (task_comments)
-- ============================================================================
--
-- 说明: 存储任务的评论信息，支持回复和跨任务关联
-- 关系: 一个任务可有多条评论，评论可回复评论（自引用）
--

CREATE TABLE IF NOT EXISTS task_comments (
    -- 主键
    id VARCHAR(50) PRIMARY KEY,

    -- 关联关系
    task_id VARCHAR(50) NOT NULL,              -- 任务ID
    employee_no VARCHAR(50) NOT NULL,         -- 评论者工号
    enterprise_id VARCHAR(50) NOT NULL,        -- 企业ID

    -- 评论内容
    content TEXT NOT NULL,                     -- 评论内容

    -- 关联关系
    related_task_id VARCHAR(50),               -- 关联的任务ID（用于跨任务引用，类似GitHub Issue关联）
    parent_comment_id VARCHAR(50),             -- 父评论ID（用于回复，形成嵌套评论）

    -- 状态
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE, -- 是否已删除（软删除）

    -- 时间戳
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 外键约束
    CONSTRAINT fk_comments_task FOREIGN KEY (task_id)
        REFERENCES tasks(id)
        ON DELETE CASCADE,                     -- 删除任务时级联删除评论

    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id)
        REFERENCES task_comments(id)
        ON DELETE SET NULL,                    -- 删除父评论时，子评论的parent_comment_id设为NULL

    -- 约束
    CONSTRAINT chk_comments_content_length CHECK (LENGTH(content) >= 1 AND LENGTH(content) <= 2000)
);

-- 索引
CREATE INDEX idx_comments_task_id ON task_comments(task_id);           -- 按任务查询评论
CREATE INDEX idx_comments_employee_no ON task_comments(employee_no);   -- 按员工查询评论
CREATE INDEX idx_comments_enterprise_id ON task_comments(enterprise_id); -- 企业隔离
CREATE INDEX idx_comments_parent ON task_comments(parent_comment_id);  -- 查询父评论的回复
CREATE INDEX idx_comments_related_task ON task_comments(related_task_id); -- 查询关联此任务的评论
CREATE INDEX idx_comments_created_at ON task_comments(created_at DESC);  -- 按时间排序

-- 复合索引（常用组合查询）
CREATE INDEX idx_comments_task_deleted ON task_comments(task_id, is_deleted);
CREATE INDEX idx_comments_employee_task ON task_comments(employee_no, task_id);

-- 注释
COMMENT ON TABLE task_comments IS '任务评论表';
COMMENT ON COLUMN task_comments.employee_no IS '评论者工号';
COMMENT ON COLUMN task_comments.content IS '评论内容（1-2000字符）';
COMMENT ON COLUMN task_comments.related_task_id IS '关联的任务ID（用于跨任务引用，类似GitHub Issue关联）';
COMMENT ON COLUMN task_comments.parent_comment_id IS '父评论ID（用于回复，形成嵌套评论结构）';
COMMENT ON COLUMN task_comments.is_deleted IS '是否已删除（软删除，删除后评论内容保留但标记为已删除）';


-- ============================================================================
-- 视图定义（可选）
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 视图 1: 任务详情视图（包含标签、分配、执行记录、评论数量）
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_task_details AS
SELECT
    t.id,
    t.title,
    t.description,
    t.priority,
    t.status,
    t.created_by,
    t.enterprise_id,
    t.created_at,
    t.updated_at,
    -- 统计信息
    (SELECT COUNT(*) FROM tags WHERE task_id = t.id) AS tag_count,
    (SELECT COUNT(*) FROM task_assignments WHERE task_id = t.id) AS assignment_count,
    (SELECT COUNT(*) FROM task_executions WHERE task_id = t.id) AS execution_count,
    (SELECT COUNT(*) FROM task_comments WHERE task_id = t.id AND is_deleted = FALSE) AS comment_count
FROM tasks t;

COMMENT ON VIEW v_task_details IS '任务详情视图（包含统计信息）';


-- ----------------------------------------------------------------------------
-- 视图 2: 员工任务视图（员工创建的 + 分配给员工的）
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_employee_tasks AS
SELECT
    t.id,
    t.title,
    t.description,
    t.priority,
    t.status,
    t.created_by,
    t.enterprise_id,
    t.created_at,
    t.updated_at,
    -- 分配信息
    ta.employee_no,
    ta.status AS assignment_status,
    ta.assigned_at,
    -- 是否是创建者
    CASE WHEN t.created_by = (
        SELECT user_id FROM user_enterprises WHERE employee_no = ta.employee_no LIMIT 1
    ) THEN TRUE ELSE FALSE END AS is_creator
FROM tasks t
INNER JOIN task_assignments ta ON t.id = ta.task_id
WHERE ta.status IN ('accepted', 'started');  -- 只显示已接受或已开始的分配

COMMENT ON VIEW v_employee_tasks IS '员工任务视图（员工创建的 + 分配给员工的）';


-- ============================================================================
-- 触发器（可选）
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 触发器 1: 自动更新 updated_at 字段
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为 tasks 表创建触发器
DROP TRIGGER IF EXISTS trigger_tasks_updated_at ON tasks;
CREATE TRIGGER trigger_tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 为 task_comments 表创建触发器
DROP TRIGGER IF EXISTS trigger_comments_updated_at ON task_comments;
CREATE TRIGGER trigger_comments_updated_at
    BEFORE UPDATE ON task_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- 存储过程（可选）
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 存储过程 1: 批量更新任务状态
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_batch_update_task_status(
    p_task_ids VARCHAR(50)[],
    p_new_status VARCHAR(20)
)
RETURNS INT AS $$
DECLARE
    v_updated_count INT;
BEGIN
    -- 验证状态
    IF p_new_status NOT IN ('pending', 'in_progress', 'completed', 'cancelled') THEN
        RAISE EXCEPTION '无效的状态: %', p_new_status;
    END IF;

    -- 批量更新
    UPDATE tasks
    SET status = p_new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = ANY(p_task_ids);

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sp_batch_update_task_status IS '批量更新任务状态';


-- ----------------------------------------------------------------------------
-- 存储过程 2: 获取企业任务统计
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_get_enterprise_task_stats(
    p_enterprise_id VARCHAR(50)
)
RETURNS TABLE (
    status VARCHAR(20),
    task_count BIGINT,
    percentage NUMERIC
) AS $$
DECLARE
    v_total BIGINT;
BEGIN
    -- 获取总任务数
    SELECT COUNT(*) INTO v_total
    FROM tasks
    WHERE enterprise_id = p_enterprise_id;

    -- 返回各状态的任务数和百分比
    RETURN QUERY
    SELECT
        t.status,
        COUNT(*) AS task_count,
        CASE
            WHEN v_total > 0 THEN ROUND(COUNT(*)::NUMERIC / v_total * 100, 2)
            ELSE 0
        END AS percentage
    FROM tasks t
    WHERE t.enterprise_id = p_enterprise_id
    GROUP BY t.status
    ORDER BY
        CASE t.status
            WHEN 'pending' THEN 1
            WHEN 'in_progress' THEN 2
            WHEN 'completed' THEN 3
            WHEN 'cancelled' THEN 4
        END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sp_get_enterprise_task_stats IS '获取企业任务统计（按状态分组）';


-- ============================================================================
-- 数据初始化（可选，仅用于测试）
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 初始化脚本: 插入测试数据
-- ----------------------------------------------------------------------------

-- 注意: 此脚本仅用于开发和测试，生产环境请勿执行

-- 插入测试任务
-- INSERT INTO tasks (id, title, description, priority, status, created_by, enterprise_id) VALUES
-- ('task-001', '修复登录页面崩溃', '用户反馈在 iOS 15 上登录后崩溃', 'high', 'pending', 'user-001', 'ent-001'),
-- ('task-002', '优化数据库查询', '任务列表查询速度较慢，需要优化', 'medium', 'in_progress', 'user-001', 'ent-001'),
-- ('task-003', '添加导出功能', '支持导出任务列表为 Excel', 'low', 'pending', 'user-002', 'ent-001');

-- 插入测试标签
-- INSERT INTO tags (id, name, color, task_id) VALUES
-- ('tag-001', 'bug', '#FF5733', 'task-001'),
-- ('tag-002', '优化', '#FFC300', 'task-002'),
-- ('tag-003', 'feature', '#DAF7A6', 'task-003');

-- 插入测试分配
-- INSERT INTO task_assignments (id, task_id, employee_no, enterprise_id, assigned_by, notes, status) VALUES
-- ('assign-001', 'task-001', 'EMP001', 'ent-001', 'user-001', '优先处理，影响用户体验', 'accepted'),
-- ('assign-002', 'task-002', 'EMP002', 'ent-001', 'user-001', '需要优化索引', 'started');

-- 插入测试执行记录
-- INSERT INTO task_executions (id, task_id, employee_no, action, notes) VALUES
-- ('exec-001', 'task-002', 'EMP002', 'start', '开始分析查询慢的原因'),
-- ('exec-002', 'task-002', 'EMP002', 'complete', '已添加复合索引，查询速度提升50%');


-- ============================================================================
-- 数据清理（谨慎使用）
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 清理脚本: 删除所有数据（仅用于开发环境重置）
-- ----------------------------------------------------------------------------

-- 注意: 此脚本会删除所有数据，请谨慎使用

-- DELETE FROM task_executions;
-- DELETE FROM task_comments;
-- DELETE FROM task_assignments;
-- DELETE FROM tags;
-- DELETE FROM tasks;


-- ============================================================================
-- 性能优化建议
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. 定期维护表（VACUUM ANALYZE）
-- ----------------------------------------------------------------------------

-- 定期执行以优化查询性能
-- VACUUM ANALYZE tasks;
-- VACUUM ANALYZE tags;
-- VACUUM ANALYZE task_assignments;
-- VACUUM ANALYZE task_executions;
-- VACUUM ANALYZE task_comments;


-- ----------------------------------------------------------------------------
-- 2. 监控慢查询
-- ----------------------------------------------------------------------------

-- 启用慢查询日志（需要在 postgresql.conf 中配置）
-- log_min_duration_statement = 1000  -- 记录执行时间超过1秒的查询


-- ----------------------------------------------------------------------------
-- 3. 定期重建索引
-- ----------------------------------------------------------------------------

-- 定期重建碎片化的索引（可选）
-- REINDEX TABLE tasks;
-- REINDEX TABLE task_comments;


-- ============================================================================
-- 附录
-- ============================================================================

-- A. 表关系总结
--    tasks (1) ----< (N) tags
--    tasks (1) ----< (N) task_assignments
--    tasks (1) ----< (N) task_executions
--    tasks (1) ----< (N) task_comments
--    task_comments (1) ----< (N) task_comments (自引用，回复关系)

-- B. 级联删除规则
--    删除 tasks → 级联删除 tags, task_assignments, task_executions, task_comments
--    删除 task_comments → 子评论的 parent_comment_id 设为 NULL（不删除子评论）

-- C. 企业隔离
--    所有表都包含 enterprise_id 字段（或通过关联表实现企业隔离）
--    查询时必须带上 enterprise_id 条件

-- D. 索引策略
--    主键索引: 所有表的 id 字段
--    外键索引: task_id, employee_no 等关联字段
--    查询索引: status, priority, created_at 等常用筛选字段
--    复合索引: (task_id, employee_no) 等常用组合查询

-- E. 数据类型选择
--    主键: VARCHAR(50) - 兼容 UUID
--    文本: TEXT - 长文本内容
--    时间: TIMESTAMP - 自动记录时间
--    布尔: BOOLEAN - 软删除标记
--    枚举: VARCHAR + CHECK - 兼容性好，易于扩展

-- F. 扩展性考虑
--    添加新字段: 直接 ALTER TABLE ADD COLUMN
--    添加新表: 遵循现有模式（DAO + Service + API）
--    添加新索引: 非高峰期执行，避免锁表
--    数据迁移: 使用事务保证一致性

-- ============================================================================
-- 文档结束
-- ============================================================================
