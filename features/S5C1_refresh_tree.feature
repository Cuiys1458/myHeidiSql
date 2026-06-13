Feature: F5 刷新对象树（S2.6）
  As a user who just changed schema (DDL or another tool)
  I want to refresh the tree node I'm currently focused on
  So that the UI shows fresh state without disconnecting

  PRD reference: §5.2.5 F5 刷新行为

  Scenario: 选中 Session → F5 刷新数据库列表
    Given a connected session "Local"
    And the user has selected the session node
    When F5 is pressed
    Then SHOW DATABASES is re-executed
    And the databases list is updated
    And expanded children's expanded state is preserved

  Scenario: 选中 Database → F5 刷新该库的表/视图
    Given a connected client with database "app" expanded
    And the user has selected database "app"
    When F5 is pressed
    Then SHOW FULL TABLES FROM `app` is re-executed
    And the table list under "app" updates
    And other databases' caches are not touched

  Scenario: 选中 Table → F5 重新拉该表元数据
    Given the user has selected table app.users
    When F5 is pressed
    Then the table's parent database is refreshed (so this table reappears with fresh row count)

  Scenario: 没选中任何节点 → F5 全量刷新（fallback to session-level）
    Given no node is selected but a session is connected
    When F5 is pressed
    Then SHOW DATABASES is re-executed
