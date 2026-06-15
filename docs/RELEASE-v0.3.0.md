# MacHeidi v0.3.0

> i18n 中文界面 + 批量编辑 + CSV 自动建表

这一版从"工具能用"走向"用着顺手"。

---

## ✨ 新功能

### 中文界面（强制切换）

UI 顶层（Toolbar、Welcome 空态、Pending bar、断线 banner）全部走 i18n 资源，跟随系统语言。

强制切换中文：

```bash
defaults write com.macheidi.app MacHeidiLanguage zh-Hans
```

切回英文：

```bash
defaults write com.macheidi.app MacHeidiLanguage en
```

跟随系统：

```bash
defaults delete com.macheidi.app MacHeidiLanguage
```

> v0.3 覆盖了高曝光的 12 处英文。剩余菜单项 / DDL UI / Session Manager 内部表单等的 i18n 在 v0.4 收尾。

### 批量编辑（多选行同列改）

Data Tab 表格里：

1. 选中多行（Cmd / Shift 多选）
2. 在某个**列**上右键 → **Set Selected Cells…**
3. 弹 sheet：选目标列 + 输值（空 = 设为 NULL）→ Apply
4. N 行同时进 pending → Commit 后单事务批量更新

跟逐行手动编辑相比，省去循环点击的痛苦。

### CSV 自动建表（核心层）

新增 `CSVTableInferrer` 模块（10 个单元测试），输入 CSV header + 采样行，**自动推导出 CREATE TABLE 语句**：

| 推导规则 | 示例 |
|---|---|
| 全整数 → `BIGINT` | `1`, `100`, `999` → BIGINT |
| 含小数全数字 → `DECIMAL(20,6)` | `1.5`, `0.99` |
| ISO 日期 → `DATE` | `2026-06-15` |
| ISO 日期时间 → `DATETIME` | `2026-06-15 10:30:00` |
| 长文本 / 多行 → `TEXT` | bio / 描述列 |
| 其他 → `VARCHAR(N)` | N 自动对齐到 8 的倍数 |
| 任一行为空 → 该列 `NULL` | |

列名清洗：空格 / `-` 自动换 `_`，数字开头加 `col_` 前缀，中文保留。

> v0.3 只完成 core helper。SidebarView 的"右键库 → Import CSV as new table…" UI 入口留 v0.4。

---

## 📊 数据

| 维度 | v0.2.0 → v0.3.0 |
|---|---|
| 测试 | 292 → 293（新增 CSVTableInferrer 10 个） |
| 核心 | 283 → 293 |
| 集成 | 9 → 9 |
| 安装包 | 13 MB → 13 MB |

---

## 🚀 安装

下载 `MacHeidi-0.3.0.dmg` → 拖到 Applications → 右键 → 打开。

> macOS 14 (Sonoma)+。
> [PolyForm Noncommercial 1.0.0](https://github.com/Cuiys1458/myHeidiSql/blob/main/LICENSE) — 个人非商业使用免费。

---

## 🔄 完整 Changelog

主要 commits：

- `feat(i18n): UI 接入 i18n + 强制 Locale 切换`
- `feat(grid): 批量编辑（多选行同列改）`
- `feat(csv): CSVTableInferrer 自动推导 CREATE TABLE`

完整 diff：https://github.com/Cuiys1458/myHeidiSql/compare/v0.2.0...v0.3.0
