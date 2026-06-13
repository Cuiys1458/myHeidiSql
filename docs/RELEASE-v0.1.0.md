# MacHeidi v0.1.0 — First Public Release

> Mac 上的 HeidiSQL —— 原生 SwiftUI MySQL 客户端。
> 第一个可发布版本。

<p align="center">
  <img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/dist/icon-1024.png" width="140" alt="MacHeidi">
</p>

---

## 📦 下载

**[`MacHeidi-0.1.0.dmg`](#assets)** · 13 MB · Universal Binary (arm64 + x86_64)

| 属性 | 值 |
|---|---|
| 版本 | 0.1.0 |
| 大小 | 13 MB（解压后 .app 约 37 MB） |
| 架构 | Universal（Apple Silicon + Intel） |
| 最低系统 | macOS 14 (Sonoma) |
| 签名 | ad-hoc（无 Apple Developer ID） |
| SHA-256 | `85de4bb37a30187a06a90a6bb0eab70d53190fd2194b221201d8b7f965ba1824` |

校验下载完整性（可选）：

```bash
shasum -a 256 ~/Downloads/MacHeidi-0.1.0.dmg
# 应输出：85de4bb37a30187a06a90a6bb0eab70d53190fd2194b221201d8b7f965ba1824
```

---

## 📷 界面预览

<table>
  <tr>
    <td width="50%"><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/04-connected-query-tab.png" alt="Query Tab"></td>
    <td width="50%"><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/06-data-tab.png" alt="Data Tab"></td>
  </tr>
  <tr>
    <td align="center"><sub>主界面 · 侧栏库表树 + Query Tab</sub></td>
    <td align="center"><sub>Data Tab · 分页 / WHERE / 列头 / 行头标记</sub></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/05-sql-completion.png" alt="SQL Completion"></td>
    <td><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/08-table-info.png" alt="Table Info"></td>
  </tr>
  <tr>
    <td align="center"><sub>SQL 自动补全（输入即弹）</sub></td>
    <td align="center"><sub>表元信息 · Status / Columns / Indexes / DDL</sub></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/09-edit-structure.png" alt="Edit Structure"></td>
    <td><img src="https://raw.githubusercontent.com/Cuiys1458/myHeidiSql/main/docs/screenshots/10-modify-column.png" alt="Modify Column"></td>
  </tr>
  <tr>
    <td align="center"><sub>表结构编辑（DDL UI）· 列管理</sub></td>
    <td align="center"><sub>Modify Column · 改完即时生成 SQL Preview</sub></td>
  </tr>
</table>

---

## 🚀 安装

1. 下载 `MacHeidi-0.1.0.dmg`
2. 双击打开 dmg，把 `MacHeidi.app` 拖进 `Applications` 文件夹
3. 在 `Applications` 里找到它 → **右键 → 打开 → 再点弹窗里的"打开"**
   （**只有第一次需要这样**，因为没买 Apple Developer ID 做正式签名）

> **如果系统提示"已损坏"或"无法验证开发者"**：
> ```bash
> xattr -cr /Applications/MacHeidi.app
> ```
> 这条命令会清掉 macOS 给所有"从互联网下载"文件打的隔离标记。

---

## ✨ 这个版本能做什么

### 连接管理
- ✅ 新建 / 编辑 / 删除 / 复制会话
- ✅ 密码**只存** macOS Keychain，配置 JSON 永远不含明文
- ✅ JSON 原子写 + `.bak` 备份回退（断电安全）
- ✅ 心跳保活（30s），断线红色 banner + 一键 Reconnect
- ✅ **SSH 隧道**（基础版，本地端口转发）

### 对象树
- ✅ Sessions / Databases / Tables / Views / Procedures / Functions / Triggers
- ✅ **跨库表名搜索**（模糊匹配 / 大小写不敏感）
- ✅ Default Database 当白名单（HeidiSQL 行为）
- ✅ F5 / ⌘R 三档刷新粒度

### 数据浏览
- ✅ **NSTableView 高性能渲染**（百万行不卡）
- ✅ 分页（100 / 500 / 1000 / 5000）+ 跳页输入框
- ✅ WHERE 输入栏（语法错单独红字提示）
- ✅ 列头排序（升 / 降 / 取消三态）
- ✅ 列宽拖拽 + 实时持久化
- ✅ Cmd+C 复制选中行（TSV 格式，含 header）
- ✅ Cmd+. 中断长查询（`KILL QUERY`）

### 表数据编辑
- ✅ 双击单元格编辑 + 类型校验（INT / DECIMAL 保精度 / NOT NULL）
- ✅ **多行批量挂起** —— 改多个单元格不立即提交
- ✅ 行头标记：`●` 黄=修改 / `●−` 红=待删除 / `●+` 绿=待插入
- ✅ **单事务 Commit**：任一失败 ROLLBACK
- ✅ 无 PK 表 Commit 前**橙色二次确认**
- ✅ NULL-safe `<=>` 全列 WHERE
- ✅ BLOB / TEXT 自动从 WHERE 排除（防误改）

### SQL 编辑器
- ✅ 多 Query Tab，切换不丢 SQL
- ✅ **F9 / ⇧⌘R** 执行所有语句 / **⌘⏎** 执行光标处当前语句
- ✅ 多 SELECT 多 sub-tab 显示结果
- ✅ **语法高亮** + **打开 / 保存 .sql** + **EXPLAIN** + **SQL 美化**
- ✅ 查询历史持久化（⌘Y 浏览搜索）

### SQL 自动补全
- ✅ **输入即弹**（IDE 风格，250ms debounce）
- ✅ ⌃Space 强制触发
- ✅ 上下文识别：FROM/JOIN→表 · WHERE/SET→列 · `users.`→该表的列
- ✅ 候选：62 关键字 + 75 内置函数 + 表名 + 列名

### 表结构编辑（DDL UI）
- ✅ 列管理：Add / Modify / Rename / Drop（含位置 FIRST / AFTER）
- ✅ 索引管理：Add / Drop（PRIMARY 自动转 `DROP PRIMARY KEY`）
- ⚠️ 外键 / 表选项核心层已实现，UI 入口待补

### 导入导出
- ✅ Export Current Page / Entire Table → CSV / TSV / SQL（流式分批，不内存爆炸）
- ✅ 跟随 WHERE 过滤
- ✅ Import CSV：列映射 + 单事务批量 INSERT（每批 500 行）
- ✅ RFC 4180 规范

### 错误处理
- ✅ MySQL errno → 5 类语义错误（network / auth / syntax / constraint / timeout）
- ✅ 13 个常见 errno 已映射

完整功能列表见 [README — 做了什么](https://github.com/Cuiys1458/myHeidiSql#%E5%81%9A%E4%BA%86%E4%BB%80%E4%B9%88%E5%8A%9F%E8%83%BD%E8%AF%A6%E8%A7%A3)。

---

## ⚠️ 已知限制

| 项 | 说明 |
|---|---|
| **ad-hoc 签名** | 首次打开需"右键 → 打开"绕过 Gatekeeper |
| **Keychain 授权** | 第一次连接弹一次"始终允许"，点完不再弹 |
| **MySQL 5.7 + caching_sha2_password** | 已验证 MySQL 8 工作；5.7 新插件未实测 |
| **大 BLOB / GEOMETRY 列** | 只读显示 `[BLOB N bytes]`，不能编辑 |
| **超大 CSV 导入** | 一次性进内存（>500MB 不建议） |
| **F9 触发** | macOS 默认 F9 被 Mission Control 占用，需在系统设置改 fn 行为，或用 ⇧⌘R |
| **macOS 14 最低** | 用了 `@Observable` / `@Bindable`，老系统装不上 |

完整清单见 [README — 已知限制](https://github.com/Cuiys1458/myHeidiSql#%E5%B7%B2%E7%9F%A5%E9%99%90%E5%88%B6)。

---

## 🔭 下一步会做什么

**v0.1.x 补丁**（小修小补，1 周内）
- DDL 外键 / 表选项 UI 入口（核心层已就绪）
- i18n 全量字符串切换（中英资源已建）
- 行 hover 高亮 / 单元格作为 INSERT 复制

**v0.2**（数周内）
- 多窗口同 Session
- 批量编辑（多选行同列改）
- EXPLAIN 可视化（树形渲染）
- JSON 列专用编辑器

**v0.4**（路线图）
- **PostgreSQL 适配**（新增 `MacHeidiPostgres` driver target）

**明确不做**
- ❌ Mac App Store 上架 / Developer ID 签名 / Sparkle 自动更新 / Crash 上报
- ❌ ER 图 / 服务器监控 / 数据同步 / ORM 代码生成器

---

## 📊 数据

```
✔ Test run with 246 tests passed
```

| 维度 | 值 |
|---|---|
| 测试 | 246 个单元测试 + 13 个 BDD `.feature` |
| 代码 | Swift 6.0，三层架构（Core / MySQL Driver / App） |
| 外部依赖 | 仅 1 个：[vapor/mysql-nio](https://github.com/vapor/mysql-nio) |
| UI 框架 | SwiftUI + AppKit（NSTableView / NSPanel / NSTextView） |
| 冷启动 | ~1.5 秒（M 系列） |
| 空闲内存 | ~100 MB |
| 安装包 | 13 MB |

---

## 🙏 致谢

- **HeidiSQL** —— 灵感来源，操作模型完全对齐
- **vapor/mysql-nio** —— Swift 原生 MySQL 驱动
- **Apple SwiftUI / AppKit** —— UI 框架

---

## 📮 反馈

发现 bug / 想要某个功能？欢迎开 [Issue](https://github.com/Cuiys1458/myHeidiSql/issues)。

**MIT License** · Built with ❤️ on macOS.
