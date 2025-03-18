-- Ініціалізація бази даних PostgreSQL для Predator Analytics 5.0

-- Створення схем
CREATE SCHEMA IF NOT EXISTS customs;
CREATE SCHEMA IF NOT EXISTS tax;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS users;

-- Створення таблиці для митних декларацій
CREATE TABLE IF NOT EXISTS customs.declarations (
    id SERIAL PRIMARY KEY,
    declaration_number VARCHAR(50) UNIQUE NOT NULL,
    declaration_date DATE NOT NULL,
    company_name VARCHAR(255) NOT NULL,
    company_code VARCHAR(50) NOT NULL,
    goods_description TEXT,
    goods_code VARCHAR(50),
    goods_value DECIMAL(15, 2) NOT NULL,
    goods_weight DECIMAL(15, 2),
    country_of_origin VARCHAR(50),
    customs_value DECIMAL(15, 2),
    customs_duty DECIMAL(15, 2),
    vat DECIMAL(15, 2),
    total_taxes DECIMAL(15, 2),
    customs_office VARCHAR(100),
    customs_officer VARCHAR(100),
    status VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення індексів для митних декларацій
CREATE INDEX IF NOT EXISTS idx_declarations_company_code ON customs.declarations(company_code);
CREATE INDEX IF NOT EXISTS idx_declarations_declaration_date ON customs.declarations(declaration_date);
CREATE INDEX IF NOT EXISTS idx_declarations_goods_code ON customs.declarations(goods_code);
CREATE INDEX IF NOT EXISTS idx_declarations_country_of_origin ON customs.declarations(country_of_origin);

-- Створення таблиці для податкових накладних
CREATE TABLE IF NOT EXISTS tax.invoices (
    id SERIAL PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    invoice_date DATE NOT NULL,
    seller_name VARCHAR(255) NOT NULL,
    seller_code VARCHAR(50) NOT NULL,
    buyer_name VARCHAR(255) NOT NULL,
    buyer_code VARCHAR(50) NOT NULL,
    goods_description TEXT,
    goods_code VARCHAR(50),
    goods_value DECIMAL(15, 2) NOT NULL,
    tax_amount DECIMAL(15, 2) NOT NULL,
    total_amount DECIMAL(15, 2) NOT NULL,
    tax_rate DECIMAL(5, 2),
    status VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення індексів для податкових накладних
CREATE INDEX IF NOT EXISTS idx_invoices_seller_code ON tax.invoices(seller_code);
CREATE INDEX IF NOT EXISTS idx_invoices_buyer_code ON tax.invoices(buyer_code);
CREATE INDEX IF NOT EXISTS idx_invoices_invoice_date ON tax.invoices(invoice_date);
CREATE INDEX IF NOT EXISTS idx_invoices_goods_code ON tax.invoices(goods_code);

-- Створення таблиці для компаній
CREATE TABLE IF NOT EXISTS analytics.companies (
    id SERIAL PRIMARY KEY,
    company_code VARCHAR(50) UNIQUE NOT NULL,
    company_name VARCHAR(255) NOT NULL,
    registration_date DATE,
    address TEXT,
    phone VARCHAR(50),
    email VARCHAR(100),
    website VARCHAR(100),
    industry VARCHAR(100),
    risk_score DECIMAL(5, 2),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення індексів для компаній
CREATE INDEX IF NOT EXISTS idx_companies_company_code ON analytics.companies(company_code);
CREATE INDEX IF NOT EXISTS idx_companies_risk_score ON analytics.companies(risk_score);

-- Створення таблиці для аномалій
CREATE TABLE IF NOT EXISTS analytics.anomalies (
    id SERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL, -- 'declaration', 'invoice', 'company'
    entity_id INTEGER NOT NULL,
    anomaly_type VARCHAR(100) NOT NULL,
    anomaly_description TEXT,
    confidence_score DECIMAL(5, 2) NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'open',
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_by INTEGER,
    resolution_notes TEXT
);

-- Створення індексів для аномалій
CREATE INDEX IF NOT EXISTS idx_anomalies_entity_type_id ON analytics.anomalies(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_anomalies_status ON analytics.anomalies(status);
CREATE INDEX IF NOT EXISTS idx_anomalies_confidence_score ON analytics.anomalies(confidence_score);

-- Створення таблиці для кластерів
CREATE TABLE IF NOT EXISTS analytics.clusters (
    id SERIAL PRIMARY KEY,
    cluster_name VARCHAR(100) NOT NULL,
    cluster_description TEXT,
    entity_type VARCHAR(50) NOT NULL, -- 'declaration', 'invoice', 'company'
    algorithm VARCHAR(100) NOT NULL,
    parameters JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення таблиці для зв'язків між кластерами та сутностями
CREATE TABLE IF NOT EXISTS analytics.cluster_entities (
    id SERIAL PRIMARY KEY,
    cluster_id INTEGER NOT NULL REFERENCES analytics.clusters(id),
    entity_type VARCHAR(50) NOT NULL,
    entity_id INTEGER NOT NULL,
    similarity_score DECIMAL(5, 2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(cluster_id, entity_type, entity_id)
);

-- Створення індексів для кластерів та зв'язків
CREATE INDEX IF NOT EXISTS idx_cluster_entities_cluster_id ON analytics.cluster_entities(cluster_id);
CREATE INDEX IF NOT EXISTS idx_cluster_entities_entity ON analytics.cluster_entities(entity_type, entity_id);

-- Створення таблиці для користувачів
CREATE TABLE IF NOT EXISTS users.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення таблиці для ролей
CREATE TABLE IF NOT EXISTS users.roles (
    id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    permissions JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення таблиці для журналу дій користувачів
CREATE TABLE IF NOT EXISTS users.activity_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users.users(id),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INTEGER,
    details JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Створення індексів для журналу дій
CREATE INDEX IF NOT EXISTS idx_activity_log_user_id ON users.activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON users.activity_log(created_at);
CREATE INDEX IF NOT EXISTS idx_activity_log_action ON users.activity_log(action);

-- Створення таблиці для налаштувань системи
CREATE TABLE IF NOT EXISTS analytics.settings (
    id SERIAL PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Вставка початкових ролей
INSERT INTO users.roles (role_name, description, permissions)
VALUES 
    ('admin', 'Адміністратор системи з повним доступом', '{"all": true}'),
    ('analyst', 'Аналітик з доступом до аналітичних функцій', '{"read": true, "analytics": true, "export": true}'),
    ('customs_broker', 'Митний брокер з обмеженим доступом', '{"read": true, "export": true, "customs": true}'),
    ('law_enforcement', 'Правоохоронні органи з доступом до розслідувань', '{"read": true, "analytics": true, "export": true, "investigations": true}'),
    ('viewer', 'Користувач з доступом тільки для перегляду', '{"read": true}')
ON CONFLICT (role_name) DO NOTHING;

-- Вставка адміністратора за замовчуванням (пароль: admin)
INSERT INTO users.users (username, email, password_hash, first_name, last_name, role)
VALUES 
    ('admin', 'admin@predator.analytics', '$2b$12$1InE4QF8aHzPIhHUKJSGkOiVVe/7d9Vj9RqGJfpO/oii9Z8yPxD2W', 'Admin', 'User', 'admin')
ON CONFLICT (username) DO NOTHING;

-- Вставка початкових налаштувань
INSERT INTO analytics.settings (setting_key, setting_value, description)
VALUES 
    ('risk_threshold', '0.7', 'Поріг ризику для виявлення аномалій'),
    ('similarity_threshold', '0.8', 'Поріг подібності для векторного пошуку'),
    ('auto_clustering_enabled', 'true', 'Увімкнення автоматичної кластеризації'),
    ('auto_clustering_interval', '86400', 'Інтервал автоматичної кластеризації в секундах (1 день)'),
    ('telegram_notifications_enabled', 'true', 'Увімкнення сповіщень через Telegram'),
    ('max_results_per_page', '100', 'Максимальна кількість результатів на сторінку')
ON CONFLICT (setting_key) DO NOTHING;

-- Створення функції для оновлення поля updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Створення тригерів для оновлення поля updated_at
CREATE TRIGGER update_customs_declarations_updated_at
BEFORE UPDATE ON customs.declarations
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tax_invoices_updated_at
BEFORE UPDATE ON tax.invoices
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_analytics_companies_updated_at
BEFORE UPDATE ON analytics.companies
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_analytics_clusters_updated_at
BEFORE UPDATE ON analytics.clusters
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_users_updated_at
BEFORE UPDATE ON users.users
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_roles_updated_at
BEFORE UPDATE ON users.roles
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_analytics_settings_updated_at
BEFORE UPDATE ON analytics.settings
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Надання прав доступу
GRANT USAGE ON SCHEMA customs TO predator;
GRANT USAGE ON SCHEMA tax TO predator;
GRANT USAGE ON SCHEMA analytics TO predator;
GRANT USAGE ON SCHEMA users TO predator;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA customs TO predator;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA tax TO predator;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA analytics TO predator;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA users TO predator;

GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA customs TO predator;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA tax TO predator;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA analytics TO predator;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA users TO predator;