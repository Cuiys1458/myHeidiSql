Feature: 数据浏览分页（PRD §5.3.5）
  As a user opening a table with millions of rows
  I want to see only one page at a time and step through pages
  So that the app stays responsive and I never accidentally pull the whole table

  PRD reference: §5.3.5 分页, §13 R2 大结果集

  Background:
    Given default page size is 100

  # ─────────────────────────────────────────────────────────
  # 默认行为
  # ─────────────────────────────────────────────────────────
  Scenario: 打开表默认拉 100 行，不再拉全表
    Given table macheidi_test.users with 5000 rows
    When the user opens the data tab
    Then the SELECT statement contains "LIMIT 100"
    And the SELECT statement contains "OFFSET 0"

  Scenario: 总行数显示
    When data is loaded
    Then footer shows "Page 1 / N · 5000 rows total"

  # ─────────────────────────────────────────────────────────
  # 翻页计算（纯函数）
  # ─────────────────────────────────────────────────────────
  Scenario: 5000 行 / page 100 → 50 页
    Given total = 5000, pageSize = 100
    Then totalPages = 50

  Scenario: 0 行 → 1 页（防止显示 "Page 1 / 0"）
    Given total = 0, pageSize = 100
    Then totalPages = 1

  Scenario: 不能整除时向上取整
    Given total = 251, pageSize = 100
    Then totalPages = 3

  Scenario: page 1 的 offset = 0
    Given pageSize = 100, page = 1
    Then offset = 0

  Scenario: page 3 的 offset = 200
    Given pageSize = 100, page = 3
    Then offset = 200

  # ─────────────────────────────────────────────────────────
  # 边界（不可超出）
  # ─────────────────────────────────────────────────────────
  Scenario: 在第一页时 First / Prev 不可用
    Given totalPages = 50, currentPage = 1
    Then canGoFirst = false
    And canGoPrev = false
    And canGoNext = true
    And canGoLast = true

  Scenario: 在最后一页时 Next / Last 不可用
    Given totalPages = 50, currentPage = 50
    Then canGoFirst = true
    And canGoPrev = true
    And canGoNext = false
    And canGoLast = false

  Scenario: 只有 1 页时所有翻页按钮都不可用
    Given totalPages = 1
    Then canGoFirst/Prev/Next/Last all false

  Scenario: 切换 pageSize 后 currentPage 自动钳制到最后一页
    Given total = 250, pageSize = 100, currentPage = 3
    When pageSize is changed to 500
    Then totalPages becomes 1
    And currentPage becomes 1

  Scenario: WHERE 条件改变后 currentPage 重置为 1
    Given currentPage = 5
    When user applies a new WHERE clause
    Then currentPage becomes 1

  # ─────────────────────────────────────────────────────────
  # 与编辑共存的安全边界
  # ─────────────────────────────────────────────────────────
  Scenario: 有 pending 编辑时翻页按钮全部禁用
    Given the user has 2 pending updates
    Then all pagination buttons are disabled
    And the bar shows hint "Commit or discard changes first"

  Scenario: pending 编辑下不能切 pageSize
    Given the user has 1 pending update
    Then page size dropdown is disabled

  # ─────────────────────────────────────────────────────────
  # 无总数兜底
  # ─────────────────────────────────────────────────────────
  Scenario: COUNT(*) 失败时 totalPages 显示 "?" 但仍允许 Next
    Given count query timed out
    When user presses Next
    Then offset advances by pageSize
    And footer shows "Page 2 / ?"
