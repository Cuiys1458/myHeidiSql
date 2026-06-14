# MacHeidi v0.1.1

> BLOB-as-JSON / TEXT-as-JSON 兼容 + 全套 JSON 专用编辑器

主要场景：log 表常用 BLOB / VARBINARY / TEXT 列存 JSON（错误对象、操作上下文、trace 等），之前 MacHeidi 一律渲染成 `[BLOB N bytes]`，看不到内容也改不了。这版彻底改完了。

---

## ✨ 新功能

### BLOB-as-JSON / TEXT-as-JSON 自动识别

| 列类型 | 内容是 JSON | 行为 |
|---|---|---|
| `JSON` | always | 走 JSON 编辑器（向来如此） |
| `BLOB` / `VARBINARY` | 是 | **绿字显示 + 双击进 JSON 编辑器**（新） |
| `BLOB` / `VARBINARY` | 否（图片等真二进制） | 灰字 `[BLOB N bytes]`，只读（保持） |
| `TEXT` / `MEDIUMTEXT` / `LONGTEXT` / `VARCHAR` | 是 | **绿字显示 + 双击进 JSON 编辑器**（新） |
| `TEXT` / `VARCHAR` | 否（普通文本） | 默认色，普通编辑（保持） |

启发式判定 `JSONHelper.looksLikeJSONBLOB` 三重检查（UTF-8 + 顶层 object/array + `JSONSerialization` 完整解析），实际生产数据基本不会误判二进制为 JSON。

### 专用 JSON 编辑器

双击 JSON-flavored 单元格弹出 720×520 sheet：

- 🎨 **语法高亮** —— 手写 tokenizer，key 蓝 / string 红 / number 紫 / bool/null 橙 / bracket 灰
- 📐 **行号 + 等宽 SF Mono**
- ⚡️ **250ms debounce 实时校验** —— 错误位置红色波浪线 + byte offset 提示
- 🔧 **工具栏** —— Format（2 空格缩进 + sortedKeys）/ Minify / Validate / Set NULL
- 🛡 **Apply 必校验** —— 输入合法才能保存
- 📊 **底部状态栏** —— 顶层 keys 数 + 字节数

### BLOB 真实写入

之前 `SQLGenerator.literal(.blob(...))` 写死 `''`（注释明写"MVP 不支持 BLOB 写入"）。这版改了：

- BLOB 内容是 JSON → 字符串字面量（`'{"a":1}'`，单引号转义）
- BLOB 内容是二进制 → 十六进制字面量（`0xFFD8FFE0`，二进制安全）
- 空 BLOB → `''`（保持向后兼容）

### MySQL 元数据 charset 区分

之前 mysqlType 字段对 TEXT 列显示 `blob`（因为 wire 协议两者共用 type code 0xfc）。这版按 column charset 区分：

- `charset == 63 (binary)` → `blob` / `tinyblob` / `mediumblob` / `longblob`
- 其他 charset → `text` / `tinytext` / `mediumtext` / `longtext`

`Show Table Info` 现在显示正确的类型名。

---

## 🐛 修复

- `swift test` 全套之前会偶发卡在"不存在 host"的集成测试。connectTimeout 8s → 3s，期望从 `< 15s` 改到 `< 12s`，避免 swift-testing 并发调度下抖动

---

## 📊 数据

| 维度 | 值 |
|---|---|
| 测试 | 292 个全过（246 → 292，新增 46） |
| BDD `.feature` | 14 个（新增 `S_blob_json_editor.feature`） |
| 代码行 | +1102 / -29（首次发布以来） |
| 安装包 | 13 MB（不变） |
| 冷启动 | ~1.5 秒（不变） |

---

## 🚀 安装

下载 `MacHeidi-0.1.1.dmg` → 拖到 Applications → 右键 → 打开（首次绕过 Gatekeeper）。

> 系统要求 macOS 14 (Sonoma)。
> 协议：[PolyForm Noncommercial 1.0.0](https://github.com/Cuiys1458/myHeidiSql/blob/main/LICENSE) — 个人非商业使用免费。

---

## 🛠 演示数据脚本

新增 `scripts/seed-demo.sh`（仓库里），一条命令重建演示库：

```bash
./scripts/seed-demo.sh    # 自动走 docker mysql8 容器，或本地 mysql CLI
```

会创建：
- `macheidi_test.users` / `orders` —— PK + FK + 索引演示
- `macheidi_test.log_with_blob_json` —— BLOB / TEXT 各装 JSON / 真二进制 / 含中文 emoji 转义的边界数据
- `macheidi_test.log_long_json` —— 大 JSON（看编辑器渲染）

---

## 🔄 完整 Changelog

主要 commits：

- `feat(json): BLOB-as-JSON / TEXT-as-JSON 兼容 + 专用 JSON 编辑器`（核心功能）
- `chore: README 同步 + 演示脚本 + CI + 测试 timeout 调整`
- `feat: TEXT-as-JSON 识别（EditableResultGrid 颜色 + 编辑器分流）`

完整 diff：https://github.com/Cuiys1458/myHeidiSql/compare/v0.1.0...v0.1.1
