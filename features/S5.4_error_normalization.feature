Feature: 错误归一化（S5.4）
  As a UI layer
  I want database driver errors normalized to a single DBError enum
  So that I can show the right kind of feedback to the user without knowing MySQL internals

  PRD reference: §5.5.4.1, §5.5.4.2

  Background:
    Given a MySQL errno → DBError mapping defined in PRD §5.5.4.2

  # ─────────────────────────────────────────────────────────
  # 网络错（连接阶段）
  # ─────────────────────────────────────────────────────────
  Scenario: MySQL "Can't connect" 映射为 network 错
    Given a MySQL error with errno 2003 and sqlstate "HY000" and message "Can't connect to MySQL server on '127.0.0.1' (61)"
    When the error is normalized
    Then it produces DBError.network
    And the message contains "Can't connect"

  Scenario: MySQL "Unknown MySQL server host" 映射为 network 错
    Given a MySQL error with errno 2005 and sqlstate "HY000" and message "Unknown MySQL server host"
    When the error is normalized
    Then it produces DBError.network

  Scenario: Lost connection during query 映射为 network 错
    Given a MySQL error with errno 2013 and sqlstate "HY000" and message "Lost connection to MySQL server during query"
    When the error is normalized
    Then it produces DBError.network

  # ─────────────────────────────────────────────────────────
  # 认证错
  # ─────────────────────────────────────────────────────────
  Scenario: Access denied 映射为 auth 错并保留 errno
    Given a MySQL error with errno 1045 and sqlstate "28000" and message "Access denied for user 'root'@'localhost'"
    When the error is normalized
    Then it produces DBError.auth
    And the auth error carries mysqlErrno 1045

  Scenario: Unknown database 映射为 auth 错
    Given a MySQL error with errno 1049 and sqlstate "42000" and message "Unknown database 'foo'"
    When the error is normalized
    Then it produces DBError.auth

  # ─────────────────────────────────────────────────────────
  # 语法错
  # ─────────────────────────────────────────────────────────
  Scenario: SQL syntax error 映射为 syntax 错并保留 errno 与 sqlstate
    Given a MySQL error with errno 1064 and sqlstate "42000" and message "You have an error in your SQL syntax"
    When the error is normalized
    Then it produces DBError.syntax
    And the syntax error carries mysqlErrno 1064
    And the syntax error carries sqlState "42000"

  Scenario: Unknown column 映射为 syntax 错
    Given a MySQL error with errno 1054 and sqlstate "42S22" and message "Unknown column 'foo' in 'field list'"
    When the error is normalized
    Then it produces DBError.syntax

  # ─────────────────────────────────────────────────────────
  # 约束错
  # ─────────────────────────────────────────────────────────
  Scenario: Duplicate key 映射为 constraint 错
    Given a MySQL error with errno 1062 and sqlstate "23000" and message "Duplicate entry '1' for key 'PRIMARY'"
    When the error is normalized
    Then it produces DBError.constraint
    And the constraint error carries mysqlErrno 1062

  Scenario: Foreign key constraint fails 映射为 constraint 错
    Given a MySQL error with errno 1452 and sqlstate "23000" and message "Cannot add or update a child row"
    When the error is normalized
    Then it produces DBError.constraint

  # ─────────────────────────────────────────────────────────
  # Cancel
  # ─────────────────────────────────────────────────────────
  Scenario: Query interrupted by KILL QUERY 映射为 cancelled
    Given a MySQL error with errno 1317 and sqlstate "70100" and message "Query execution was interrupted"
    When the error is normalized
    Then it produces DBError.cancelled

  # ─────────────────────────────────────────────────────────
  # 超时
  # ─────────────────────────────────────────────────────────
  Scenario: Lock wait timeout 映射为 timeout 错
    Given a MySQL error with errno 1205 and sqlstate "HY000" and message "Lock wait timeout exceeded"
    When the error is normalized
    Then it produces DBError.timeout

  # ─────────────────────────────────────────────────────────
  # 兜底
  # ─────────────────────────────────────────────────────────
  Scenario: 未在映射表中的 errno 落到 server 分类
    Given a MySQL error with errno 1290 and sqlstate "HY000" and message "The MySQL server is running with the --read-only option"
    When the error is normalized
    Then it produces DBError.server
    And the server error carries mysqlErrno 1290

  Scenario: 非 MySQL 错（如 Swift 网络栈错）落到 unknown
    Given a non-MySQL error of type "URLError" with description "The Internet connection appears to be offline."
    When the error is normalized
    Then it produces DBError.unknown
    And the unknown error preserves the original error description
