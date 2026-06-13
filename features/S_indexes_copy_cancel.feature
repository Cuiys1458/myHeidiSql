Feature: 表结构编辑 — 索引管理（DDL UI B）
  As a database operator
  I want to add or drop indexes through UI
  So that I don't need to remember CREATE INDEX syntax

  PRD reference: §11 v0.3 表结构编辑

  # ─────────────────────────────────────────────────────────
  # 添加索引
  # ─────────────────────────────────────────────────────────
  Scenario: 添加单列普通索引
    Given table `db`.`users` exists
    When the user adds index "idx_email" on column "email"
    Then SQL is "ALTER TABLE `db`.`users` ADD INDEX `idx_email` (`email`)"

  Scenario: 添加 UNIQUE 索引
    When the user adds UNIQUE index "uniq_email" on column "email"
    Then SQL is "ALTER TABLE `db`.`users` ADD UNIQUE INDEX `uniq_email` (`email`)"

  Scenario: 添加复合索引
    When the user adds index "idx_status_created" on columns ["status", "created_at"]
    Then SQL contains "(`status`, `created_at`)"

  Scenario: 索引名为空时拒绝
    When the user adds index with empty name
    Then SQL generation fails with "empty identifier"

  Scenario: 列名为空时拒绝
    When the user adds index "idx_x" with empty columns
    Then SQL generation fails with "no columns"

  Scenario: 索引名 / 列名包含反引号正确转义
    When the user adds index "idx`weird" on column "col`name"
    Then SQL contains "`idx``weird`"
    And SQL contains "`col``name`"

  # ─────────────────────────────────────────────────────────
  # 删除索引
  # ─────────────────────────────────────────────────────────
  Scenario: 删除普通索引
    When the user drops index "idx_email"
    Then SQL is "ALTER TABLE `db`.`users` DROP INDEX `idx_email`"

  Scenario: 删除主键
    When the user drops index "PRIMARY"
    Then SQL is "ALTER TABLE `db`.`users` DROP PRIMARY KEY"

  Scenario: 索引名空拒绝
    When the user drops index with empty name
    Then SQL generation fails with "empty identifier"


Feature: 数据网格复制
  As a user reading a result set
  I want to copy selected cell or row with Cmd+C
  So that I can paste into Excel / Slack / SQL

  Scenario: 单击单元格 + Cmd+C 复制单元格值
    Given a selected cell containing "Alice"
    When the user presses Cmd+C
    Then the clipboard contains "Alice"

  Scenario: 多行选中 Cmd+C 复制为 TSV（含 header）
    Given rows 1, 3 are selected
    When the user presses Cmd+C
    Then the clipboard contains tab-separated rows
    And the first line contains the column headers


Feature: Data Tab 长查询取消
  As a user opening a multi-million row table
  I want to cancel the SELECT
  So that I don't wait for it to finish

  Scenario: 加载中显示 Cancel 按钮
    Given the Data Tab is loading
    Then a Cancel button is visible

  Scenario: 点 Cancel 中断查询
    Given Data Tab is loading
    When user presses Cancel
    Then the underlying connection sends KILL QUERY
    And the loading state ends within 2 seconds
