-- ============================================================
-- KIGHMU PANEL v2 - Base de données (CORRIGÉE)
-- Usage: mysql -u root -p < schema.sql
-- ============================================================
CREATE DATABASE IF NOT EXISTS kighmu_panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE kighmu_panel;

CREATE TABLE IF NOT EXISTS admins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS resellers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    max_users INT DEFAULT 10,
    used_users INT DEFAULT 0,
    data_limit_gb DECIMAL(10,2) DEFAULT 0,
    allowed_tunnels TEXT DEFAULT NULL,  -- JSON array ex: ["vless","ssh-multi"] — NULL = tous autorisés
    expires_at TIMESTAMP NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    quota_exceeded TINYINT(1) DEFAULT 0,  -- 1 = quota data dépassé → panel verrouillé (aucune création possible)
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES admins(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255),
    uuid VARCHAR(36),
    reseller_id INT,
    tunnel_type VARCHAR(30) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    quota_blocked TINYINT(1) DEFAULT 0,
    data_limit_gb DECIMAL(10,2) DEFAULT 0,
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS usage_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id INT,
    reseller_id INT,
    upload_bytes BIGINT DEFAULT 0,
    download_bytes BIGINT DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE,
    FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);

-- ============================================================
-- TABLE DE SNAPSHOT PAR UTILISATEUR (SOLUTION AU PROBLÈME DE RÉUTILISATION)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_traffic_snapshot (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    tunnel_type VARCHAR(30) NOT NULL,
    ym VARCHAR(7) NOT NULL,
    upload_bytes BIGINT DEFAULT 0,
    download_bytes BIGINT DEFAULT 0,
    deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_ym (ym)
);

-- Table de snapshot global par mois (conservée pour compatibilité)
CREATE TABLE IF NOT EXISTS monthly_traffic_snapshot (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ym VARCHAR(7) NOT NULL UNIQUE,
    upload_bytes BIGINT DEFAULT 0,
    download_bytes BIGINT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ym (ym)
);

CREATE TABLE IF NOT EXISTS activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    actor_type ENUM('admin','reseller') NOT NULL,
    actor_id INT NOT NULL,
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id INT,
    details TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS login_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    attempts INT DEFAULT 1,
    blocked_until TIMESTAMP NULL,
    last_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ip (ip_address)
);

-- Admin par défaut: admin / Admin@2024
INSERT IGNORE INTO admins (username, password) VALUES
('admin', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQyCgAvUlWSaJLRObAZWKpkYy');

-- ============================================================
-- MIGRATION pour installations existantes (décommenter si upgrade)
-- ============================================================
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS data_limit_gb DECIMAL(10,2) DEFAULT 0;
-- ALTER TABLE clients ADD COLUMN IF NOT EXISTS data_limit_gb DECIMAL(10,2) DEFAULT 0;
-- ALTER TABLE clients ADD COLUMN IF NOT EXISTS quota_blocked TINYINT(1) DEFAULT 0;
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS allowed_tunnels TEXT DEFAULT NULL;
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS quota_exceeded TINYINT(1) DEFAULT 0;
-- 
-- -- Créer la table user_traffic_snapshot si elle n'existe pas:
-- CREATE TABLE IF NOT EXISTS user_traffic_snapshot (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     username VARCHAR(50) NOT NULL UNIQUE,
--     tunnel_type VARCHAR(30) NOT NULL,
--     ym VARCHAR(7) NOT NULL,
--     upload_bytes BIGINT DEFAULT 0,
--     download_bytes BIGINT DEFAULT 0,
--     deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     INDEX idx_username (username),
--     INDEX idx_ym (ym)
-- );
--
-- -- Créer la table monthly_traffic_snapshot si elle n'existe pas:
-- CREATE TABLE IF NOT EXISTS monthly_traffic_snapshot (
--     id INT AUTO_INCREMENT PRIMARY KEY,
--     ym VARCHAR(7) NOT NULL UNIQUE,
--     upload_bytes BIGINT DEFAULT 0,
--     download_bytes BIGINT DEFAULT 0,
--     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     INDEX idx_ym (ym)
-- );
