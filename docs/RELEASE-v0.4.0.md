# MacHeidi v0.4.0

> CSV 自动建表 + 行 hover + 会话颜色标签

这一版聚焦"日常使用顺手程度"——三处看似小的改动，但用过 HeidiSQL 的人会一秒认出来。

---

## ✨ 新功能

### CSV 导入到新表（v0.3 留的尾巴）

之前 v0.3 完成了 `CSVTableInferrer` 核心层（10 个测试），UI 入口没接。这版接好：

1. 侧栏右键**库节点** → **从 CSV 导入到新表…**
2. 选 CSV 文件 → 自动用首行做表头、用前 200 行采样推导列类型
3. 改改类型 / nullable（`BIGINT` / `DECIMAL(20,6)` / `DATE` / `DATETIME` / `VARCHAR(N)` / `TEXT`）
4. 看 `CREATE TABLE` 预览 → **建表并导入**
5. 自动 INSERT 全部行（每批 500 行 + 单事务）

### 行 hover 高亮

数据网格鼠标悬停的行用 `controlAccentColor` × 12% alpha 高亮。

实现：`CopyableTableView` 加 `NSTrackingArea` `.mouseMoved` + 每次 hoveredRow 变化只 reload 前后两行（不全表刷）。10万行表零卡顿。

### 会话颜色标签（防误连生产）

`SessionConfig` 加 `colorTag` 字段，**蓝（开发）/ 绿（测试）/ 橙（预发）/ 红（生产）/ 紫 / 灰 / 无** 七档。

- Session Manager 编辑表单底部多一行色块 picker
- 侧栏会话名左边出现 3px 色条，prod 一眼看到红色，敲 SQL 前心智回路触发一次

---

## 📊 数据

| 维度 | v0.3 → v0.4 |
|---|---|
| 测试 | 293 → 293 |
| 安装包 | 13 MB → 13 MB |
| 新增源文件 | 2（CSVImportNewTableView + SessionColorPalette） |

---

## 🚀 安装

下载 `MacHeidi-0.4.0.dmg` → 拖到 Applications → 右键 → 打开。

> macOS 14+。
> [PolyForm Noncommercial 1.0.0](https://github.com/Cuiys1458/myHeidiSql/blob/main/LICENSE)。

---

## 🔄 完整 Changelog

主要 commits：

- `feat(csv): 自动建表 UI（侧栏库右键 → 从 CSV 导入到新表）`
- `feat(grid): 行 hover 高亮（NSTrackingArea + 增量 reload）`
- `feat(session): 颜色标签（防误连生产）`

完整 diff：https://github.com/Cuiys1458/myHeidiSql/compare/v0.3.0...v0.4.0
