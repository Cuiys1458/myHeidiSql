Feature: BLOB-as-JSON 兼容编辑（S5.3.7 扩展）
  作为 MacHeidi 用户，
  我想看到并编辑那些"被存到 BLOB / VARBINARY 列里的 JSON 字符串"，
  而不是看到一个无意义的 [BLOB N bytes] 占位。

  典型场景：log / event 表用 BLOB 存了 JSON 错误对象，
  例如 sys_operation_log.error_msg = '{"code":500,"msg":"oops"}'

  Background:
    Given 一个连接到本地 MySQL 8 的会话
    And 数据库 macheidi_test 里有表 log_with_blob_json：
      """
      CREATE TABLE log_with_blob_json (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        payload BLOB,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB;
      """
    And 表里有以下三行：
      | id | payload                                     |
      |  1 | {"code":500,"msg":"oops"}                   |
      |  2 | {"code":200,"msg":"ok","stack":["a","b"]}   |
      |  3 | UNHEX('FFD8FFE0')                           |

  Scenario: BLOB 列内容是 JSON 时显示真实内容
    When 我在 Data Tab 打开 log_with_blob_json
    Then 第 1 行 payload 应显示 {"code":500,"msg":"oops"} 形式（绿字）
    And 第 2 行 payload 应显示 minified 形式（绿字）
    And 第 3 行 payload 应显示 [BLOB 4 bytes]（灰字，未被识别为 JSON）

  Scenario: 双击 BLOB-as-JSON 单元格弹出 JSON 专用编辑器
    When 我双击第 1 行 payload
    Then 弹出窗口标题应为 "Edit JSON · `payload`"
    And 编辑区显示 {"code":500,"msg":"oops"}（语法高亮）
    And 顶部状态徽章显示 "Valid"（绿色对勾）
    And 工具栏含 Format、Minify 按钮（启用）

  Scenario: Format 按钮把单行 JSON 缩进
    Given 我打开了第 1 行 payload 的 JSON 编辑器
    When 我点 Format 按钮
    Then 编辑区内容应缩进为多行（2 空格）
    And 键按字典序排列（diff 稳定）

  Scenario: 输入非法 JSON 后 Apply 按钮被禁用
    Given 我打开了第 1 行 payload 的 JSON 编辑器
    When 我把内容改成 "{not json"
    Then 状态徽章变红显示 "Invalid"
    And 错误信息行显示具体语法错误（含 byte offset）
    And Apply 按钮被禁用

  Scenario: 改回合法 JSON 后 Apply 重新可用
    Given 我把内容改成了 "{not json"（Apply 已禁用）
    When 我把内容改回 {"code":500,"msg":"fixed"}
    Then 状态徽章变绿
    And Apply 按钮可点击

  Scenario: BLOB-as-JSON commit 后 MySQL 存的是真实 JSON 字符串
    Given 我打开了第 1 行 payload 的 JSON 编辑器
    When 我把内容改成 {"code":500,"msg":"fixed","tag":"v2"}
    And 我点 Apply
    Then 主界面 pending bar 显示 "1 update"
    When 我点 Commit
    Then 数据库里第 1 行 payload 应等于 {"code":500,"msg":"fixed","tag":"v2"}（UTF-8 字节）
    And 重新打开此行可以看到新内容

  Scenario: 真二进制 BLOB 不会误识别为 JSON
    When 我双击第 3 行 payload（实际是 JPEG 头 0xFFD8FFE0）
    Then 应该走老路径（不弹 JSON 编辑器）
    And 编辑窗显示 "[BLOB 4 bytes]"
    And Save 按钮提交时被 CellValueParser 拒绝（unsupported）

  Scenario: 导出含 BLOB-as-JSON 的表
    Given 我在 Data Tab 打开 log_with_blob_json
    When 我点 Export → Entire Table → CSV
    Then 导出文件里第 1、2 行 payload 列是 JSON 字符串（不是 [BLOB N bytes]）
    And 第 3 行 payload 列是 [BLOB 4 bytes]（保留二进制占位）

  Scenario: JSON 列的非法输入被 CellValueParser 拒绝
    Given 我在某表的 JSON 列单元格输入 "{not json"
    When 我点 Save
    Then 编辑窗显示红色错误 "Invalid JSON: ..."
    And 单元格未被加入 pending edits（dirty 状态保留输入）
