Feature: SQL 自动补全（实时弹窗版 / 升级 #4）
  As a SQL writer
  I want a popup of suggestions to appear as I type
  So that I can pick table/column/keyword names without typing them out

  PRD reference: §11 v0.6 SQL 自动补全（提前到 v0.3）

  Background:
    Given an active connection with at least 2 databases preloaded
    And the SQL editor has focus

  # ─────────────────────────────────────────────────────────
  # 触发与关闭
  # ─────────────────────────────────────────────────────────
  Scenario: 输入第一个字母后 250ms 弹窗出现
    Given the editor is empty
    When the user types "S"
    And waits 250ms with no further input
    Then a completion popup is shown
    And it contains keywords starting with S (SELECT, SHOW, SET, ...)

  Scenario: 连续输入会刷新候选
    Given the popup is showing for "S"
    When the user types another "E"
    Then the popup updates to show entries starting with "SE" (SELECT, SET, ...)
    And the popup stays open

  Scenario: 输入到不再像 identifier 时关闭
    Given the popup is showing for "SEL"
    When the user types " " (space)
    Then the popup closes

  Scenario: 按 Esc 关闭
    Given the popup is showing
    When the user presses Esc
    Then the popup closes
    And the inserted text is unchanged

  Scenario: 编辑器失焦关闭
    Given the popup is showing
    When focus leaves the editor
    Then the popup closes

  # ─────────────────────────────────────────────────────────
  # 选择 + 确认
  # ─────────────────────────────────────────────────────────
  Scenario: 默认选中第 0 项
    When the popup opens
    Then row 0 is highlighted

  Scenario: 上下键移动选择
    Given the popup is showing 5 items, row 0 selected
    When the user presses Down arrow
    Then row 1 is selected

  Scenario: 到达底部按 Down 不动
    Given the popup has 3 items, row 2 selected
    When the user presses Down arrow
    Then row 2 stays selected

  Scenario: Enter 确认替换 token
    Given the editor contains "SELECT * FROM use" with cursor at end
    And the popup is showing with "users" selected
    When the user presses Enter
    Then the editor text becomes "SELECT * FROM users"
    And the popup closes
    And the cursor is right after "users"

  Scenario: Tab 也能确认
    Given a popup with selection
    When user presses Tab
    Then the selected entry is inserted

  # ─────────────────────────────────────────────────────────
  # 候选准确性
  # ─────────────────────────────────────────────────────────
  Scenario: SELECT 之后给列与函数
    Given the editor is "SELECT VER" cursor at end
    Then the popup includes "VERSION"

  Scenario: FROM 之后给表
    Given the editor is "SELECT * FROM us"
    Then the popup includes "users" but not "SELECT"

  Scenario: users. 之后给该表的列
    Given table users has columns id/name/email
    And the editor is "SELECT users."
    Then the popup includes "id", "name", "email" only

  Scenario: 没有匹配时不弹窗
    Given no entries start with "xyz"
    When the user types "xyz"
    Then no popup is shown

  # ─────────────────────────────────────────────────────────
  # 性能 / 不阻塞
  # ─────────────────────────────────────────────────────────
  Scenario: 候选加载未完成时仍能打字
    Given column metadata is still loading in background
    When the user types
    Then keystrokes are not blocked
    And the popup may show partial candidates that update later
