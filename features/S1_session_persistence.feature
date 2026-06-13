Feature: Session 持久化与 Keychain（S1.1, S1.6, S1.7）
  As a user
  I want connection configs to survive app restart
  And my password to be stored only in macOS Keychain, never in plain files
  So that I don't have to re-enter credentials, and a stolen laptop disk reveals nothing useful

  PRD reference: §5.1.2, §5.1.5, §10

  # ─────────────────────────────────────────────────────────
  # S1.1 — Session CRUD
  # ─────────────────────────────────────────────────────────
  Scenario: 新建会话保存后能被重新读出
    Given an empty SessionManager backed by an in-memory store
    When a new session with name "Local MySQL" is added
    Then loadAll returns 1 session named "Local MySQL"

  Scenario: 编辑已有会话的字段保存后字段更新
    Given a SessionManager with 1 session named "Local MySQL"
    When the session's hostname is changed to "10.0.0.1" and saved
    Then loadAll returns a session with hostname "10.0.0.1"

  Scenario: 删除会话后列表减少
    Given a SessionManager with 2 sessions
    When the first session is deleted
    Then loadAll returns 1 session

  Scenario: 复制会话生成新 id、相同字段并自动追加后缀
    Given a SessionManager with 1 session named "Local"
    When the session is duplicated
    Then loadAll returns 2 sessions
    And the new session is named "Local (copy)"
    And the new session has a different id from the original
    And the new session has the same hostname as the original

  Scenario: 添加重名会话时自动追加后缀
    Given a SessionManager with 1 session named "Local"
    When a new session with name "Local" is added
    Then loadAll returns 2 sessions
    And the names are "Local" and "Local (2)"

  Scenario: 第三次重名追加 "(3)"
    Given a SessionManager with sessions named "Local" and "Local (2)"
    When a new session with name "Local" is added
    Then the third session is named "Local (3)"

  Scenario: name 字段必须非空
    Given an empty SessionManager
    When a new session with empty name is added
    Then an invalid input error is thrown

  Scenario: name 字段超过 64 字符校验失败
    Given an empty SessionManager
    When a new session with a 65-character name is added
    Then an invalid input error is thrown

  Scenario: port 范围超出 1..65535 校验失败
    Given an empty SessionManager
    When a new session with port 70000 is added
    Then an invalid input error is thrown

  # ─────────────────────────────────────────────────────────
  # S1.6 — 密码只进 Keychain，不进 JSON
  # ─────────────────────────────────────────────────────────
  Scenario: 添加带密码的会话后 JSON 文件不含密码字段
    Given a JSON-backed SessionManager pointing at a temp file
    When a new session "Prod" with password "s3cret!" is added
    Then the JSON file content does not contain "s3cret!"
    And the JSON file content does not contain a "password" key

  Scenario: 添加带密码的会话后 Keychain 收到该密码
    Given a SessionManager with a mock keychain
    When a new session "Prod" with password "s3cret!" is added
    Then the mock keychain holds an entry with that password under the session's id

  Scenario: 删除会话后 Keychain 中该 id 的密码也被删除
    Given a SessionManager with 1 session and a password in mock keychain
    When the session is deleted
    Then the mock keychain has no entry for that session id

  Scenario: 重命名（编辑 name 字段）不改变 Keychain account
    Given a SessionManager with 1 session id-X password "p" name "Local"
    When the session's name is changed to "Renamed" and saved
    Then mock keychain still has password "p" under account id-X
    And the password is unchanged

  # ─────────────────────────────────────────────────────────
  # S1.7 — 重启后还原
  # ─────────────────────────────────────────────────────────
  Scenario: 应用重启后会话配置完整还原
    Given a JSON-backed SessionManager with 2 sessions saved
    When a brand-new SessionManager is created against the same file
    Then it loads 2 sessions with identical fields

  Scenario: sessions.json 损坏时自动回退到 .bak
    Given a JSON-backed SessionManager that previously saved 1 session named "Good"
    And the main file is then corrupted to invalid JSON
    But the .bak file remains intact
    When a new SessionManager is created
    Then it loads 1 session named "Good"

  Scenario: sessions.json 与 .bak 都损坏时抛 corrupt 错
    Given the sessions.json file contains "not json"
    And the .bak file contains "also not json"
    When a SessionManager attempts to load
    Then SessionStoreError.corrupt is thrown

  Scenario: sessions.json 不存在时 loadAll 返回空数组
    Given no sessions.json exists at the path
    When a SessionManager loads
    Then loadAll returns an empty array

  Scenario: 写入 sessions.json 是原子的（temp → rename），不会留下半文件
    Given a JSON-backed SessionManager
    When save is called with 3 sessions
    Then no file named "sessions.json.tmp" remains in the directory
    And sessions.json contains valid JSON with 3 sessions

  Scenario: sessions.json 文件权限为 0600
    Given a JSON-backed SessionManager
    When save is called with 1 session
    Then sessions.json has POSIX permissions 0600

  Scenario: 读到不认识的版本号时只读模式打开，不破坏文件
    Given the sessions.json contains version 99 with 2 sessions
    When a SessionManager attempts to load
    Then it throws SessionStoreError.versionTooNew
    And the file content is unchanged after the failed load
