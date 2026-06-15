# MacHeidi v0.2.0

> DDL UI 完整 + 复制为 INSERT + i18n 框架就绪

这个版本把 v0.1 留下的所有 "⚠️ UI 入口未接" 都接好了，外加几个高频实用功能。

---

## ✨ 新功能

### DDL 完整 UI（外键 / 表选项）

`Show Table Info → Edit Structure` 现在不光能改列和索引，还能：

- **Foreign Keys** —— 列出所有外键，每行可 Drop；点 Add Foreign Key 弹表单：
  - Constraint name / 本地列（多选 = 复合 FK）
  - 引用 database / table / 列
  - ON DELETE / ON UPDATE 下拉（NO ACTION / RESTRICT / CASCADE / SET NULL）
  - Generate SQL → SQL Preview → Apply
- **Table Options** —— 改 ENGINE / DEFAULT CHARSET / COLLATE / COMMENT；同窗口能 RENAME TABLE
  - 非空字段才会写进 SQL，不动的留空
  - RENAME 与 ALTER 分两条 SQL（避免 MySQL 解析错）

核心层早就完成（11 个测试），这版只是把 UI 接上。

### 复制行为 INSERT 语句

Data Tab 表格里**右键单选行 / 多选行**：
- 新菜单项 **Copy as INSERT** —— 把当前选中行（含 dirty pending 编辑）生成完整的 `INSERT INTO ...` 语句写到剪贴板
- 多行选择 → 多条 INSERT，按 schema 列序生成
- 调试时把生产数据搬到测试环境秒级实用

### i18n 框架就绪

资源齐全（150+ 字符串覆盖全 UI），未来切换到中文显示只差替换硬编码：

- `Sources/MacHeidiApp/Resources/en.lproj/Localizable.strings` — 完整英文清单
- `Sources/MacHeidiApp/Resources/zh-Hans.lproj/Localizable.strings` — 中文翻译
- `Sources/MacHeidiApp/L10n.swift` — `L("key")` / `LS("key")` helper（处理 SPM Bundle.module）
- 当前 UI 仍是英文（不破坏现有测试和截图），全量替换在 v0.3

---

## 📊 数据

| 维度 | v0.1.1 → v0.2.0 |
|---|---|
| 测试 | 292 → 292（无回归） |
| 核心 | 283 → 283 |
| 集成 | 9 → 9 |
| 安装包 | 13 MB → 13 MB |
| 冷启动 | 1.5s → 1.5s |

---

## 🚀 安装

下载 `MacHeidi-0.2.0.dmg` → 拖到 Applications → 右键 → 打开（首次绕过 Gatekeeper）。

> 系统要求 macOS 14 (Sonoma)。
> 协议：[PolyForm Noncommercial 1.0.0](https://github.com/Cuiys1458/myHeidiSql/blob/main/LICENSE) — 个人非商业使用免费。

---

## 🔄 完整 Changelog

主要 commits：

- `feat(ddl): 外键 / 表选项 UI 入口（核心层 -> UI 接通）`
- `feat(grid): Copy as INSERT 右键菜单`
- `feat(i18n): L10n.swift helper + 完整中英 strings 资源`

完整 diff：https://github.com/Cuiys1458/myHeidiSql/compare/v0.1.1...v0.2.0
