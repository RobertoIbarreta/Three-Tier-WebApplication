-- MySQL 8.x — run once against your RDS instance (same DB as var.db_name in Terraform).
-- Example: mysql -h <endpoint> -u <user> -p < schema.sql

CREATE TABLE IF NOT EXISTS items (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(512) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO items (id, title) VALUES
  (1, 'Hello from the database'),
  (2, 'Deploy this stack with Terraform + ASG');
