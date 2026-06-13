Feature: 表数据单元格编辑（S3.4 / S3.5 / S3.6 / S3.7 / S3.8 / S3.9）
  As a database operator
  I want to edit cells inline, batch changes, then commit/discard them as a transaction
  So that I don't have to write UPDATE/INSERT/DELETE by hand

  PRD reference: §5.3.5 ~ §5.3.9, §13 R4 无 PK 表风险

  # ─────────────────────────────────────────────────────────
  # 类型校验（值 → 类型化 CellValue）
  # ─────────────────────────────────────────────────────────
  Scenario: 字符串列接受任何字符串
    Given a VARCHAR(100) column
    When user inputs "Alice"
    Then the typed value is .string("Alice")

  Scenario: INT 列接受合法数字
    When user inputs "42" into an INT column
    Then the typed value is .int(42)

  Scenario: INT 列拒绝非数字
    When user inputs "abc" into an INT column
    Then validation fails with "Invalid integer"

  Scenario: NOT NULL 列拒绝 NULL
    Given a NOT NULL VARCHAR column
    When user sets the cell to NULL
    Then validation fails with "Column does not allow NULL"

  Scenario: nullable 列允许 NULL
    Given a nullable VARCHAR column
    When user sets the cell to NULL
    Then the typed value is .null

  Scenario: TINYINT(1) 接受布尔输入
    Given a TINYINT(1) column (treated as bool)
    When user toggles to true
    Then the typed value is .bool(true)

  Scenario: DECIMAL 列保留字符串精度
    When user inputs "12345.678901234567890" into a DECIMAL(30,15) column
    Then the typed value is .decimal("12345.678901234567890")

  # ─────────────────────────────────────────────────────────
  # Pending edits 状态机
  # ─────────────────────────────────────────────────────────
  Scenario: 修改单元格后行变 dirty
    Given a row with column 'name' = 'Alice'
    When user changes 'name' to 'Bob'
    Then the row is dirty
    And dirtyCellCount is 1

  Scenario: 改回原值后 dirty 自动清除
    Given a dirty row whose 'name' was 'Alice' and is now 'Bob'
    When user changes 'name' back to 'Alice'
    Then the row is no longer dirty
    And dirtyCellCount is 0

  Scenario: 多个单元格独立追踪
    When user edits column 'a' then column 'b' on the same row
    Then dirtyCellCount is 2
    And both cells are tracked separately

  Scenario: Discard 恢复原值并清除 dirty
    Given a row with two dirty cells
    When discard is invoked
    Then the row is no longer dirty
    And the cell values are back to original

  # ─────────────────────────────────────────────────────────
  # SQL 生成 — UPDATE
  # ─────────────────────────────────────────────────────────
  Scenario: 有主键表的 UPDATE 用 PK
    Given table users with PK [id], a row where id=1, name='Alice'
    And the user changed name to 'Bob'
    When commit SQL is generated
    Then it is "UPDATE `db`.`users` SET `name`='Bob' WHERE `id`=1"

  Scenario: UPDATE 多列同时改
    Given a dirty row with both 'name' and 'age' modified
    Then UPDATE has both columns in SET clause

  Scenario: UPDATE 使用复合主键
    Given table with PK [tenant_id, user_id]
    And the user changed name on a row with tenant=5, user=10
    Then WHERE clause contains both `tenant_id`=5 AND `user_id`=10

  Scenario: UPDATE 字符串值正确转义单引号
    Given user changes 'name' to "it's"
    Then the SQL contains "'it''s'" (doubled quote)

  Scenario: UPDATE NULL 值用 IS NULL 不是 = NULL（在 WHERE 里）
    Given a row where the PK column 'code' is NULL (no PK case actually, but for SET)
    When SET to NULL
    Then SET fragment is "`code` = NULL"

  # ─────────────────────────────────────────────────────────
  # SQL 生成 — 无 PK（PRD R4）
  # ─────────────────────────────────────────────────────────
  Scenario: 无主键表 UPDATE 用所有列做 WHERE
    Given table no_pk with columns [a, b, c], no PK
    And a row a=1, b='x', c=NULL
    When user changes 'a' to 2
    Then SQL is "UPDATE `db`.`no_pk` SET `a`=2 WHERE `a`<=>1 AND `b`<=>'x' AND `c`<=>NULL"

  Scenario: 无主键表 WHERE 排除 BLOB / TEXT 列（PRD §5.3.7.2）
    Given table with VARCHAR + TEXT + BLOB columns, no PK
    When generating WHERE for a dirty row
    Then BLOB and TEXT columns are excluded from WHERE
    And a warning is recorded: "BLOB/TEXT columns excluded from WHERE"

  Scenario: 无主键表编辑了被排除的列时拒绝提交
    Given a no-PK table with TEXT column 'bio'
    When user changes 'bio'
    And tries to commit
    Then commit is refused with "Cannot edit BLOB/TEXT in no-PK table; add a primary key first"

  # ─────────────────────────────────────────────────────────
  # SQL 生成 — INSERT
  # ─────────────────────────────────────────────────────────
  Scenario: INSERT 只发用户填了的列
    Given table users with columns [id AUTO_INCREMENT, name NOT NULL, age]
    When user inserts a new row with only 'name' = 'Alice'
    Then SQL is "INSERT INTO `db`.`users` (`name`) VALUES ('Alice')"

  Scenario: INSERT 带 NULL 值
    When user inserts a new row with name='Bob' and age=NULL
    Then SQL is "INSERT INTO `db`.`users` (`name`, `age`) VALUES ('Bob', NULL)"

  Scenario: 空插入行（用户未填任何列）→ 跳过该行
    When user inserts a placeholder row but enters nothing
    Then no INSERT is generated for that row

  # ─────────────────────────────────────────────────────────
  # SQL 生成 — DELETE
  # ─────────────────────────────────────────────────────────
  Scenario: DELETE 用 PK
    Given a row with id=42 marked for deletion
    Then SQL is "DELETE FROM `db`.`users` WHERE `id`=42"

  Scenario: 多行 DELETE
    Given rows id=1, id=2, id=3 marked for deletion
    Then SQL is "DELETE FROM `db`.`users` WHERE `id` IN (1, 2, 3)"
    Or 3 separate DELETE statements (impl-defined; both acceptable)

  Scenario: 无 PK DELETE 也用全列 WHERE
    Given no-PK table, row a=1 b='x' marked for deletion
    Then SQL is "DELETE FROM `db`.`no_pk` WHERE `a`<=>1 AND `b`<=>'x'"

  # ─────────────────────────────────────────────────────────
  # 提交流程
  # ─────────────────────────────────────────────────────────
  Scenario: 提交所有 pending 在单事务里
    Given 3 dirty rows: 2 UPDATE, 1 DELETE
    When commit
    Then sequence is: BEGIN; UPDATE...; UPDATE...; DELETE...; COMMIT;

  Scenario: 任一语句失败整个事务回滚
    Given dirty rows where the second UPDATE will fail
    When commit
    Then ROLLBACK is sent
    And dirty marks are NOT cleared
    And UI displays the failing statement and error
