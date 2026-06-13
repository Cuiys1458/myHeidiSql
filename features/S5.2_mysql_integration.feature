Feature: MySQL 驱动集成（S5.2 / S1.2）
  As a MySQLClient implementor
  I want to verify DBClient protocol works against a real MySQL server
  So that MockDBClient covers behavior but MySQLClient covers protocol correctness

  PRD reference: §5.5.2, §5.5.7

  Background:
    Given a reachable MySQL 8 server at 127.0.0.1:3306
    And a MySQLClient configured with root/password

  # ─────────────────────────────────────────────────────────
  # 连接
  # ─────────────────────────────────────────────────────────
  Scenario: 能用凭据建立连接
    When connect is called
    Then state is connected
    And connectionId is non-nil and matches CONNECTION_ID()

  Scenario: 错误密码返回 auth 错
    When connect is called with wrong password
    Then it throws DBError.auth with errno 1045

  Scenario: 不存在的 host 返回 network 错
    When connect is called with host "192.0.2.1" (test-net unreachable)
    Then it throws DBError.network within 10 seconds

  # ─────────────────────────────────────────────────────────
  # 元数据
  # ─────────────────────────────────────────────────────────
  Scenario: listDatabases 返回非空列表且排除系统库
    Given a connected client
    When listDatabases with includeSystem=false
    Then returns a non-empty array excluding information_schema/performance_schema/mysql/sys

  Scenario: listTables 对已知库返回表列表
    Given a connected client
    When listTables is called for database "macheidi_test"
    Then returns an array containing at least "users" with kind .table
    And "active_users" with kind .view

  # ─────────────────────────────────────────────────────────
  # 查询
  # ─────────────────────────────────────────────────────────
  Scenario: query 返回正确的 ResultSet
    Given a connected client
    When "SELECT id, name FROM macheidi_test.users ORDER BY id" is executed
    Then ResultSet has column count 2
    And rows[0][0] equals .int(1)

  Scenario: 语法错返回 syntax 错
    Given a connected client
    When "SELEKT 1" is executed
    Then it throws DBError.syntax with errno 1064

  Scenario: 多条 DML 后 exec 返回 affectedRows
    Given a connected client
    And table macheidi_test.no_pk_table has 3 rows
    When "UPDATE macheidi_test.no_pk_table SET col_a = col_a + 1" is executed
    Then ExecResult has affectedRows 3

  Scenario: KILL QUERY 后 query 抛 cancelled
    Given a connected client
    When "SELECT SLEEP(10)" is running and cancel() is called
    Then the running query throws DBError.cancelled

  Scenario: 断开后重新 connect 可以再用
    Given a connected client
    When disconnect is called
    And connect is called again
    Then the client is connected again with a new connectionId