Feature: DBClient 协议契约（S5.1）
  As an upper layer (ViewModel, UI)
  I want a single DBClient protocol with predictable state transitions
  So that I can write Mocks and not depend on any specific MySQL driver

  PRD reference: §5.5.1, §5.5.7

  # ─────────────────────────────────────────────────────────
  # 状态机
  # ─────────────────────────────────────────────────────────
  Scenario: 新建的 client 处于 idle 状态
    Given a new MockDBClient
    Then its state is idle
    And its connectionId is nil

  Scenario: connect 成功后状态变为 connected 并暴露 connectionId
    Given a new MockDBClient configured to succeed on connect with connectionId 42
    When connect is called with valid config
    Then its state transitions through connecting then to connected
    And its connectionId equals 42

  Scenario: connect 失败后状态保持 disconnected 并抛出 DBError
    Given a new MockDBClient configured to fail connect with auth error
    When connect is called
    Then it throws DBError.auth
    And its state is disconnected
    And its connectionId is nil

  Scenario: disconnect 后状态变为 disconnected 并清空 connectionId
    Given a connected MockDBClient
    When disconnect is called
    Then its state is disconnected
    And its connectionId is nil

  Scenario: 已断开的 client 再次 disconnect 是 no-op
    Given a new MockDBClient in idle state
    When disconnect is called
    Then no error is thrown
    And its state remains disconnected-or-idle

  # ─────────────────────────────────────────────────────────
  # 元数据查询
  # ─────────────────────────────────────────────────────────
  Scenario: listDatabases 在未连接时抛出 network 错
    Given a new MockDBClient in idle state
    When listDatabases is called
    Then it throws DBError.network

  Scenario: listDatabases 返回排序后的库名列表
    Given a connected MockDBClient with databases ["sys", "app_prod", "mysql"]
    When listDatabases is called with includeSystem false
    Then it returns ["app_prod"]

  Scenario: listDatabases includeSystem 为 true 时包含系统库
    Given a connected MockDBClient with databases ["sys", "app_prod", "mysql", "information_schema", "performance_schema"]
    When listDatabases is called with includeSystem true
    Then it returns ["app_prod", "information_schema", "mysql", "performance_schema", "sys"]

  # ─────────────────────────────────────────────────────────
  # 查询与执行（行为契约，非真实 SQL）
  # ─────────────────────────────────────────────────────────
  Scenario: query 在未连接时抛出 network 错
    Given a new MockDBClient in idle state
    When query "SELECT 1" is called
    Then it throws DBError.network

  Scenario: query 返回预先 stub 的 ResultSet
    Given a connected MockDBClient stubbed to return 2 rows for "SELECT * FROM users"
    When query "SELECT * FROM users" is called
    Then it returns a ResultSet with 2 rows

  Scenario: exec 在未连接时抛出 network 错
    Given a new MockDBClient in idle state
    When exec "UPDATE users SET x=1" is called
    Then it throws DBError.network

  Scenario: exec 返回预先 stub 的 ExecResult
    Given a connected MockDBClient stubbed to return affectedRows 3 for "UPDATE users SET x=1"
    When exec "UPDATE users SET x=1" is called
    Then it returns ExecResult with affectedRows 3

  # ─────────────────────────────────────────────────────────
  # Cancel
  # ─────────────────────────────────────────────────────────
  Scenario: cancel 调用导致后续 query 抛 cancelled
    Given a connected MockDBClient with a query stubbed to honor cancel
    When cancel is called before query completes
    Then the in-flight query throws DBError.cancelled
