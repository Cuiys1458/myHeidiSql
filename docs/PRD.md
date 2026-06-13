# MacHeidi — 产品需求文档（PRD）

> 版本：v0.2（MVP，详细版）
> 日期：2026-06-11
> 状态：草案，待评审
> 负责人：cuiys

---

## 0. 文档约定

### 0.1 关键词

- **必须 / 应当 / 可以** = MUST / SHOULD / MAY，RFC 2119 含义。
- **P0**：发布阻断；**P1**：发布前必修；**P2**：可发布带 known issue；**P3**：v0.2+。
- **MVP** = v0.1，本文档定义的第一个可发布版本。
- 行内代码标识符（如 `DBClient`）= Swift 类型名；`<占位符>` = 用户输入或运行时值。

### 0.2 阅读路径

- 产品 / QA：§1、§4、§5、§7、§12
- 后端 / 驱动：§5.5、§6、§10、§A（附录 A：MySQL 类型映射表）
- 前端 / UI：§5.1-§5.4、§6、§7、§8、§B（附录 B：组件契约）
- 测试：§5、§12、§C（附录 C：测试 fixture 规格）、§D（附录 D：错误码总表）

### 0.3 本 PRD 不涵盖

- 像素级视觉稿（§8 给原则，设计稿单独出）
- 性能指标的硬性 KPI 数字（§9 给目标方向）
- 测试代码本身（由 BDD/TDD 流程单独产出 `.feature` + 测试代码）
- 项目目录结构与构建配置（由架构文档单独出）

---

## 1. 产品概述

### 1.1 一句话定位

MacHeidi 是一款 **macOS 原生** 的 MySQL 数据库管理客户端，**交互模型完全参考 HeidiSQL**，视觉按 macOS 系统风格重新设计。

### 1.2 目标用户

| 画像 | 占比假设 | 核心诉求 | 失败信号（不解决这些就会流失） |
|---|---|---|---|
| 从 Windows 转 Mac 的 HeidiSQL 老用户 | 40% | 操作路径与肌肉记忆完全沿用 | F9/Ctrl+Enter 不工作；找不到"Truncate"右键 |
| Mac 上的 MySQL 日常使用者 | 50% | 轻量、原生、不卡顿；启动 < 2s | 启动菊花转 5s；切表卡顿；内存占 1GB |
| 反 Electron 选手 | 10% | 包 < 30MB、原生控件、跟随系统主题 | 看出来用了 WebView；不支持 Dark Mode |

### 1.3 不是什么

| 不是 | 原因 |
|---|---|
| ER 图工具 | 出图工具市场已饱和（MySQL Workbench、DBeaver） |
| 服务器监控工具 | 不显示慢查询、连接池图表 |
| 数据同步 / 迁移工具 | 与"客户端"定位冲突 |
| 多数据库支持的 v0.1 | 见 v0.4 路线图 |
| ORM / 代码生成器 | 越界 |

### 1.4 价值主张

> "Mac 上的 HeidiSQL 操作手感，没有 Wine 的别扭，没有 Electron 的笨重。"

### 1.5 成功指标（MVP 阶段不做埋点，仅用作内部判断）

- 已迁移自 HeidiSQL 的用户，**首次连接成功后** 30 分钟内能独立完成"查表 → 写 SQL → 看结果 → 改数据 → 提交"全流程。
- 安装包 ≤ 30 MB，冷启动 ≤ 1.5s（M 系列）。
- 100k 行表的滚动 FPS ≥ 50。

---

## 2. 范围（Scope）

### 2.1 MVP 范围（v0.1）

| 域 | 包含 | 详见 |
|---|---|---|
| 连接管理 | 新建 / 编辑 / 删除 / 复制 / 连接 MySQL 会话；密码存 Keychain；配置持久化 | §5.1 |
| 对象树 | 数据库列表、表与视图列表、单击/双击/右键基础操作、F5 刷新 | §5.2 |
| 表数据浏览 | 分页加载、列头排序、WHERE 过滤、就地编辑、INSERT/UPDATE/DELETE 提交、NULL 显示 | §5.3 |
| SQL 编辑执行 | 多标签查询、F9 全部执行、Ctrl+Enter 选中执行、结果网格、错误高亮、取消长查询 | §5.4 |
| 基础设施 | `DBClient` 协议、MySQL 驱动适配、错误归一化、结果集 ViewModel、Keychain 封装 | §5.5 |

### 2.2 明确排除（v0.1 不做）

| 功能 | 推迟到 |
|---|---|
| PostgreSQL / MSSQL / SQLite | v0.4 |
| **中文 UI / 多语言** | v0.2（按 D 决定从 MVP 移除） |
| 表结构编辑（DDL UI）、索引/外键可视化 | v0.3 |
| 存储过程 / 函数 / 触发器 / 事件 | v0.5 |
| 数据导出 / 导入（CSV / SQL / Excel） | v0.2（导出）/ v0.6（导入） |
| 查询历史持久化、SQL 美化、自动补全 | v0.2 / v0.6 |
| 用户与权限管理 UI | v1.x |
| 主从复制状态、进程列表 UI | v1.x |
| SSH 隧道 | v0.2 |
| SSL 自签证书、CA 路径配置 | v0.3（MVP 只支持 SSL on/off） |
| 多窗口、跨连接拖拽 | v1.0 |
| 自动更新、崩溃上报、遥测 | v1.0 |
| 自定义快捷键 | v1.0 |

---

## 3. 核心概念与术语

| 术语 | 定义 | 状态/类型 |
|---|---|---|
| **Session（会话）** | 一组 MySQL 连接配置 + 用户起的名字。**未连接时也存在**。 | `SessionConfig` 持久化对象 |
| **Connection（连接）** | Session 激活后建立的实际 TCP+协议连接 | `DBClient` 实例 |
| **Active Session** | 当前主区域正在展示其内容的 Session；同时最多 1 个 | UI 状态 |
| **Object Tree（对象树）** | 左侧导航：Session → Database → Table/View 三层 | UI 组件 |
| **Data Tab** | 右侧"数据"视图，按表展示行数据，可编辑 | UI 组件 |
| **Query Tab** | 右侧"查询"视图，自由编写并执行 SQL；可有多个 | UI 组件 |
| **Result Sub-Tab** | Query Tab 内的结果子标签（多个 SELECT → 多个） | UI 组件 |
| **Dirty Row** | 用户已修改但未提交的行，行头有 ● 标记 | ViewModel 状态 |
| **Pending Edits** | 当前 Data Tab 全部 Dirty Row 集合 | ViewModel 状态 |
| **Pending Inserts** | 用户新增但未提交的行 | ViewModel 状态 |
| **Pending Deletes** | 用户标记删除但未提交的行 ID 集合 | ViewModel 状态 |
| **`ConnectionConfig`** | 运行时连接参数（含密码明文，从 SessionConfig + Keychain 组装） | 临时值，不持久化 |
| **`DBClient`** | 数据库客户端协议，所有上层只依赖它 | Swift protocol |
| **`ResultSet`** | SELECT 返回的内存表 | 值类型 |
| **`ExecResult`** | DML/DDL 返回的影响行数 + 耗时 + 最后插入 ID | 值类型 |

---

## 4. 用户故事（User Stories）

每条故事在 §5 都有对应的详细场景；每个场景在 §12 都有验收标准。

### 4.1 连接管理

| ID | As a | I want | So that |
|---|---|---|---|
| U1.1 | 新用户 | 新建一个 MySQL 连接配置，下次打开还在 | 不用每次输入 |
| U1.2 | 已有用户 | 双击会话列表条目能 < 3s 进入主界面看到数据库 | 快速开始工作 |
| U1.3 | 安全意识用户 | 密码不明文存盘 | 笔记本丢了不会泄露 |
| U1.4 | 偶尔手抖的用户 | 连接失败时看到清晰错误（不是 "Error -1"）并能重试 | 知道改哪里 |
| U1.5 | 多环境用户 | 复制一个会话快速建相邻环境 | 不用重新填 host/port |

### 4.2 对象树

| ID | As a | I want | So that |
|---|---|---|---|
| U2.1 | 日常使用者 | 连接成功后能看到所有数据库 | 知道有哪些库 |
| U2.2 | 日常使用者 | 单击表只看元信息，双击才拉数据 | 避免误点千万行表 |
| U2.3 | 偶尔清表的用户 | 右键能 Truncate / 复制 CREATE | 不用切到 SQL 标签 |
| U2.4 | 改了结构的用户 | F5 能刷新当前节点 | 不用断开重连 |

### 4.3 表数据浏览

| ID | As a | I want | So that |
|---|---|---|---|
| U3.1 | 浏览数据的用户 | 默认看前 1000 行，看到总行数 | 知道数据规模 |
| U3.2 | 找数据的用户 | WHERE 框过滤 + 列头排序 | 不用写 SQL |
| U3.3 | 修改数据的用户 | 双击改值，Enter 提交，Esc 撤销 | 直觉操作 |
| U3.4 | 多行修改的用户 | 改了多行后一次 Commit / Discard | 批量操作 |
| U3.5 | 录入数据的用户 | 表末尾插入新行，选中删除 | 不用写 INSERT/DELETE |
| U3.6 | 数据库审慎用户 | 无主键表编辑时被警告 | 不会误改多行 |

### 4.4 SQL 编辑执行

| ID | As a | I want | So that |
|---|---|---|---|
| U4.1 | 写 SQL 用户 | 多标签互不干扰 | 同时调几条查询 |
| U4.2 | 写多条 SQL 用户 | F9 跑全部，Ctrl+Enter 跑当前 | 沿用 HeidiSQL 习惯 |
| U4.3 | 查 SELECT 的用户 | 多 SELECT 出多个结果标签 | 对比结果 |
| U4.4 | DML 用户 | 看到"X 行受影响、Y ms" | 确认副作用 |
| U4.5 | 写错 SQL 的用户 | 错误行高亮 + MySQL 原文错误 | 知道改哪 |
| U4.6 | 跑慢查询想反悔的用户 | 点 Cancel 中断 | 不用 kill -9 |

---

## 5. 功能详细规格

### 5.1 连接管理（Session Manager）

#### 5.1.1 入口与界面

- **触发**：
  - 应用启动时：若 `sessions.json` 不存在或为空，自动打开 Session Manager 侧栏；否则打开主窗口 + 上次活跃 Session（若上次正常 Disconnect 则不自动连接，只展示空主区）。
  - 主菜单：`File → Session Manager…` (`Cmd+Shift+S`)。
  - 工具栏：`Sessions` 按钮。
- **形态**：右侧滑出的**非模态侧栏**，宽度 480pt（用户可拖拽，最小 360pt，不持久化），从主窗口右侧滑入；不挡住主区域，可同时操作。
- **布局**：
  ```
  ┌─ Session Manager ────────────────────┐
  │ [+] [⎘] [−]                          │ 工具栏
  │ ┌──────────────┐ ┌─────────────────┐ │
  │ │ Local MySQL  │ │ Name:  [______] │ │
  │ │ Staging      │ │ Host:  [______] │ │
  │ │ Production   │ │ ...             │ │
  │ │              │ │                 │ │
  │ │              │ │ [Test] [Save]   │ │
  │ │              │ │ [Open]          │ │
  │ └──────────────┘ └─────────────────┘ │
  └──────────────────────────────────────┘
  ```

#### 5.1.2 会话字段（`SessionConfig`）

| 字段 | 类型 | 默认 | 必填 | 校验规则 | 持久化位置 | 备注 |
|---|---|---|---|---|---|---|
| `id` | UUID | 新建时生成 | 是 | UUID v4 格式 | sessions.json | 用作 Keychain account |
| `name` | String | "Unnamed" | 是 | 1-64 字符；不能与其他会话同名（系统强制唯一） | sessions.json | 重名时保存时追加 " (2)" |
| `networkType` | enum | `.tcpIp` | 是 | 仅 `.tcpIp` 可选；其他选项 disabled | sessions.json | UI 上保留下拉，为 v0.2 SSH 隧道占位 |
| `hostname` | String | "127.0.0.1" | 是 | 非空；不验证 DNS 可达性（验证在 Test/Open 时） | sessions.json | |
| `user` | String | "root" | 是 | 1-32 字符 | sessions.json | MySQL 限制 32 |
| `password` | String | "" | 否 | 0-256 字符 | **Keychain** | UI 显示 `••••` |
| `port` | Int | 3306 | 是 | 1-65535 | sessions.json | |
| `defaultDatabases` | String | "" | 否 | 逗号分隔，每段符合 MySQL identifier 规则（不验证存在性） | sessions.json | 为空连接后不 USE |
| `useSSL` | Bool | false | 是 | — | sessions.json | 简单开关 |
| `comment` | String | "" | 否 | 0-1024 字符 | sessions.json | 多行文本 |
| `createdAt` | Date | new Date | 是 | ISO 8601 | sessions.json | 不在 UI 显示，仅审计 |
| `lastUsedAt` | Date? | nil | 否 | ISO 8601 | sessions.json | 每次成功 Open 后更新；UI 排序依据 |

#### 5.1.3 行为表

| 操作 | UI 触发 | 前置条件 | 行为 | 失败处理 |
|---|---|---|---|---|
| **新建** | 工具栏 `+` | — | 列表追加 "Unnamed N"（N 为下一个未占用编号），右侧表单空白，焦点到 Name 字段 | — |
| **复制** | 工具栏 `⎘` 或 `Cmd+D` | 选中一个会话 | 新建 "<原名> (copy)" 条目，所有字段含密码克隆，新 UUID | Keychain 复制失败时弹错误 |
| **删除** | 工具栏 `−` 或 `Delete` 键 | 选中一个会话 | 二次确认 dialog；确认后从列表移除，Keychain 清除该 account | Keychain 删除失败：保留 session 显示错误 |
| **编辑** | 表单字段任意输入 | — | 字段值改变 → 表单顶部出现 `Modified` 标签；`Save` 按钮启用 | 校验失败：字段红框 + tooltip |
| **保存** | `Save` 按钮 或 `Cmd+S` | 表单有修改 + 通过校验 | 写 sessions.json + Keychain；`Modified` 消失 | 写盘失败：弹错误，保留未保存状态 |
| **测试连接** | `Test` 按钮 | 表单字段通过校验 | 按当前表单值（包括未保存的）尝试 `connect → disconnect`；3s 内反馈成功/失败 | 失败：底部红条显示错误分类（§5.5.4） |
| **打开连接** | `Open` 按钮 或 双击列表项 或 `Enter` | 选中会话 + 字段有效 | 见 §5.1.4 状态机 | 同上 |
| **切换会话**（列表点击其他条目） | 单击其他列表项 | 当前有未保存修改 | 弹三选一确认："Save / Discard / Cancel" | 用户选 Cancel 则不切换 |
| **关闭侧栏** | Esc 或点 `×` | 当前有未保存修改 | 同上三选一 | 同上 |

#### 5.1.4 连接状态机

```
┌─────────┐  Open()    ┌────────────┐  success  ┌──────────┐
│  Idle   ├───────────►│ Connecting ├──────────►│ Connected │
└─────────┘            └──────┬─────┘           └─────┬────┘
     ▲                         │ failure              │ disconnect()
     │                         ▼                      ▼
     │                  ┌──────────┐           ┌──────────┐
     └──────────────────┤  Failed  │           │   Idle   │
       retry/edit       └──────────┘           └──────────┘
```

- **Idle → Connecting**：触发 `DBClient.connect(config)`；UI 按钮 disabled，列表项显示 spinner。
- **Connecting → Connected**：`connect` 成功返回；关闭 Session Manager 侧栏；主窗口切到该 Session；触发 `listDatabases` 填充对象树；更新 `lastUsedAt`。
- **Connecting → Failed**：在 `connectTimeoutMs`（默认 10000）超时或 `connect` 抛出；保持 Session Manager 打开；表单底部红色错误条；按钮恢复。
- **Failed → Connecting**：用户改字段后再次点 Open。
- **Connected → Idle**：用户点 Disconnect 或关闭主窗口；触发 `DBClient.disconnect()`，主区域清空。

#### 5.1.5 持久化规范

- **文件路径**：`~/Library/Application Support/MacHeidi/sessions.json`
- **文件权限**：`0600`（owner read/write only）
- **格式**：UTF-8 JSON，2 空格缩进
- **Schema**：
  ```json
  {
    "version": 1,
    "sessions": [
      {
        "id": "8a7f...",
        "name": "Local MySQL",
        "networkType": "tcpIp",
        "hostname": "127.0.0.1",
        "user": "root",
        "port": 3306,
        "defaultDatabases": "",
        "useSSL": false,
        "comment": "",
        "createdAt": "2026-06-11T10:00:00Z",
        "lastUsedAt": "2026-06-11T18:30:00Z"
      }
    ]
  }
  ```
- **密码**：`SecItemAdd` 写 Keychain，`service = "com.macheidi.session"`, `account = <session.id>`。
- **向前兼容**：读到 `version > 1` 时弹"This file was written by a newer version" 错误，**不强制升级**也**不丢弃**，只读模式打开应用。
- **崩溃保护**：写 sessions.json 用 `temp file → rename` 原子写。

#### 5.1.6 与已连接 Session 的关系

- 当前已连接的 Session 的 row，在 Session Manager 列表里显示 🟢 圆点。
- 已连接 Session **可以编辑**字段，但保存后**不立即重连**；状态提示："Changes will apply on next connection."
- 已连接 Session **不能删除**；需先 Disconnect。

---

### 5.2 对象树（Object Tree）

#### 5.2.1 数据结构

```
[Window]
 └─ Object Tree (NSOutlineView)
     ├─ Session Node (1..N)         // sessions.json 中全部会话
     │   ├─ [connected only] Database Node (1..N)
     │   │   ├─ Tables Group     // 虚拟分组
     │   │   │   └─ Table Node (1..M)
     │   │   └─ Views Group
     │   │       └─ View Node (1..M)
     │   │
     │   └─ [disconnected] (子节点不展开)
```

- 同时只允许一个 Session 处于 `Connected + Active` 状态。
- 其他 `Connected` Session 在树里子节点保留，但不能展开（点击展开会先切到 Active）。
- `Disconnected` Session 在树里只显示自己一行。

#### 5.2.2 节点状态

| 状态 | 图标 | 颜色 | 可操作 |
|---|---|---|---|
| Session - Disconnected | 🗄 灰 | secondary | 双击连接 / 右键 |
| Session - Connecting | 🗄 + spinner | accent | 取消（断开） |
| Session - Connected (Active) | 🗄 + 🟢 | primary | 全部 |
| Session - Connected (Inactive) | 🗄 + 🟢 | secondary | 点击转 Active |
| Database | 📁 | primary | 单击展开 / 右键 |
| Database - Loading | 📁 + spinner | primary | 不可操作 |
| Database - LoadFailed | 📁 + ⚠ | error | 右键重试 |
| Table | ⊞ | primary | 单击 / 双击 / 右键 |
| View | ⊟ | primary | 同 Table |

#### 5.2.3 交互矩阵（HeidiSQL 行为对齐）

| 节点 | 单击 | 双击 | 右键菜单（MVP）| 键盘 |
|---|---|---|---|---|
| Session (Disconnected) | 选中 | 触发 `Open()` | `Open` / `Edit Session…` / `Delete…` | Enter = Open |
| Session (Connected) | 切换为 Active | — | `Disconnect` / `Edit Session…` / `Refresh` | F5 = Refresh |
| Database | 选中并展开/折叠 | 右侧切到 "Database" 标签 | `Refresh` / `Copy Database Name` | F5 = Refresh |
| Table | 右侧切到 "Table" 标签（不查数据） | 右侧打开 "Data" 标签并加载 | `Refresh` / `Open Data` / `Truncate Table…` / `Copy CREATE Statement` / `Copy Table Name` | F5；Enter = 打开 Data |
| View | 同 Table | 同 Table（Data 标签为只读） | `Refresh` / `Open Data` / `Copy CREATE Statement` / `Copy View Name` | 同 Table |

#### 5.2.4 数据获取

| 节点展开/选中 | 查询 | 缓存策略 |
|---|---|---|
| Session connected | `SHOW DATABASES` | 启动时全量；F5 重新拉 |
| Database 展开 | `SHOW FULL TABLES FROM \`<db>\`` | 首次展开拉取；F5 重新拉；切回不重拉 |
| Table 选中 | `SHOW TABLE STATUS FROM \`<db>\` LIKE '<table>'` | 每次选中都拉（轻量） |
| 右键 Copy CREATE | `SHOW CREATE TABLE \`<db>\`.\`<table>\`` | 按需，不缓存 |

#### 5.2.5 F5 刷新行为

- 选中节点按 F5：
  - Session：重新 `SHOW DATABASES`，子树以差异方式更新（新增 db 出现，消失 db 移除，已展开 db 保留展开态）。
  - Database：重新 `SHOW FULL TABLES`，同上。
  - Table/View：重新 `SHOW TABLE STATUS`，刷新右侧元信息。
- 刷新过程中节点旁 spinner；失败时变 ⚠ 图标，hover 显示错误。

#### 5.2.6 Truncate Table 流程

1. 用户右键 → `Truncate Table…`
2. 弹模态确认：
   ```
   Truncate `<schema>.<table>`?

   This will delete ALL rows. This cannot be undone.

   [ ] I understand this operation cannot be undone.

   [Cancel]  [Truncate]
   ```
3. `Truncate` 按钮在勾选 checkbox 前 disabled。
4. 执行 `TRUNCATE TABLE \`<schema>\`.\`<table>\``。
5. 成功：关闭弹框；若该表当前有 Data Tab 打开，**强制刷新**该 Tab。
6. 失败：弹框保留，底部红字显示错误。

#### 5.2.7 边界 case

| Case | 处理 |
|---|---|
| 实例无数据库 | 树显示 "(no databases)" 灰字 |
| 数据库无表 | 数据库展开下显示 "(empty)" 灰字 |
| 表名含反引号 | 显示反引号；SQL 用 `\`` 双写转义 |
| 表名含非 BMP Unicode | 正常显示，确保 NSOutlineView UTF-16 安全 |
| 同名表（不同库） | 树里按库分隔，不会冲突 |
| 1000+ 表的数据库 | 不做虚拟化（MVP 假设单库表数 < 5000）；> 5000 时 log warn |

---

### 5.3 表数据浏览（Data Tab）

#### 5.3.1 布局（详细）

```
┌─────────────────────────────────────────────────────────────────────┐
│ Toolbar Row 1:                                                       │
│  [↻ Refresh] WHERE: [_____________________________] [Apply ▷]         │
│  Limit: [1000] Offset: [0] [< Prev] [Next >]                         │
├─────────────────────────────────────────────────────────────────────┤
│ Toolbar Row 2 (only when dirty):                                     │
│  ● 3 pending changes  [✓ Commit] [✕ Discard]                         │
├─────────────────────────────────────────────────────────────────────┤
│ ┃ # ┃ id ▲ │ name        │ created_at          │ status   │ ...     │
│ ┃───╋────────────────────────────────────────────────────────────────│
│ ┃ 1 │ 1    │ Alice        │ 2026-01-01 10:00:00 │ active   │ ...     │
│ ┃●2 │ 2    │ Bob (edited) │ 2026-01-02 11:00:00 │ pending  │ ...     │
│ ┃ 3 │ 3    │ Carol        │ (NULL)              │ inactive │ ...     │
│ ┃ + │      │              │                     │          │         │  ← 占位插入行
├─────────────────────────────────────────────────────────────────────┤
│ Status: Loaded 1000 / Total 23,847 rows · query 142ms                │
└─────────────────────────────────────────────────────────────────────┘
```

#### 5.3.2 加载流程

| 阶段 | 操作 | 超时 | 失败处理 |
|---|---|---|---|
| 1. 元数据 | `SHOW FULL COLUMNS FROM \`<db>\`.\`<table>\`` | 5s | 错误条 + Retry 按钮 |
| 2. 主键探测 | 从 §1 结果解析 `Key = 'PRI'` | — | 无 PK：状态栏永久显示 "⚠ No PK" |
| 3. 数据 | `SELECT * FROM \`<db>\`.\`<table>\` [ORDER BY ...] [WHERE ...] LIMIT 1000 OFFSET 0` | 30s | 错误条 + Retry |
| 4. 总数（并行） | `SELECT COUNT(*) FROM \`<db>\`.\`<table>\` [WHERE ...]` | 5s | 状态栏显示 "Total: ?" |

- 列宽：按列名 + 前 100 行内容估算，最小 60pt，最大 400pt；用户可拖拽，**不持久化**。
- 列顺序：表元数据原始顺序，**不可拖拽**（MVP）。

#### 5.3.3 排序

- 单击列头三态循环：`未排序 → ASC ↑ → DESC ↓ → 未排序`
- 同时只支持单列排序
- 实现：清空 ORDER BY 重新发查询；offset 重置为 0
- 排序请求触发时，有 Pending Edits 则弹"This will discard your changes. Continue?"

#### 5.3.4 WHERE 过滤

| 行为 | 规则 |
|---|---|
| 输入 | 接受裸 WHERE 子句（不带 `WHERE` 关键字） |
| 提交 | 回车或点 Apply 按钮 |
| 语法错 | 输入框红框；tooltip = MySQL 错误原文；状态栏红字；**不刷新表格** |
| 清空 | 清空输入框回车 → 恢复无过滤 |
| 与 Pending Edits 冲突 | 同 §5.3.3：弹确认 |
| 历史 | MVP 不做历史；v0.2 加 |

#### 5.3.5 分页

- `Next` / `Prev` 按钮：offset 加减 limit
- offset 输入框：手动改后回车应用
- limit 输入框：默认 1000，可改；最大 100000（硬上限，超过截断并提示）
- offset = 0 时 Prev disabled；loaded < limit 时 Next disabled

#### 5.3.6 单元格编辑

##### 5.3.6.1 进入编辑

| 触发 | 行为 |
|---|---|
| 双击单元格 | 进入编辑 |
| 选中后按 Enter | 进入编辑 |
| 选中后按 F2 | 进入编辑 |
| 选中后键入字符 | 进入编辑并替换原值 |

##### 5.3.6.2 编辑器形态（按列类型，见 §A）

| MySQL 类型类 | UI |
|---|---|
| INT / BIGINT / DECIMAL / FLOAT / DOUBLE | `NSTextField`，数字键盘约束（仍允许-、.、e） |
| VARCHAR / CHAR / TEXT | `NSTextField`，单行；TEXT 双击单元格弹出多行编辑器 |
| LONGTEXT / MEDIUMTEXT | 单元格只显示 256 字符预览，双击弹多行编辑器 |
| DATE / DATETIME / TIMESTAMP / TIME | `NSTextField`，placeholder 显示 ISO 8601 格式 |
| TINYINT(1) / BOOL | 复选框（true/false 显示 ✓/✗） |
| ENUM | `NSPopUpButton`（下拉） |
| SET | `NSPopUpButton` + 多选 dialog |
| BLOB / VARBINARY | 显示 `[BLOB N bytes]`，**只读**（MVP 不支持编辑） |
| JSON | 单元格显示 256 字符预览，双击弹多行编辑器 |
| GEOMETRY 等空间类型 | 显示 `[GEOMETRY]`，**只读** |
| NULL | 显示斜体 `(NULL)`；右键菜单 "Set NULL" / "Unset NULL" |

##### 5.3.6.3 提交单元格编辑

| 触发 | 行为 |
|---|---|
| Enter | 提交，焦点移到下一行同列 |
| Tab | 提交，焦点移到同行下一列；最后列则到下一行第一列 |
| Shift+Tab | 提交，焦点向左 |
| Esc | 取消，恢复原值 |
| 点击其他单元格 | 提交 |
| 点击非表格区 | 提交 |

提交后：
- 值与原值相同 → 不变 dirty
- 值不同 → 该单元格高亮黄色 + 行头变 ● + Pending Edits 计数 +1

##### 5.3.6.4 值校验

- 类型不匹配（如 INT 列输入 "abc"）：单元格保持编辑态 + 红框 + tooltip "Invalid INT value"
- NOT NULL 列设 NULL：同上 "Column does not allow NULL"
- 超长字符串（> column.maxLength）：截断 + 警告
- 越界数值（DECIMAL 超精度）：保持编辑态 + 红框

#### 5.3.7 提交挂起编辑

##### 5.3.7.1 Commit 流程

```
BEGIN;
  -- 按 dirty 行的原始顺序
  UPDATE ... WHERE <pk>=...;
  UPDATE ... WHERE <pk>=...;
  -- 插入行
  INSERT INTO ... (...) VALUES (...);
  -- 删除行
  DELETE FROM ... WHERE <pk> IN (...);
COMMIT;
```

- 单事务包裹所有 UPDATE / INSERT / DELETE
- 任一失败 → ROLLBACK，状态栏红字显示失败语句和错误
- 成功后：
  - 清除全部 dirty 标记
  - **重新拉取**这些行的最新值（按 pk SELECT）填回（处理 DEFAULT、TRIGGER、auto_increment）
  - 插入行的 `LAST_INSERT_ID()` 填回主键列

##### 5.3.7.2 无主键表的 UPDATE / DELETE

- 在 Commit 之前**一次性**弹确认：
  ```
  Table `<schema>.<table>` has no primary key.

  UPDATE/DELETE statements will use ALL columns in WHERE clause,
  which may match MULTIPLE rows unintentionally.

  Generated WHERE clause example:
    WHERE id <=> 1 AND name <=> 'Alice' AND created_at <=> '...'

  Affected operations: 2 UPDATEs, 1 DELETE

  [Cancel]  [Continue]
  ```
- 用户确认后，按全部列原值生成 WHERE，使用 `<=>` (NULL-safe equal) 处理 NULL 值
- BLOB / TEXT / JSON 列从 WHERE 中**排除**（避免巨型 SQL）；状态栏额外警告
- 若 BLOB 等被排除列**也被编辑**，则放弃 Commit 并提示用户先加主键

##### 5.3.7.3 Discard

- 弹一次性确认 "Discard N pending changes?"
- 确认后恢复全部原值，清除 dirty 标记

#### 5.3.8 插入行

- 数据网格末尾**永远**显示一行占位：`[+ Click to add row]`
- 点击占位行 → 在它上方插入一个新空行，行头变 `●+`，焦点到第一个可编辑列
- 新行所有列默认值：
  - 有 DEFAULT：显示 `<default>` 占位灰字
  - AUTO_INCREMENT：显示 `<auto>` 占位灰字
  - NOT NULL 无 DEFAULT：必须填，否则 Commit 时报错
  - 其他：NULL
- 提交 INSERT 时只发送用户实际改过的列；其他用数据库默认

#### 5.3.9 删除行

| 触发 | 行为 |
|---|---|
| 选中行 + Delete 键 | 标记删除 |
| 右键 "Delete Row(s)" | 标记删除 |

- 标记后行变灰 + 划掉效果 + 行头 `●−`；不立即 SQL
- 进入 Pending Deletes 集合，由 Commit/Discard 统一处理
- 在 Commit 前可右键 "Unmark delete" 恢复

#### 5.3.10 与其他 Tab / 操作的并发

- 同一表打开的 Data Tab 只有一个；从树重复双击 → 切到已打开 Tab，**不刷新**
- Truncate / DROP / 结构变更后，已打开的 Data Tab **不自动**刷新，但顶部出现黄条 "Schema may have changed. [Refresh]"

---

### 5.4 SQL 编辑执行（Query Tab）

#### 5.4.1 标签管理

| 操作 | 触发 | 行为 |
|---|---|---|
| 新建 Query Tab | `Cmd+T` 或工具栏 `New Query` 或菜单 `File → New Query` | 在当前 Tab 右侧插入 "Query #N"，N 为下一个未占用编号；焦点到编辑器 |
| 关闭 Tab | `Cmd+W` 或 Tab 上 `×` | 若 SQL 文本非空且与上次保存/打开时不同 → 弹"Discard changes?"；确认则关闭 |
| 切换 Tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` 或点击 | 切换；每个 Tab 的 SQL 文本、光标位置、结果集、滚动位置**完全独立保留** |
| 重命名 | 双击 Tab 标题 | 进入编辑；MVP **不实现**，固定 "Query #N" |
| 拖拽重排 | — | MVP **不实现** |

- Tab 最大数 **无限制**（受内存限制；> 50 时 log warn）
- 关闭 Session 时关闭其下全部 Query Tab，统一弹一次"Discard N unsaved queries?"

#### 5.4.2 编辑器规格

| 项 | 规格 |
|---|---|
| 实现 | `NSTextView` 子类 + 自定义 `NSLayoutManager` |
| 字体 | `SF Mono Regular 12pt`（MVP 不可改） |
| 行号 | 左侧 gutter，灰色等宽 |
| 缩进 | 4 空格；Tab 键插入 4 空格 |
| 自动缩进 | 按 Enter 时继承上一行缩进 |
| 软换行 | 关闭（横向滚动） |
| 高亮（MVP 4 类） | 关键字 蓝、字符串 红、注释 灰、数字 紫 |
| 语法高亮 token 来源 | 手写 MySQL keyword 列表 + 简易 lexer（不接入 ANTLR） |
| 自动补全 | **不做**（v0.6） |
| 括号匹配 | **不做** |
| 多光标 | **不做** |
| 撤销/重做 | `Cmd+Z` / `Cmd+Shift+Z`，系统默认行为 |
| 查找/替换 | `Cmd+F` / `Cmd+Alt+F`，系统默认 `NSTextFinder` |
| 复制/粘贴 | 系统默认 |

#### 5.4.3 SQL 拆分（用于 F9 与 Ctrl+Enter）

**拆分规则**：

1. 单字符状态机：扫描 SQL 文本
2. 跟踪状态：
   - `inSingleQuote`：遇 `'` 翻转；`\'` 不翻转
   - `inDoubleQuote`：遇 `"` 翻转；`\"` 不翻转
   - `inBacktick`：遇 `` ` `` 翻转
   - `inLineComment`：遇 `--` 开始（前后需空白或行首），遇 `\n` 结束
   - `inBlockComment`：遇 `/*` 开始，遇 `*/` 结束（不嵌套）
3. 在四种 in 状态都为 false 时，`;` 作为语句分隔符
4. 每条语句 trim 空白后丢弃空语句

**Ctrl+Enter 当前语句界定**：

- 若有选中 → 整段作为一条（包含其中的 `;`，发给 MySQL；MySQL 默认单条只接受一条，多条会报错；这个行为对齐 HeidiSQL）
- 否则按 §5.4.3 拆分整个编辑器内容；找到光标所在的语句

#### 5.4.4 执行流程

```
F9 (Run All)              Ctrl+Enter (Run Current)
       │                            │
       ▼                            ▼
┌─────────────────┐         ┌─────────────────┐
│ Split into N    │         │ Identify single │
│ statements      │         │ statement       │
└────────┬────────┘         └────────┬────────┘
         │                           │
         ▼                           ▼
   For each stmt:                Single stmt
         │                           │
         ▼                           ▼
   ┌──────────────────────────────────────────┐
   │ Determine kind:                          │
   │  - SELECT-like → query(), get ResultSet  │
   │  - DML/DDL    → exec(), get ExecResult   │
   └─────────────────┬────────────────────────┘
                     ▼
   ┌──────────────────────────────────────────┐
   │ On success: append to Messages panel +   │
   │   create Result Sub-Tab (if SELECT)      │
   │ On error: append to Messages panel red + │
   │   highlight statement line in editor +   │
   │   F9: STOP processing remaining stmts    │
   │   Ctrl+Enter: 不影响其他（单条）        │
   └──────────────────────────────────────────┘
```

##### 5.4.4.1 SELECT-like 判定

- 第一个非空白非注释 token（大小写不敏感）属于：`SELECT / SHOW / DESCRIBE / DESC / EXPLAIN / WITH / VALUES / TABLE / CALL`
- 否则按 `exec` 处理（DML/DDL）

##### 5.4.4.2 多结果集（如 CALL stored procedure）

- 一条 CALL 可能返回多个结果集 → 在 Result Sub-Tab 区追加多个

#### 5.4.5 结果展示

##### 5.4.5.1 SELECT 结果（`Result #N` 子标签）

- 复用 §5.3 的数据网格组件，但**默认只读**
- 列头按列在 ResultSet 中的顺序
- 列宽自适应同 §5.3.2
- 排序：点列头**客户端排**（因为结果集已在内存）
- 复制：
  - `Cmd+C` 复制选中单元格（TSV）
  - 选中行 → `Cmd+C` 复制整行（TSV）
  - 右键 `Copy as SQL`（生成 INSERT 语句，作为 v0.2 stretch goal）
- 子标签关闭按钮：`×`；关闭最后一个时 Result 区域整体隐藏

##### 5.4.5.2 DML/DDL 结果（Messages 面板）

- 不创建子标签
- 在 Query Tab 下方"Messages"面板追加一条：
  ```
  [14:02:31.123] /* Query #1 stmt 2 */ UPDATE users SET ... — 3 rows affected, 12 ms
  ```
- 若包含 `LAST_INSERT_ID()` 信息，追加 ` (last_insert_id=42)`

##### 5.4.5.3 错误展示

- Messages 面板红字：
  ```
  [14:02:33.456] /* Query #1 stmt 3 */ ERROR 1064 (42000): You have an error in your SQL syntax; ... near 'FRM users' at line 1
  ```
- 编辑器：错误语句所在的所有行，行号 gutter 显示 ✕ 图标 + 行背景浅红
- 用户编辑该行后高亮自动消失

#### 5.4.6 取消查询

##### 5.4.6.1 触发

- 执行中（query 或 exec 未返回），状态栏 spinner + `[Cancel] Cmd+.`
- 点击 Cancel 或按 Cmd+.

##### 5.4.6.2 实现

- 在 `DBClient.cancel()` 中：
  1. 用 `connectionId`（之前 `connect` 时获取的 `CONNECTION_ID()`）
  2. **开新连接**（不复用执行中的连接），发送 `KILL QUERY <connectionId>`
  3. 新连接用完即关
- 执行中的 query/exec 收到 MySQL 错误码 `1317 (Query execution was interrupted)` → 归类为 `DBError.cancelled`

##### 5.4.6.3 UI 反馈

- 成功：Messages 面板灰字 `[14:02:35.789] /* Query #1 stmt 1 */ Query cancelled by user`
- 失败（已执行完）：吞掉，无提示
- KILL QUERY 本身失败（权限不足）：Messages 面板红字 `Cancel failed: <error>`

#### 5.4.7 Query Tab 与 Session 的关系

- Query Tab 隶属于 Session（不能跨 Session）
- 切换 Active Session 时，Query Tab 切到该 Session 的 Tab 集合
- 每个 Query Tab 复用 Session 的**主连接**（同 §5.5.1）执行查询；同一时刻只能跑一条查询

---

### 5.5 基础设施（Cross-Cutting）

#### 5.5.1 `DBClient` 协议

```swift
public protocol DBClient: Actor {
    /// 当前协议连接的 MySQL CONNECTION_ID()，连接前为 nil
    var connectionId: UInt64? { get }

    /// 当前连接状态
    var state: DBClientState { get }

    /// 建立 TCP + 协议握手 + USE default db（若指定）
    /// - Throws: DBError.network / .auth / .unknown
    func connect(_ config: ConnectionConfig) async throws

    /// 优雅关闭；若已断开则 no-op
    func disconnect() async

    /// SHOW DATABASES → 排除 information_schema/performance_schema/mysql/sys（可配）
    func listDatabases(includeSystem: Bool) async throws -> [String]

    /// SHOW FULL TABLES FROM `<db>`
    func listTables(database: String) async throws -> [TableMeta]

    /// SHOW FULL COLUMNS FROM `<db>`.`<table>` + SHOW INDEX
    func describeTable(database: String, table: String) async throws -> TableSchema

    /// 仅用于 SELECT-like；返回完整内存 ResultSet
    /// - Throws: DBError.syntax / .server / .cancelled / ...
    func query(_ sql: String) async throws -> ResultSet

    /// 用于 DML/DDL
    func exec(_ sql: String) async throws -> ExecResult

    /// 在新连接上 KILL QUERY；不影响调用方等待中的 query/exec
    func cancel() async
}

public enum DBClientState {
    case idle
    case connecting
    case connected
    case disconnected(reason: DisconnectReason)
}

public struct ConnectionConfig {
    public let hostname: String
    public let port: Int
    public let user: String
    public let password: String  // 明文，从 Keychain 取
    public let defaultDatabase: String?
    public let useSSL: Bool
    public let connectTimeout: Duration  // 默认 10s
    public let queryTimeout: Duration?    // 默认 nil（不超时）
}

public struct TableMeta {
    public let name: String
    public let kind: TableKind   // .table / .view
    public let engine: String?
    public let rowCountEstimate: UInt64?  // 来自 SHOW TABLE STATUS
    public let comment: String
}

public struct TableSchema {
    public let columns: [ColumnMeta]
    public let primaryKey: [String]   // 空数组 = 无 PK
    public let indices: [IndexMeta]
}

public struct ColumnMeta {
    public let name: String
    public let mysqlType: String       // 原始类型字符串 e.g. "varchar(255)"
    public let normalizedType: NormalizedType  // .int / .string / .blob / ...
    public let nullable: Bool
    public let defaultValue: CellValue?
    public let isAutoIncrement: Bool
    public let isUnsigned: Bool
    public let maxLength: Int?
    public let precision: Int?
    public let scale: Int?
    public let comment: String
}

public struct ResultSet {
    public let columns: [ColumnMeta]
    public let rows: [[CellValue]]
    public let executionTime: Duration
    public let warnings: [String]   // SHOW WARNINGS 结果
}

public struct ExecResult {
    public let affectedRows: UInt64
    public let lastInsertId: UInt64?
    public let executionTime: Duration
    public let warnings: [String]
}

public enum CellValue: Equatable, Sendable {
    case null
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case decimal(String)        // 字符串保精度
    case string(String)
    case bool(Bool)
    case date(Date)
    case datetime(Date)
    case time(String)           // MySQL TIME 不一定 < 24h，用字符串
    case blob(Data)
    case json(String)
    case unknown(String)        // 兜底
}
```

##### 5.5.1.1 测试替身

- `MockDBClient`：内存实现，BDD/TDD 单元测试默认使用
- `MySQLClient`：基于 MySQLNIO 的真实实现，仅集成测试使用

#### 5.5.2 MySQL 驱动选型

| 候选 | 优势 | 劣势 | 决策 |
|---|---|---|---|
| MySQLNIO | Swift 原生、纯异步、SwiftNIO 生态、维护活跃 | 不支持老协议（MySQL 5.6-）；caching_sha2_password 需验证 | **首选** |
| MySQLKit | MySQLNIO 之上的 ORM 风格封装 | 我们要的是裸协议；ORM 反而碍事 | 不用 |
| libmysqlclient | 协议覆盖最全 | C 桥接、内存安全负担、license（GPL） | 兜底（R1） |
| Vapor + MySQL driver | — | 引入整个 Vapor 生态 | 不用 |

**第一个集成测试必须验证**：

- caching_sha2_password 认证（MySQL 8 默认）
- mysql_native_password 认证（MySQL 5.7 默认）
- KILL QUERY 的实际行为
- SSL 握手

不通过则启动 R1 应急方案（封装 libmysqlclient）。

#### 5.5.3 类型映射（结果集 → `CellValue`）

完整映射表见 §A。关键决策：

- DECIMAL 用 `.decimal(String)` 不用 Double，保精度
- TIMESTAMP / DATETIME 用 `.datetime(Date)`，时区按服务器 `@@time_zone` 解释为 UTC（连接时探测）
- TIME 用 `.time(String)`，因为 MySQL TIME 范围 `-838:59:59` 到 `838:59:59`，超出 24h
- BIT(n) 用 `.uint(UInt64)`
- JSON 列单独类型 `.json(String)`，UI 显示绿色 + 双击显示格式化

#### 5.5.4 错误归一化

##### 5.5.4.1 `DBError` 定义

```swift
public enum DBError: Error, Equatable {
    case network(message: String, underlying: Error?)
    case auth(message: String, mysqlErrno: Int?)
    case syntax(mysqlErrno: Int, sqlState: String, message: String)
    case constraint(mysqlErrno: Int, sqlState: String, message: String)
    case timeout(message: String)
    case cancelled
    case server(mysqlErrno: Int, sqlState: String, message: String)
    case unknown(message: String, underlying: Error?)
}
```

##### 5.5.4.2 MySQL errno → `DBError` 映射

| MySQL errno | SQLSTATE | DBError | UI 处理 |
|---|---|---|---|
| 2002, 2003 | HY000 | `.network` | Session Manager 红条 |
| 2005 (Unknown host) | HY000 | `.network` | 同上 |
| 1045 (Access denied) | 28000 | `.auth` | 同上 |
| 1044 (DB access denied) | 42000 | `.auth` | 同上 |
| 1049 (Unknown database) | 42000 | `.auth` | 同上 |
| 1064 (Syntax) | 42000 | `.syntax` | 编辑器高亮 + Messages |
| 1054 (Unknown column) | 42S22 | `.syntax` | 同上 |
| 1146 (Unknown table) | 42S02 | `.syntax` | 同上 |
| 1062 (Duplicate entry) | 23000 | `.constraint` | Data Tab 状态栏 + Messages |
| 1452 (FK constraint) | 23000 | `.constraint` | 同上 |
| 1451 (FK ref) | 23000 | `.constraint` | 同上 |
| 1317 (Interrupted) | 70100 | `.cancelled` | Messages 灰字 |
| 1205 (Lock wait timeout) | HY000 | `.timeout` | Messages 红字 |
| 2013 (Lost connection) | HY000 | `.network` | 主区域 banner "Connection lost. [Reconnect]" |
| 1290 (Server running with read-only) | HY000 | `.server` | Messages |
| Default | any | `.server` 或 `.unknown` | Messages |

##### 5.5.4.3 UI 反馈策略表

| DBError case | 位置 | 颜色 | 持续 | 动作 |
|---|---|---|---|---|
| `.network` (连接阶段) | Session Manager 表单底部 | 红 | 直到改字段 | 可重试 |
| `.network` (运行阶段) | 主窗口顶部 banner | 红 | 直到 Reconnect | `[Reconnect]` 按钮 |
| `.auth` | Session Manager 表单底部 | 红 | 同上 | 可重试 |
| `.syntax` | 编辑器行高亮 + Messages 面板 | 红 | 改 SQL 后消失 | — |
| `.constraint` | Messages 面板 + Data Tab 状态栏 | 红 | 直到下次操作 | — |
| `.timeout` | Messages 面板 | 红 | 同上 | — |
| `.cancelled` | Messages 面板 | 灰 | 同上 | — |
| `.server` | Messages 面板 | 红 | 同上 | 复制错误按钮 |
| `.unknown` | 模态错误对话框 | 红 | 用户关闭 | `[Copy Details]` |

#### 5.5.5 Keychain 封装

```swift
public protocol KeychainStore {
    func save(account: String, password: String) throws
    func read(account: String) throws -> String?
    func delete(account: String) throws
}

public enum KeychainError: Error {
    case unhandled(OSStatus)
    case invalidData
    case denied  // 用户拒绝授权
}
```

- 实现：`SecItemAdd / SecItemCopyMatching / SecItemDelete`
- `service` = `"com.macheidi.session"`
- `accessControl` = `.userPresence`（MVP 不要求 Touch ID，仅 unlocked-this-session）
- 测试：`MockKeychainStore` 内存实现

#### 5.5.6 持久化封装

```swift
public protocol SessionStore {
    func loadAll() throws -> [SessionConfig]
    func save(_ sessions: [SessionConfig]) throws
}
```

- 实现：原子写 `sessions.json`
- 测试：`InMemorySessionStore`

#### 5.5.7 连接生命周期

- 一个 Session 在 Active 期间持有**一个主 `DBClient` 实例**
- 该实例**串行**执行所有上层请求（基于 Actor）
- Query Tab 的 SQL 执行排队跑；同一时刻只一条
- KILL QUERY 在临时新建的 `DBClient` 上跑，不抢占主连接
- 断线（`.network` 2013）：标 Disconnected；显示顶部 banner；用户点 Reconnect 触发 Open

---

## 6. 信息架构与导航

### 6.1 顶层窗口

```
┌─ MacHeidi — Local MySQL ─────────────────────────────────────[─][□][×]┐
│ NSToolbar:  [⇆ Session▼] [↻] [+ Query] [⏏ Disconnect] [⋯]              │
├──────────┬───────────────────────────────────────────────────────────┤
│          │ [Host] [Database: app_prod] [Table: users] [Data] [Query #1] [+] │
│ Object   ├───────────────────────────────────────────────────────────┤
│ Tree     │                                                           │
│          │                  Main Content                             │
│ (Sidebar)│              (per active tab)                             │
│          │                                                           │
│          ├─── Messages Panel (collapsible) ──────────────────────────┤
│          │ [14:02:31] /* Q#1 */ SELECT ... — 1000 rows, 23 ms        │
│          │ [14:02:35] /* Q#1 */ ERROR 1064: ...                      │
├──────────┴───────────────────────────────────────────────────────────┤
│ Status: ●Connected · 8.0.35 · sql_mode=STRICT · @@time_zone=+00:00   │
│         [▶ Running stmt 2/5...] [Cancel]                              │
└────────────────────────────────────────────────────────────────────────┘
```

### 6.2 主区域 Tab 类型

| Tab | 触发 | 关闭 | 数量限制 |
|---|---|---|---|
| **Host** | 选中 Session 节点 | 不可关闭，跟随 Session | 0..1 |
| **Database** | 选中 Database 节点 | 不可关闭，跟随选中 | 0..1 |
| **Table** | 单击 Table/View | 不可关闭，跟随选中 | 0..1 |
| **Data** | 双击 Table/View 或右键 Open Data | 可关闭 | 每个表 0..1 |
| **Query #N** | `Cmd+T` | 可关闭 | 无上限 |

> Host / Database / Table 三个 Tab **互斥**显示（同时只有一个），跟随对象树选中切换。
> Data 与 Query 是**用户主动打开**的持久 Tab，可同时多个。

### 6.3 Host / Database / Table Tab 内容（MVP 简版）

| Tab | 内容 |
|---|---|
| **Host** | MySQL 版本、`@@hostname`、uptime、`@@time_zone`、`@@character_set_server`、`@@sql_mode` |
| **Database** | 该库的表 + 视图列表（`SHOW TABLE STATUS`：name / engine / rows / size / collation） |
| **Table** | `SHOW TABLE STATUS` 摘要 + `DESCRIBE` 列表（列名 / 类型 / 可空 / 默认 / 注释） |

> 这三个 Tab MVP 只展示**信息**，不允许任何操作（编辑列、加索引等都在 v0.3 DDL UI）。

### 6.4 状态栏

| 元素 | 来源 | 更新时机 |
|---|---|---|
| 连接圆点 | `DBClient.state` | 状态变更 |
| 服务器版本 | 连接后 `SELECT VERSION()` | 连接成功 |
| `sql_mode` | `SELECT @@sql_mode` | 连接成功 |
| `@@time_zone` | `SELECT @@time_zone` | 连接成功 |
| 执行进度 | 当前 query/exec | 开始/结束 |
| Cancel 按钮 | 执行中显示 | 同上 |

---

## 7. 键盘快捷键（完整表）

> macOS 习惯优先；与 HeidiSQL 冲突时给出对齐选择。

### 7.1 全局

| 快捷键 | 行为 | 对齐 HeidiSQL |
|---|---|---|
| `Cmd+N` | 新建 Session（打开 Session Manager + 新建） | 新增 |
| `Cmd+Shift+S` | 打开 / 关闭 Session Manager | 新增 |
| `Cmd+T` | 新建 Query Tab | HeidiSQL = `Ctrl+T` ✓ |
| `Cmd+W` | 关闭当前 Tab | HeidiSQL = `Ctrl+F4` |
| `Cmd+,` | 偏好设置（MVP 仅空壳） | macOS 标准 |
| `Cmd+Q` | 退出 | macOS 标准 |
| `Cmd+R` | 刷新当前节点（等价 F5） | 新增 |
| `Cmd+.` | 取消执行中的查询 | 新增 |
| `Cmd+Ctrl+F` | 进入/退出全屏 | macOS 标准 |
| `Cmd+\` | 切换对象树侧栏 | 新增 |

### 7.2 对象树

| 快捷键 | 行为 |
|---|---|
| `↑ / ↓` | 上下导航 |
| `← / →` | 折叠 / 展开 |
| `Enter` | Session: Open / Table: 打开 Data Tab |
| `Space` | 同 Enter |
| `F5` | 刷新当前节点 |
| `Delete` | 删除 Session（仅 Disconnected） |
| `Cmd+C` | 复制节点名 |

### 7.3 Data Tab

| 快捷键 | 行为 |
|---|---|
| `↑↓←→` | 单元格导航（编辑态外） |
| `Enter` / `F2` | 进入编辑 |
| `Esc` | 取消编辑 |
| `Tab / Shift+Tab` | 提交并左右移动 |
| `Cmd+Enter` | 提交所有 Pending Edits（Commit） |
| `Cmd+Z / Cmd+Shift+Z` | Discard 后立即可撤销（不与 SQL 撤销冲突） |
| `Delete` | 标记选中行为删除 |
| `Cmd+N` 在表格焦点时 | 新增行（焦点到占位行） |
| `Cmd+F` | 聚焦 WHERE 输入框 |
| `Cmd+C` | 复制选中单元格（TSV） |
| `F5` | 刷新表数据 |

### 7.4 Query Tab

| 快捷键 | 行为 | 对齐 HeidiSQL |
|---|---|---|
| **F9** | Run All | ✓ |
| **Ctrl+Enter** | Run Current | ✓ |
| **Cmd+/** | 注释/取消注释当前行/选中 | 新增 macOS |
| `Cmd+L` | 跳到行号 | 新增 |
| `Cmd+F` | 查找 | macOS |
| `Cmd+Alt+F` | 替换 | macOS |
| `Cmd+A` | 全选 | macOS |
| `Cmd+]` / `Cmd+[` | 增减缩进 | macOS |

### 7.5 冲突解决

- `Ctrl+Enter` 在 macOS 上不冲突任何系统快捷键，保留 HeidiSQL 习惯
- `F9` 在 macOS 上默认是 Mission Control 触发；用户需在系统设置改 fn key 行为；MVP 接受这个不便，**Cmd+R** 作为不冲突的备选（**注**：因 Cmd+R 已给"刷新对象树"，需用户切换焦点；后续可考虑改为 Cmd+Enter = Run Current, Cmd+Shift+Enter = Run All，由 v0.2 决定）

---

## 8. 视觉与设计原则

### 8.1 硬性约束

1. **原生优先**：所有控件使用 SwiftUI / AppKit；**不**引入 WebView。
2. **跟随系统**：颜色、圆角、间距、字体遵循 macOS HIG；自动支持 Light/Dark mode；MVP **仅英文**。
3. **不模仿 Windows 像素**：HeidiSQL 的 16 色图标、密集表单、Windows 风滚动条**不照搬**。

### 8.2 控件实现矩阵

| UI 元素 | 实现 | 理由 |
|---|---|---|
| 数据网格 / 结果网格 | **NSTableView**（包 SwiftUI） | SwiftUI Table 渲染 10k+ 行卡顿 |
| SQL 编辑器 | **NSTextView** 子类 | SwiftUI 无法做行号、高亮 |
| 对象树 | **NSOutlineView** | SwiftUI List 不支持高效展开/拖拽 |
| Session Manager | SwiftUI | 简单表单足够 |
| Tabs | SwiftUI `TabView` + 自定义样式 | 视觉一致 |
| 工具栏 | `NSToolbar` | 原生 |
| 状态栏 | SwiftUI HStack | 灵活 |
| 模态对话框 | SwiftUI `alert/confirmationDialog` | 标准 |

### 8.3 调色与排版

- 全局色：使用系统 `accentColor`，跟随用户系统设置
- 错误色：`Color.red.opacity(0.85)`
- 警告色：`Color.orange.opacity(0.85)`
- Dirty 行高亮：`Color.yellow.opacity(0.18)`（Light）/ `Color.yellow.opacity(0.25)`（Dark）
- NULL 单元格字色：`secondaryLabel`，斜体
- 等宽场景（SQL 编辑器、数据网格）：`SF Mono`
- 其他：系统字体

### 8.4 图标

- 系统 SF Symbols 优先
- 自定义图标（如 MySQL logo）：限定 Session 节点
- 不引入 Material / FontAwesome 等第三方图标库

---

## 9. 非功能需求

### 9.1 性能目标（验收方向）

| 项 | 目标（M 系列芯片，本地 MySQL） | 测量方法 |
|---|---|---|
| 冷启动到主窗口 | ≤ 1.5s | 手工掐表，10 次中位数 |
| 内存（空闲） | ≤ 150 MB | Activity Monitor |
| 内存（10k 行表打开） | ≤ 400 MB | Activity Monitor |
| 1000 行表加载 | ≤ 500 ms | 状态栏耗时 |
| 100k 行表滚动 FPS | ≥ 50 | Instruments |
| Cancel → UI 反馈 | ≤ 1s | 手工 |
| 切 Query Tab | ≤ 50ms | 手工感知 |

### 9.2 健壮性

- 不允许：未捕获异常 / 主线程卡死 > 3s / 内存泄漏 > 10 MB/小时
- 网络断开自动检测（heartbeat 30s 一次 `SELECT 1`）；断开后 UI 提示
- 写操作（sessions.json / Keychain）失败必须有 UI 反馈

### 9.3 安装与发布

- 安装包格式：`.dmg`（含 .app 拖拽到 Applications）
- 大小：≤ 30 MB
- 架构：Universal Binary（arm64 + x86_64）
- 最低系统：macOS 13 Ventura
- 签名：Developer ID 签名 + Notarization（避免 Gatekeeper 警告）
- 公证：必须

### 9.4 国际化

- MVP：**仅英文 UI**（v0.2 加简体中文）
- 全部 UI 字符串通过 `LocalizedStringKey` 暴露，便于 v0.2 一键加 zh-Hans
- 数据库标识符（库名、表名、列名）按 UTF-8 显示，不做大小写转换

### 9.5 可访问性

- VoiceOver 兼容（所有控件有 accessibility label）
- 键盘可达所有功能（无需鼠标完成完整流程）
- 高对比度模式跟随系统
- MVP **不**做：动态字体放大（数据网格固定 12pt）

---

## 10. 安全与隐私

| 项 | 要求 | 测试 |
|---|---|---|
| 密码存储 | 仅 macOS Keychain，**不**写日志、**不**写配置文件 | 检查 sessions.json + 日志 |
| 配置文件权限 | sessions.json = 0600 | `stat` 验证 |
| 错误日志 | 默认写 `~/Library/Logs/MacHeidi/macheidi.log` | 检查不含密码 |
| 日志内容 | **不**包含查询结果数据、**不**包含 SQL 中的字面值 | 单元测试 |
| 遥测 | **无** | 网络抓包验证 |
| 自动更新 | **无** | 同上 |
| 网络出站 | 仅连用户配置的 MySQL host | 同上 |
| SSL | 使用系统 trust store；MVP 不做自定义 CA | 集成测试 |
| 内存中的密码 | 连接成功后**立即** zeroize | 代码审计 |
| URL Scheme | **不**注册（避免外部唤起） | Info.plist 验证 |

---

## 11. 后续版本路线图

| 版本 | 内容 |
|---|---|
| **v0.2** | 中文 UI、数据导出（CSV/SQL）、查询历史持久化、SSH 隧道 |
| v0.3 | 表结构编辑（DDL UI）、索引/外键可视化、SSL 自定义证书 |
| v0.4 | PostgreSQL 支持（复用 `DBClient` 协议） |
| v0.5 | 存储过程 / 函数 / 触发器 / 事件 |
| v0.6 | 数据导入（CSV）、SQL 自动补全、SQL 美化 |
| v1.0 | 公测发布、遥测（opt-out）、自动更新 |
| v1.x | MSSQL / SQLite、用户权限管理、进程列表 |

---

## 12. 验收标准（MVP 总）

### 12.1 功能验收

每个 §5 场景都必须有 BDD 测试覆盖，且通过：

| 场景 ID | 描述 | 测试层级 | 优先级 |
|---|---|---|---|
| S1.1 | 新建会话并持久化 | C+I | P0 |
| S1.2 | 双击会话连接成功 | E2E | P0 |
| S1.3 | 连接失败显示分类错误 | C+I | P0 |
| S1.4 | 编辑保存会话 | U+C | P0 |
| S1.5 | 删除会话二次确认 | C | P0 |
| S1.6 | 密码存 Keychain，不写明文 | U+I | P0 |
| S1.7 | 重启后会话还原 | I | P0 |
| S1.8 | 复制会话 | C | P1 |
| S2.1 | 列出数据库 | I | P0 |
| S2.2 | 列出表与视图 | I | P0 |
| S2.3 | 单击表查元信息 | C | P0 |
| S2.4 | 双击表打开 Data Tab | E2E | P0 |
| S2.5 | 右键菜单 - Truncate | C+I | P1 |
| S2.5b | 右键菜单 - Copy CREATE | C+I | P1 |
| S2.6 | F5 刷新 | C | P0 |
| S3.1 | 默认分页加载 + 总数 | I | P0 |
| S3.2 | 列头排序三态 | C+I | P0 |
| S3.3 | WHERE 过滤回车刷新 | I | P0 |
| S3.4 | 单元格双击编辑 | C | P0 |
| S3.5 | 多行挂起编辑 + 行头标记 | C | P0 |
| S3.6a | Commit UPDATE（有 PK） | I | P0 |
| S3.6b | Commit UPDATE（无 PK + 警告） | I | P0 |
| S3.7 | NULL 显示与录入 | C | P1 |
| S3.8 | INSERT 新行 | I | P0 |
| S3.9 | DELETE 行 + 二次确认 | I | P0 |
| S4.1 | 新建 Query Tab + 输入 | C | P0 |
| S4.2 | F9 多条按序执行 | I | P0 |
| S4.3 | Ctrl+Enter 当前语句 | I | P0 |
| S4.4 | SELECT 结果多子标签 | C+I | P0 |
| S4.5 | DML 结果消息面板 | C+I | P0 |
| S4.6 | 语法错高亮 + 错误原文 | C+I | P0 |
| S4.7 | Cancel 长查询 | I | P1 |
| S4.8 | 多 Tab 状态独立 | C | P0 |
| S4.9 | SQL 语法高亮 | C | P1 |
| S5.1 | DBClient mock 协议 | U | P0 |
| S5.2 | MySQL 驱动适配集成 | I | P0 |
| S5.3 | 结果集 → ViewModel 映射 | U | P0 |
| S5.4 | 错误归一化 | U | P0 |

### 12.2 手工验收

对**本地 docker MySQL 8.0** 和 **MySQL 5.7** 两个实例分别走通 §4 全部用户故事；MySQL 5.7 实例由用户提供（暂未明确）。

### 12.3 非功能验收

§9 所有指标**测量并记录**，未达标项在 release notes 说明差距。

### 12.4 安全验收

§10 所有项**全部满足**，不允许任何一项妥协。

---

## 13. 风险与开放问题

| # | 风险 / 问题 | 概率 | 影响 | 处理 |
|---|---|---|---|---|
| R1 | MySQLNIO 对 MySQL 5.7 老协议支持不完整 | 中 | 高 | 第 1 个集成测试验证；不行回退 libmysqlclient |
| R2 | 大结果集（>1M 行 SELECT）内存爆炸 | 高 | 高 | 强制 `LIMIT 100000` 截断，状态栏提示 |
| R3 | NSTableView ⇄ SwiftUI 桥接复杂度 | 高 | 中 | 接受复杂度；先实现再优化 |
| R4 | 无主键表 UPDATE/DELETE 误改多行 | 高 | 极高 | §5.3.7.2 强制二次确认 + 永久"No PK"警告 |
| R5 | MySQL 8 caching_sha2_password 认证 | 中 | 极高 | 驱动选型时验证；不行换驱动 |
| R6 | KILL QUERY 在共享 MySQL 实例上权限不足 | 中 | 中 | 失败时 UI 提示，不重试 |
| R7 | macOS Keychain 用户拒绝授权 | 低 | 中 | 弹错误，提供"明文存储"opt-in 但**不在 MVP** |
| R8 | F9 与 macOS Mission Control 冲突 | 高 | 低 | 文档说明 + Cmd+R 备选 |
| R9 | sessions.json 损坏 | 低 | 中 | 备份 `sessions.json.bak`，加载失败回退到 .bak |
| R10 | 长连接被 MySQL `wait_timeout` 断开 | 高 | 中 | heartbeat 30s `SELECT 1`；断开后 UI 提示 |
| O1 | MVP 是否需要 SSH 隧道 | — | — | **决定：放 v0.2** |
| O2 | Universal 还是仅 arm64 | — | — | **决定：Universal** |
| O3 | 是否在 MVP 内做 .gitignore-style sessions 加密 | — | — | **决定：不做，依赖 Keychain** |
| O4 | F9 / Cmd+Enter 默认绑定 | — | — | **决定：F9（带文档说明）** |
| O5 | Truncate 是否需要管理员密码二次确认 | — | — | **决定：不需要，checkbox 足够** |

---

## 14. 修订记录

| 版本 | 日期 | 修改 |
|---|---|---|
| v0.1 | 2026-06-11 | 初稿（精简版） |
| v0.2 | 2026-06-11 | 详细版重写：加错误码表、状态机、字段约束、类型映射、组件契约、键盘冲突解决、测试 fixture 规格（见附录 C）；中文 UI 移到 v0.2 |

---

# 附录

## §A MySQL 类型映射表

完整列出 MVP 支持的列类型 → `CellValue` → 编辑器形态 → 边界处理：

| MySQL 类型 | `NormalizedType` | `CellValue` | 编辑器 | NULL | 边界/备注 |
|---|---|---|---|---|---|
| `TINYINT` | `.int` | `.int(Int64)` | TextField (numeric) | ✓ | unsigned: `.uint` |
| `TINYINT(1)` | `.bool` | `.bool(Bool)` | Checkbox | ✓ | 0=false, 非0=true |
| `SMALLINT` | `.int` | `.int(Int64)` | TextField | ✓ | unsigned: `.uint` |
| `MEDIUMINT` | `.int` | `.int(Int64)` | TextField | ✓ | unsigned: `.uint` |
| `INT` / `INTEGER` | `.int` | `.int(Int64)` | TextField | ✓ | unsigned: `.uint` |
| `BIGINT` | `.int` | `.int(Int64)` | TextField | ✓ | unsigned: `.uint(UInt64)` |
| `DECIMAL(M,D)` / `NUMERIC` | `.decimal` | `.decimal(String)` | TextField | ✓ | 保精度，字符串不转 Double |
| `FLOAT` | `.double` | `.double(Double)` | TextField | ✓ | |
| `DOUBLE` / `REAL` | `.double` | `.double(Double)` | TextField | ✓ | |
| `BIT(N)` | `.uint` | `.uint(UInt64)` | TextField (hex) | ✓ | 显示为 `b'0101'` |
| `DATE` | `.date` | `.date(Date)` | TextField (placeholder "YYYY-MM-DD") | ✓ | 时区无关 |
| `DATETIME` | `.datetime` | `.datetime(Date)` | TextField | ✓ | 按 `@@time_zone` 解释 |
| `TIMESTAMP` | `.datetime` | `.datetime(Date)` | TextField | ✓ | UTC 存储，按 `@@time_zone` 显示 |
| `TIME` | `.time` | `.time(String)` | TextField | ✓ | 范围 `-838:59:59` 到 `838:59:59` |
| `YEAR` | `.int` | `.int(Int64)` | TextField | ✓ | 1901-2155 |
| `CHAR(N)` | `.string` | `.string(String)` | TextField | ✓ | |
| `VARCHAR(N)` | `.string` | `.string(String)` | TextField | ✓ | 校验 length ≤ N |
| `TINYTEXT` | `.string` | `.string(String)` | TextField + 双击多行 | ✓ | max 255 |
| `TEXT` | `.string` | `.string(String)` | TextField + 双击多行 | ✓ | max 65535 |
| `MEDIUMTEXT` | `.string` | `.string(String)` | 多行编辑器 | ✓ | max 16M |
| `LONGTEXT` | `.string` | `.string(String)` | 多行编辑器 | ✓ | max 4G |
| `BINARY(N)` | `.blob` | `.blob(Data)` | **只读** `[BLOB N bytes]` | ✓ | |
| `VARBINARY(N)` | `.blob` | `.blob(Data)` | **只读** | ✓ | |
| `TINYBLOB / BLOB / MEDIUMBLOB / LONGBLOB` | `.blob` | `.blob(Data)` | **只读** | ✓ | |
| `ENUM('a','b',...)` | `.string` | `.string(String)` | PopUpButton | ✓ | |
| `SET('a','b',...)` | `.string` | `.string(String)` | 多选 dialog | ✓ | |
| `JSON` | `.json` | `.json(String)` | 多行编辑器（绿色） | ✓ | 验证 JSON.parse |
| `GEOMETRY / POINT / LINESTRING / POLYGON / etc.` | `.unknown` | `.unknown(String)` | **只读** `[GEOMETRY]` | ✓ | MVP 不支持编辑 |

## §B 关键组件契约

### B.1 `SessionStore`

```swift
protocol SessionStore {
    func loadAll() throws -> [SessionConfig]
    func save(_ sessions: [SessionConfig]) throws
}
// 实现：JSONSessionStore(url: URL)
// 测试替身：InMemorySessionStore
```

行为契约：
- `loadAll` 返回 `[]` 当文件不存在
- `save` 必须原子（temp + rename）
- `loadAll` 解析失败时回退 `.bak`，再失败抛 `SessionStoreError.corrupt`

### B.2 `DataGridViewModel`

```swift
@MainActor
final class DataGridViewModel: ObservableObject {
    @Published private(set) var rows: [DataRow]
    @Published private(set) var schema: TableSchema
    @Published private(set) var dirty: [RowID: PendingChange]
    @Published private(set) var inserts: [DataRow]
    @Published private(set) var deletes: Set<RowID>
    @Published private(set) var totalCount: UInt64?
    @Published private(set) var loadState: LoadState

    func load(offset: Int, limit: Int) async
    func sort(column: String, direction: SortDirection?) async
    func setWhereClause(_ clause: String) async
    func editCell(rowId: RowID, column: String, newValue: CellValue) throws
    func unsetCellDirty(rowId: RowID, column: String)
    func markRowDelete(rowId: RowID)
    func insertNewRow() -> RowID
    func commit() async throws  // 单事务
    func discard()
}
```

### B.3 `QueryTabViewModel`

```swift
@MainActor
final class QueryTabViewModel: ObservableObject {
    @Published var sqlText: String
    @Published var cursorPosition: Int
    @Published private(set) var resultSubTabs: [ResultSubTabViewModel]
    @Published private(set) var messages: [QueryMessage]
    @Published private(set) var isRunning: Bool
    @Published private(set) var currentStatementIndex: Int?

    func runAll() async       // F9
    func runCurrent() async   // Ctrl+Enter
    func cancel() async
}
```

### B.4 `ObjectTreeViewModel`

```swift
@MainActor
final class ObjectTreeViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionNode]
    @Published var activeSessionId: SessionConfig.ID?
    @Published var selectedNodeId: NodeID?

    func openSession(_ id: SessionConfig.ID) async
    func disconnectSession(_ id: SessionConfig.ID) async
    func expandDatabase(_ db: String) async
    func refresh(node: NodeID) async
    func truncateTable(database: String, table: String) async throws
    func copyCreateStatement(database: String, table: String) async throws -> String
}
```

## §C 测试 Fixture 规格

### C.1 单元测试（U）

- 全部基于 `MockDBClient` + `MockKeychainStore` + `InMemorySessionStore`
- 不需要任何外部依赖
- 工具：`swift-testing`

### C.2 集成测试（I）— MySQL 实例

**最小测试 schema**（由 setUp 自动创建）：

```sql
CREATE DATABASE IF NOT EXISTS macheidi_test;
USE macheidi_test;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) UNIQUE,
  age INT,
  active TINYINT(1) DEFAULT 1,
  bio TEXT,
  metadata JSON,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  avatar BLOB
);

DROP TABLE IF EXISTS no_pk_table;
CREATE TABLE no_pk_table (
  col_a INT,
  col_b VARCHAR(50)
);

DROP VIEW IF EXISTS active_users;
CREATE VIEW active_users AS SELECT id, name, email FROM users WHERE active = 1;

INSERT INTO users (name, email, age, bio, metadata) VALUES
  ('Alice', 'alice@example.com', 30, 'Engineer', '{"city":"SF"}'),
  ('Bob', 'bob@example.com', 25, NULL, NULL),
  ('Carol', NULL, NULL, 'Long bio...', '{"city":"NYC"}');

INSERT INTO no_pk_table VALUES (1, 'a'), (2, 'b'), (3, 'c');
```

**大表（性能测试）**：
- `large_table` (1M rows, INT id + 10 cols mixed types)，由独立 fixture 脚本生成
- 默认 CI 跳过；本地用 `MACHEIDI_PERF=1` 启用

### C.3 E2E 测试（E）

- 基于 XCUITest
- 启动一个 dummy MySQL container（用 Docker compose）
- 用上面 §C.2 的 schema
- 自动化点击 / 输入 / 截图，验证完整用户流程

## §D 错误码总表

见 §5.5.4.2。

---

（PRD 正文完）
