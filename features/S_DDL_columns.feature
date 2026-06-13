Feature: 表结构编辑 — 列管理（DDL UI A）
  As a database operator
  I want to add / drop / modify / rename columns through UI
  So that I don't have to write ALTER TABLE syntax by hand

  PRD reference: §11 v0.3 表结构编辑

  # ─────────────────────────────────────────────────────────
  # 添加列
  # ─────────────────────────────────────────────────────────
  Scenario: 添加 INT 列（最简）
    Given table `db`.`users` exists
    When the user adds column `age` INT nullable
    Then SQL is "ALTER TABLE `db`.`users` ADD COLUMN `age` INT NULL"

  Scenario: 添加 NOT NULL + DEFAULT 列
    When the user adds column `status` VARCHAR(20) NOT NULL with default 'active'
    Then SQL contains "ADD COLUMN `status` VARCHAR(20) NOT NULL DEFAULT 'active'"

  Scenario: 添加 AUTO_INCREMENT 整型列
    When the user adds column `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY
    Then SQL contains "ADD COLUMN `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT"
    And SQL contains "PRIMARY KEY"

  Scenario: 列名含反引号正确转义
    When the user adds column `weird``name` INT
    Then SQL contains "`weird``name`"

  Scenario: AFTER 子句指定位置
    When the user adds column `age` INT AFTER `name`
    Then SQL contains "ADD COLUMN `age` INT NULL AFTER `name`"

  Scenario: FIRST 子句加到第一列
    When the user adds column `id` INT first
    Then SQL contains "ADD COLUMN `id` INT NULL FIRST"

  # ─────────────────────────────────────────────────────────
  # 删除列
  # ─────────────────────────────────────────────────────────
  Scenario: 删除列
    When the user drops column `tmp`
    Then SQL is "ALTER TABLE `db`.`users` DROP COLUMN `tmp`"

  Scenario: 删除主键列被警告（不阻止）
    When the user drops PK column `id` on a table whose PK is [id]
    Then a warning is recorded: "dropping PRIMARY KEY column"
    And SQL is generated normally

  # ─────────────────────────────────────────────────────────
  # 修改列类型
  # ─────────────────────────────────────────────────────────
  Scenario: 修改列类型
    When the user changes column `age` from INT to BIGINT
    Then SQL is "ALTER TABLE `db`.`users` MODIFY COLUMN `age` BIGINT NULL"

  Scenario: 改可空性 NULL → NOT NULL
    When the user changes column `name` from nullable VARCHAR(50) to NOT NULL VARCHAR(50)
    Then SQL contains "MODIFY COLUMN `name` VARCHAR(50) NOT NULL"

  Scenario: 改默认值
    When the user changes column `status` default from 'active' to 'pending'
    Then SQL contains "DEFAULT 'pending'"

  # ─────────────────────────────────────────────────────────
  # 重命名列
  # ─────────────────────────────────────────────────────────
  Scenario: 重命名列（保留类型）
    When the user renames column `name` to `full_name` (type VARCHAR(100), nullable)
    Then SQL is "ALTER TABLE `db`.`users` CHANGE COLUMN `name` `full_name` VARCHAR(100) NULL"

  Scenario: 重命名 + 改类型 + 改可空性
    When user renames `age` (INT NULL) to `age_years` (SMALLINT NOT NULL)
    Then SQL contains "CHANGE COLUMN `age` `age_years` SMALLINT NOT NULL"

  # ─────────────────────────────────────────────────────────
  # 校验
  # ─────────────────────────────────────────────────────────
  Scenario: 添加同名列被拒绝
    Given table has column `email`
    When the user tries to add another column `email` INT
    Then SQL generation fails with "duplicate column name"

  Scenario: 修改不存在的列被拒绝
    Given table has columns [id, name]
    When the user tries to modify column `nonexistent`
    Then SQL generation fails with "column not found"

  Scenario: 空列名被拒绝
    When the user adds column with empty name
    Then SQL generation fails with "empty identifier"
