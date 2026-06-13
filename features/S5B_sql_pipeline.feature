Feature: SQL 多语句拆分（S4.2 / S4.3 / S5.3）
  As the SQL execution layer
  I want to split a free-form editor text into individual statements
  Respecting strings, comments, and identifier quoting
  So that F9 can run them in order, Ctrl+Enter can pick the one under cursor,
  and we never split inside a literal/comment

  PRD reference: §5.4.3 SQL 拆分规则

  # ── 基本拆分 ──────────────────────────────
  Scenario: 单条无分号
    Given SQL "SELECT 1"
    When split
    Then 1 statement: "SELECT 1"

  Scenario: 单条带分号
    Given SQL "SELECT 1;"
    When split
    Then 1 statement: "SELECT 1"

  Scenario: 两条用分号分隔
    Given SQL "SELECT 1; SELECT 2"
    When split
    Then 2 statements: ["SELECT 1", "SELECT 2"]

  Scenario: 末尾多余分号被忽略
    Given SQL "SELECT 1;;;"
    When split
    Then 1 statement: "SELECT 1"

  Scenario: 空白行 / 多余换行不产生空语句
    Given SQL "SELECT 1;\n\n\nSELECT 2;"
    When split
    Then 2 statements

  # ── 字符串内的分号不分隔 ──────────────────────────────
  Scenario: 单引号字符串内的分号被保留
    Given SQL "SELECT 'a;b;c'; SELECT 2"
    When split
    Then 2 statements: ["SELECT 'a;b;c'", "SELECT 2"]

  Scenario: 双引号字符串内的分号被保留
    Given SQL "SELECT \"a;b\"; SELECT 2"
    When split
    Then 2 statements

  Scenario: 反引号标识符内的分号被保留
    Given SQL "SELECT * FROM `weird;name`; SELECT 2"
    When split
    Then 2 statements

  Scenario: 单引号内的反斜杠转义不影响状态机
    Given SQL "SELECT 'it\\'s ok'; SELECT 2"
    When split
    Then 2 statements

  # ── 注释 ──────────────────────────────
  Scenario: 行注释里的分号被忽略
    Given SQL "SELECT 1 -- ; comment\n; SELECT 2"
    When split
    Then 2 statements

  Scenario: 块注释里的分号被忽略
    Given SQL "SELECT /* ; nope ; */ 1; SELECT 2"
    When split
    Then 2 statements

  Scenario: 块注释跨行
    Given SQL "/* multi\nline\ncomment */ SELECT 1"
    When split
    Then 1 statement

  # ── SELECT-like 判别 ──────────────────────────────
  Scenario: SELECT 被识别为 query
    When classifying "SELECT 1"
    Then it is .query

  Scenario: SHOW / DESCRIBE / EXPLAIN / WITH / VALUES / CALL 都是 query
    When classifying each of ["SHOW DATABASES", "DESCRIBE x", "EXPLAIN SELECT 1", "WITH cte AS (SELECT 1) SELECT * FROM cte", "VALUES (1)", "CALL p()"]
    Then each is .query

  Scenario: UPDATE / INSERT / DELETE / CREATE / DROP / TRUNCATE 都是 exec
    When classifying each of ["UPDATE u SET x=1", "INSERT INTO u VALUES (1)", "DELETE FROM u", "CREATE TABLE t (id INT)", "DROP TABLE t", "TRUNCATE TABLE t"]
    Then each is .exec

  Scenario: 前导空白和注释不影响判别
    When classifying "  -- a comment\n  /* block */ SELECT 1"
    Then it is .query

  Scenario: 大小写不敏感
    When classifying "select 1"
    Then it is .query

  # ── 光标语句定位（Ctrl+Enter）──────────────────────────────
  Scenario: 光标在第一条上 → 返回第一条
    Given SQL "SELECT 1; SELECT 2; SELECT 3"
    And cursor at offset 4 (inside "SELECT 1")
    When statement at cursor
    Then it returns "SELECT 1"

  Scenario: 光标在分号位置 → 返回分号前的语句
    Given SQL "SELECT 1; SELECT 2"
    And cursor at offset 8 (on the ";")
    When statement at cursor
    Then it returns "SELECT 1"

  Scenario: 光标在最后一条
    Given SQL "SELECT 1; SELECT 2"
    And cursor at offset 15
    When statement at cursor
    Then it returns "SELECT 2"

  Scenario: 光标在所有语句之后的空白
    Given SQL "SELECT 1;\n\n"
    And cursor at end
    When statement at cursor
    Then it returns "SELECT 1"


Feature: 多语句执行流水线（S4.2 / S4.4 / S4.5）
  As the QueryTab ViewModel
  I want to run N statements in order
  And collect each statement's result (ResultSet | ExecResult | Error)
  So that the UI can render N sub-tabs for SELECTs and a message log for everything

  Scenario: 全部成功 → results 序列等长且按顺序
    Given splits: ["SELECT 1", "SELECT 2", "UPDATE t SET x=1"]
    And client succeeds for all
    When runAll executes
    Then 3 outcomes recorded in order: [.rows, .rows, .affected]

  Scenario: 中间一条失败 → 停在失败处，后续不执行（PRD §5.4.4)
    Given splits: ["SELECT 1", "SELEKT broken", "SELECT 3"]
    When runAll executes
    Then outcomes: [.rows, .error, but no third entry]

  Scenario: 单条 query
    Given splits: ["SELECT 1"]
    When runAll
    Then 1 outcome: .rows

  Scenario: 空 SQL 不产生 outcome
    Given splits: []
    When runAll
    Then 0 outcomes
