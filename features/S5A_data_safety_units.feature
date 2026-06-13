Feature: SQL 标识符转义（S2.5 / S3 / R4 共用）
  As any feature that builds SQL strings from user-given names
  I want a single, audited identifier-quoting function
  So that backticks/reserved words/multi-byte names never break or inject SQL

  PRD reference: §A 类型映射、§5.3.7 提交时的 UPDATE 生成

  Scenario: 普通 ASCII 名转义为反引号包裹
    Given identifier "users"
    When quoted
    Then result is "`users`"

  Scenario: 含反引号的名按 MySQL 规则双写转义
    Given identifier "weird`name"
    When quoted
    Then result is "`weird``name`"

  Scenario: 含点号的名仍然只用一对反引号
    Given identifier "my.table"
    When quoted
    Then result is "`my.table`"

  Scenario: 空字符串拒绝
    Given identifier ""
    When quoted
    Then it throws SQLIdentifierError.empty

  Scenario: 含 NUL 字节的名拒绝
    Given identifier containing the NUL character
    When quoted
    Then it throws SQLIdentifierError.containsNul

  Scenario: 库.表 限定名
    Given database "macheidi_test" and table "users"
    When qualified
    Then result is "`macheidi_test`.`users`"

  Scenario: 库.表 任一方含反引号也要正确转义
    Given database "weird`db" and table "x"
    When qualified
    Then result is "`weird``db`.`x`"


Feature: 会话删除前置检查（S1.5）
  As the UI layer
  I want to ask domain whether a deletion is safe
  Before showing the confirmation dialog

  Scenario: 未连接的会话允许删除
    Given a session "Local" that is not the active session
    When asked whether deletion is allowed
    Then the result is .allowed

  Scenario: 当前活跃会话拒绝删除
    Given session "Local" is the active session
    When asked whether deletion is allowed
    Then the result is .blocked(reason: "Disconnect this session before deleting")


Feature: 心跳调度（R10）
  As the connection layer
  I want a deterministic scheduler that fires at fixed intervals
  And stops on the first failure
  So that we can detect lost connections and surface them to the user

  Scenario: 启动后按 interval 等待第一次 tick
    Given a scheduler with interval 30s
    When started at t=0
    Then the first tick fires at t=30s
    And the second tick fires at t=60s

  Scenario: 一次心跳成功后继续
    Given a scheduler with a success-stubbed probe
    When 3 ticks elapse
    Then 3 probes have been attempted
    And the scheduler is still alive

  Scenario: 第一次心跳失败 → 调度器停止 + 触发 onDisconnect
    Given a scheduler with a failure-stubbed probe
    When 1 tick elapses
    Then onDisconnect has been invoked exactly once
    And no further probes happen

  Scenario: 用户主动 stop 不触发 onDisconnect
    Given a running scheduler
    When stop() is called
    Then no onDisconnect callback fires
