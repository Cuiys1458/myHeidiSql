#!/usr/bin/env bash
# Seed demo / 集成测试用的 MySQL 数据库。
#
# 用法：
#   ./scripts/seed-demo.sh           # 写到本机 127.0.0.1:3306（用 docker exec mysql8）
#   ./scripts/seed-demo.sh --shell   # 强制走 mysql CLI（如果你装了）
#
# 创建：
#   - macheidi_test.users / orders         （PK + FK + 索引演示）
#   - macheidi_test.log_with_blob_json     （BLOB / TEXT-as-JSON 演示）
#
# 数据是 self-contained 的：内置中文 / 转义字符 / 各种边界值，
# 适合录视频 / 跑集成测试 / 手工验收。

set -euo pipefail

cd "$(dirname "$0")/.."

USE_SHELL="${1:-}"

run_sql() {
    local sql="$1"
    if [[ "$USE_SHELL" == "--shell" ]] && command -v mysql >/dev/null 2>&1; then
        mysql -h 127.0.0.1 -P 3306 -u root -ppassword <<<"$sql"
    elif docker ps --format '{{.Names}}' | grep -q '^mysql8$'; then
        # docker exec 路径 —— 通过临时文件传入避免 stdin 被丢
        local tmp=$(mktemp)
        echo "$sql" > "$tmp"
        docker cp "$tmp" mysql8:/tmp/seed.sql >/dev/null
        docker exec mysql8 sh -c "mysql -uroot -ppassword < /tmp/seed.sql" 2>&1 \
            | grep -v "Using a password" || true
        rm "$tmp"
    else
        echo "✗ 找不到 mysql client，也没有 docker mysql8 容器在跑" >&2
        echo "  请先：docker run -d --name mysql8 -p 3306:3306 -e MYSQL_ROOT_PASSWORD=password mysql:8.0" >&2
        exit 1
    fi
}

echo "▶ 重建 macheidi_test 库…"
run_sql "
DROP DATABASE IF EXISTS macheidi_test;
CREATE DATABASE macheidi_test CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE macheidi_test;

-- 1. users / orders（HeidiSQL 风格的 PK + FK + 索引演示）
CREATE TABLE users (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  email VARCHAR(120),
  age INT,
  bio TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY idx_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE orders (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  status VARCHAR(20),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY idx_user (user_id),
  CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO users (username, email, age, bio) VALUES
  ('alice',   'alice@example.com',   28, 'product manager'),
  ('bob',     'bob@example.com',     35, 'engineer · loves SQL'),
  ('charlie', 'charlie@example.com', 22, 'designer'),
  ('diana',   'diana@example.com',   31, 'data scientist'),
  ('eve',     'eve@example.com',     27, 'security researcher'),
  ('frank',   'frank@example.com',   45, 'CTO at SomeCo'),
  ('grace',   'grace@example.com',   29, '中文名测试 · grace 张');

INSERT INTO orders (user_id, amount, status) VALUES
  (1, 199.00,  'paid'),
  (2, 88.50,   'pending'),
  (3, 1299.00, 'paid'),
  (1, 49.90,   'paid'),
  (4, 666.00,  'cancelled'),
  (5, 12.00,   'paid');

-- 2. BLOB-as-JSON / TEXT-as-JSON 演示（这是 v0.1.1 的新功能）
CREATE TABLE log_with_blob_json (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  payload BLOB,                               -- charset=binary，真 BLOB
  payload_text TEXT,                          -- charset=utf8mb4，是 TEXT
  note VARCHAR(100),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO log_with_blob_json (payload, payload_text, note) VALUES
  (
    '{\"code\":500,\"msg\":\"oops\",\"stack\":[\"MyService.handleRequest:42\",\"Logger.error:18\"]}',
    '{\"trace_id\":\"abc-123\",\"span_id\":\"xyz-789\",\"duration_ms\":234}',
    'JSON 错误对象 + JSON trace'
  ),
  (
    '{\"code\":200,\"msg\":\"ok\"}',
    '普通文本，不是 JSON',
    '简单 JSON BLOB + 普通 TEXT'
  ),
  (
    UNHEX('FFD8FFE0AB123456789ABCDEF0'),
    '{\"event\":\"file_upload\",\"size\":1024}',
    'JPEG 头（真二进制 BLOB） + JSON TEXT'
  ),
  (
    '{\"nested\":{\"a\":[1,2,3],\"b\":{\"c\":true,\"d\":null}}}',
    '{\"中文\":\"你好\",\"emoji\":\"🚀\",\"escape\":\"a\\\"b\"}',
    '嵌套 JSON + 含中文/emoji/转义'
  );

-- 3. 演示：VARCHAR-as-JSON 极端长 JSON（看大 JSON 编辑器渲染）
CREATE TABLE log_long_json (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  request_payload VARCHAR(8000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO log_long_json (request_payload) VALUES
  ('{\"endpoint\":\"/api/users\",\"method\":\"POST\",\"headers\":{\"Authorization\":\"Bearer ...\",\"Content-Type\":\"application/json\"},\"body\":{\"username\":\"new_user\",\"email\":\"new@example.com\",\"profile\":{\"age\":25,\"city\":\"Beijing\",\"interests\":[\"coding\",\"reading\",\"hiking\"]}},\"meta\":{\"ip\":\"192.0.2.1\",\"user_agent\":\"Mozilla/5.0\",\"timestamp\":\"2026-06-15T08:00:00Z\"}}');

SELECT
  (SELECT COUNT(*) FROM users) AS users_count,
  (SELECT COUNT(*) FROM orders) AS orders_count,
  (SELECT COUNT(*) FROM log_with_blob_json) AS blob_log_count,
  (SELECT COUNT(*) FROM log_long_json) AS long_json_count;
"

echo ""
echo "✅ 完成。可以连 MacHeidi → 127.0.0.1:3306 / root / password"
echo "   打开 macheidi_test 库 → log_with_blob_json 看 JSON 编辑器效果"
