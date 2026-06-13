Feature: 数据安全防误操作（S1.5 / S2.5 / R10）
  As a user holding a connection to a production database
  I want hard-to-undo operations to require explicit confirmation
  And I want to know immediately when my connection dies
  So that I don't lose data or run queries against a stale connection

  PRD reference: §5.1.3 删除、§5.2.6 Truncate、§13 R10 断线

  # ─────────────────────────────────────────────────────────
  # S1.5 — 删除会话二次确认
  # ─────────────────────────────────────────────────────────
  Scenario: 删除会话需要二次确认
    Given a session "Prod DB" exists
    When the user invokes Delete on the session
    Then a confirmation dialog appears with the session name shown verbatim
    And the dialog has Cancel and Delete buttons
    And the destructive button is styled as destructive (red)
    And no deletion has happened yet

  Scenario: 在确认对话框点 Cancel 不会删除
    Given a session "Prod DB" exists
    When the user invokes Delete and then clicks Cancel
    Then the session still exists
    And no Keychain entry is removed

  Scenario: 在确认对话框点 Delete 才真正删除
    Given a session "Prod DB" exists
    When the user invokes Delete and then clicks Delete
    Then the session is removed
    And its Keychain entry is removed

  Scenario: 在 Session Manager 工具栏删除也走二次确认
    Given a session is selected in Session Manager
    When the user clicks the minus button
    Then a confirmation dialog appears
    And the session is only removed after confirming

  Scenario: 不允许删除当前已连接的活跃会话
    Given session "Local" is currently connected and active
    When the user invokes Delete on "Local"
    Then a notice appears: "Disconnect this session before deleting"
    And no confirmation dialog is shown
    And the session still exists

  # ─────────────────────────────────────────────────────────
  # S2.5 — 表的右键菜单
  # ─────────────────────────────────────────────────────────
  Scenario: 表右键 → Copy CREATE Statement → 剪贴板包含 CREATE TABLE
    Given a connected client with table macheidi_test.users
    When the user right-clicks the table and chooses "Copy CREATE Statement"
    Then the system clipboard contains a string starting with "CREATE TABLE"
    And the string contains "users"

  Scenario: 表右键 → Copy Table Name → 剪贴板是 `db`.`table`
    Given a connected client with table macheidi_test.users
    When the user right-clicks and chooses "Copy Table Name"
    Then the system clipboard equals "`macheidi_test`.`users`"

  Scenario: 表右键 → Truncate Table 弹模态需勾选 checkbox 才能确认
    Given a connected client with table macheidi_test.no_pk_table containing 3 rows
    When the user right-clicks and chooses "Truncate Table…"
    Then a modal appears with text matching "delete ALL rows"
    And the Truncate button is initially disabled
    And after the user checks the confirmation checkbox the Truncate button becomes enabled

  Scenario: Truncate 确认执行后表为空且打开的 Data Tab 刷新
    Given table macheidi_test.no_pk_table has 3 rows
    And a Data Tab for that table is open showing 3 rows
    When the user truncates the table via the modal
    Then the table has 0 rows on the server
    And the open Data Tab refreshes to show 0 rows

  Scenario: Truncate 失败时弹框保留，错误显示在底部
    Given a table without DROP privilege
    When the user tries to truncate it
    Then the modal stays open
    And the modal bottom shows the MySQL error message in red

  # ─────────────────────────────────────────────────────────
  # R10 — 断线检测
  # ─────────────────────────────────────────────────────────
  Scenario: 心跳定期发 SELECT 1 保活
    Given a connected client
    When 35 seconds elapse without any user query
    Then exactly one SELECT 1 has been sent on the heartbeat channel

  Scenario: 心跳失败 → 标记 disconnected 并显示主区顶部 banner
    Given a connected client
    When the underlying connection is forcibly closed (server side or network)
    And the next heartbeat or query attempt fails with .network
    Then the client state becomes disconnected
    And the main window shows a banner: "Connection lost. [Reconnect]"

  Scenario: 用户点 Reconnect → 重新走 connect 流程
    Given the disconnected banner is showing
    When the user clicks Reconnect
    Then the client transitions to connecting
    And on success the banner disappears and tree refreshes

  Scenario: 用户主动 disconnect 不显示 banner
    Given a connected client
    When the user clicks Disconnect from the toolbar
    Then the client transitions to disconnected
    And no "Connection lost" banner is shown
