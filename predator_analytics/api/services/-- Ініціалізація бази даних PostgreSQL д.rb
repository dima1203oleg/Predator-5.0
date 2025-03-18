-- Ініціалізація бази даних PostgreSQL для Predator Analytics 5.0

-- Створення схем
CREATE SCHEMA IF NOT EXISTS customs;
COMMENT ON SCHEMA customs IS 'Схема для митних даних';

CREATE SCHEMA IF NOT EXISTS tax;
COMMENT ON SCHEMA tax IS 'Схема для податкових даних';

CREATE SCHEMA IF NOT EXISTS analytics;
COMMENT ON SCHEMA analytics IS 'Схема для аналітичних даних';

CREATE SCHEMA IF NOT EXISTS users;
COMMENT ON SCHEMA users IS 'Схема для даних користувачів';

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
    status VARCHAR(50) DEFAULT 'pending', -- Added default status
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_goods_value CHECK (goods_value >= 0), -- Added check constraint
    CONSTRAINT chk_goods_weight CHECK (goods_weight >= 0), -- Added check constraint
    CONSTRAINT chk_customs_value CHECK (customs_value >= 0), -- Added check constraint
    CONSTRAINT chk_customs_duty CHECK (customs_duty >= 0), -- Added check constraint
    CONSTRAINT chk_vat CHECK (vat >= 0), -- Added check constraint
    CONSTRAINT chk_total_taxes CHECK (total_taxes >= 0) -- Added check constraint
);
COMMENT ON TABLE customs.declarations IS 'Таблиця для зберігання митних декларацій';
COMMENT ON COLUMN customs.declarations.id IS 'Унікальний ідентифікатор декларації';
COMMENT ON COLUMN customs.declarations.declaration_number IS 'Номер декларації';
COMMENT ON COLUMN customs.declarations.declaration_date IS 'Дата декларації';
COMMENT ON COLUMN customs.declarations.company_name IS 'Назва компанії';
COMMENT ON COLUMN customs.declarations.company_code IS 'Код компанії';
COMMENT ON COLUMN customs.declarations.goods_description IS 'Опис товару';
COMMENT ON COLUMN customs.declarations.goods_code IS 'Код товару';
COMMENT ON COLUMN customs.declarations.goods_value IS 'Вартість товару';
COMMENT ON COLUMN customs.declarations.goods_weight IS 'Вага товару';
COMMENT ON COLUMN customs.declarations.country_of_origin IS 'Країна походження';
COMMENT ON COLUMN customs.declarations.customs_value IS 'Митна вартість';
COMMENT ON COLUMN customs.declarations.customs_duty IS 'Мито';
COMMENT ON COLUMN customs.declarations.vat IS 'ПДВ';
COMMENT ON COLUMN customs.declarations.total_taxes IS 'Загальна сума податків';
COMMENT ON COLUMN customs.declarations.customs_office IS 'Митний орган';
COMMENT ON COLUMN customs.declarations.customs_officer IS 'Митний інспектор';
COMMENT ON COLUMN customs.declarations.status IS 'Статус декларації';
COMMENT ON COLUMN customs.declarations.source IS 'Джерело даних';
COMMENT ON COLUMN customs.declarations.created_at IS 'Дата створення запису';
COMMENT ON COLUMN customs.declarations.updated_at IS 'Дата оновлення запису';

-- Створення індексів для митних декларацій
CREATE INDEX IF NOT EXISTS idx_declarations_company_code ON customs.declarations(company_code);
CREATE INDEX IF NOT EXISTS idx_declarations_declaration_date ON customs.declarations(declaration_date);
CREATE INDEX IF NOT EXISTS idx_declarations_goods_code ON customs.declarations(goods_code);
CREATE INDEX IF NOT EXISTS idx_declarations_country_of_origin ON customs.declarations(country_of_origin);
CREATE INDEX IF NOT EXISTS idx_declarations_status ON customs.declarations(status); -- Added index for status
CREATE INDEX IF NOT EXISTS idx_declarations_source ON customs.declarations(source); -- Added index for source

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
    status VARCHAR(50) DEFAULT 'pending', -- Added default status
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_goods_value CHECK (goods_value >= 0), -- Added check constraint
    CONSTRAINT chk_tax_amount CHECK (tax_amount >= 0), -- Added check constraint
    CONSTRAINT chk_total_amount CHECK (total_amount >= 0), -- Added check constraint
    CONSTRAINT chk_tax_rate CHECK (tax_rate >= 0) -- Added check constraint
);
COMMENT ON TABLE tax.invoices IS 'Таблиця для зберігання податкових накладних';
COMMENT ON COLUMN tax.invoices.id IS 'Унікальний ідентифікатор накладної';
COMMENT ON COLUMN tax.invoices.invoice_number IS 'Номер накладної';
COMMENT ON COLUMN tax.invoices.invoice_date IS 'Дата накладної';
COMMENT ON COLUMN tax.invoices.seller_name IS 'Назва продавця';
COMMENT ON COLUMN tax.invoices.seller_code IS 'Код продавця';
COMMENT ON COLUMN tax.invoices.buyer_name IS 'Назва покупця';
COMMENT ON COLUMN tax.invoices.buyer_code IS 'Код покупця';
COMMENT ON COLUMN tax.invoices.goods_description IS 'Опис товару';
COMMENT ON COLUMN tax.invoices.goods_code IS 'Код товару';
COMMENT ON COLUMN tax.invoices.goods_value IS 'Вартість товару';
COMMENT ON COLUMN tax.invoices.tax_amount IS 'Сума податку';
COMMENT ON COLUMN tax.invoices.total_amount IS 'Загальна сума';
COMMENT ON COLUMN tax.invoices.tax_rate IS 'Ставка податку';
COMMENT ON COLUMN tax.invoices.status IS 'Статус накладної';
COMMENT ON COLUMN tax.invoices.source IS 'Джерело даних';
COMMENT ON COLUMN tax.invoices.created_at IS 'Дата створення запису';
COMMENT ON COLUMN tax.invoices.updated_at IS 'Дата оновлення запису';

-- Створення індексів для податкових накладних
CREATE INDEX IF NOT EXISTS idx_invoices_seller_code ON tax.invoices(seller_code);
CREATE INDEX IF NOT EXISTS idx_invoices_buyer_code ON tax.invoices(buyer_code);
CREATE INDEX IF NOT EXISTS idx_invoices_invoice_date ON tax.invoices(invoice_date);
CREATE INDEX IF NOT EXISTS idx_invoices_goods_code ON tax.invoices(goods_code);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON tax.invoices(status); -- Added index for status
CREATE INDEX IF NOT EXISTS idx_invoices_source ON tax.invoices(source); -- Added index for source

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
    risk_score DECIMAL(5, 2) DEFAULT 0.0, -- Added default value
    is_active BOOLEAN DEFAULT TRUE,
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_risk_score CHECK (risk_score >= 0 AND risk_score <= 1) -- Added check constraint
);
COMMENT ON TABLE analytics.companies IS 'Таблиця для зберігання інформації про компанії';
COMMENT ON COLUMN analytics.companies.id IS 'Унікальний ідентифікатор компанії';
COMMENT ON COLUMN analytics.companies.company_code IS 'Код компанії';
COMMENT ON COLUMN analytics.companies.company_name IS 'Назва компанії';
COMMENT ON COLUMN analytics.companies.registration_date IS 'Дата реєстрації';
COMMENT ON COLUMN analytics.companies.address IS 'Адреса';
COMMENT ON COLUMN analytics.companies.phone IS 'Телефон';
COMMENT ON COLUMN analytics.companies.email IS 'Електронна пошта';
COMMENT ON COLUMN analytics.companies.website IS 'Веб-сайт';
COMMENT ON COLUMN analytics.companies.industry IS 'Галузь';
COMMENT ON COLUMN analytics.companies.risk_score IS 'Рівень ризику';
COMMENT ON COLUMN analytics.companies.is_active IS 'Статус активності';
COMMENT ON COLUMN analytics.companies.source IS 'Джерело даних';
COMMENT ON COLUMN analytics.companies.created_at IS 'Дата створення запису';
COMMENT ON COLUMN analytics.companies.updated_at IS 'Дата оновлення запису';

-- Створення індексів для компаній
CREATE INDEX IF NOT EXISTS idx_companies_company_code ON analytics.companies(company_code);
CREATE INDEX IF NOT EXISTS idx_companies_risk_score ON analytics.companies(risk_score);
CREATE INDEX IF NOT EXISTS idx_companies_is_active ON analytics.companies(is_active); -- Added index for is_active
CREATE INDEX IF NOT EXISTS idx_companies_source ON analytics.companies(source); -- Added index for source

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
    resolved_by INTEGER REFERENCES users.users(id), -- Added foreign key
    resolution_notes TEXT,
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_confidence_score CHECK (confidence_score >= 0 AND confidence_score <= 1) -- Added check constraint
);
COMMENT ON TABLE analytics.anomalies IS 'Таблиця для зберігання інформації про аномалії';
COMMENT ON COLUMN analytics.anomalies.id IS 'Унікальний ідентифікатор аномалії';
COMMENT ON COLUMN analytics.anomalies.entity_type IS 'Тип сутності';
COMMENT ON COLUMN analytics.anomalies.entity_id IS 'Ідентифікатор сутності';
COMMENT ON COLUMN analytics.anomalies.anomaly_type IS 'Тип аномалії';
COMMENT ON COLUMN analytics.anomalies.anomaly_description IS 'Опис аномалії';
COMMENT ON COLUMN analytics.anomalies.confidence_score IS 'Рівень впевненості';
COMMENT ON COLUMN analytics.anomalies.detected_at IS 'Дата виявлення';
COMMENT ON COLUMN analytics.anomalies.status IS 'Статус аномалії';
COMMENT ON COLUMN analytics.anomalies.resolved_at IS 'Дата вирішення';
COMMENT ON COLUMN analytics.anomalies.resolved_by IS 'Користувач, який вирішив аномалію';
COMMENT ON COLUMN analytics.anomalies.resolution_notes IS 'Примітки щодо вирішення аномалії';
COMMENT ON COLUMN analytics.anomalies.source IS 'Джерело даних';
COMMENT ON COLUMN analytics.anomalies.created_at IS 'Дата створення запису';
COMMENT ON COLUMN analytics.anomalies.updated_at IS 'Дата оновлення запису';

-- Створення індексів для аномалій
CREATE INDEX IF NOT EXISTS idx_anomalies_entity_type_id ON analytics.anomalies(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_anomalies_status ON analytics.anomalies(status);
CREATE INDEX IF NOT EXISTS idx_anomalies_confidence_score ON analytics.anomalies(confidence_score);
CREATE INDEX IF NOT EXISTS idx_anomalies_anomaly_type ON analytics.anomalies(anomaly_type); -- Added index for anomaly_type
CREATE INDEX IF NOT EXISTS idx_anomalies_source ON analytics.anomalies(source); -- Added index for source

-- Створення таблиці для кластерів
CREATE TABLE IF NOT EXISTS analytics.clusters (
    id SERIAL PRIMARY KEY,
    cluster_name VARCHAR(100) NOT NULL,
    cluster_description TEXT,
    entity_type VARCHAR(50) NOT NULL, -- 'declaration', 'invoice', 'company'
    algorithm VARCHAR(100) NOT NULL,
    parameters JSONB,
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE analytics.clusters IS 'Таблиця для зберігання інформації про кластери';
COMMENT ON COLUMN analytics.clusters.id IS 'Унікальний ідентифікатор кластера';
COMMENT ON COLUMN analytics.clusters.cluster_name IS 'Назва кластера';
COMMENT ON COLUMN analytics.clusters.cluster_description IS 'Опис кластера';
COMMENT ON COLUMN analytics.clusters.entity_type IS 'Тип сутності';
COMMENT ON COLUMN analytics.clusters.algorithm IS 'Алгоритм кластеризації';
COMMENT ON COLUMN analytics.clusters.parameters IS 'Параметри кластеризації';
COMMENT ON COLUMN analytics.clusters.source IS 'Джерело даних';
COMMENT ON COLUMN analytics.clusters.created_at IS 'Дата створення запису';
COMMENT ON COLUMN analytics.clusters.updated_at IS 'Дата оновлення запису';

-- Створення таблиці для зв'язків між кластерами та сутностями
CREATE TABLE IF NOT EXISTS analytics.cluster_entities (
    id SERIAL PRIMARY KEY,
    cluster_id INTEGER NOT NULL REFERENCES analytics.clusters(id),
    entity_type VARCHAR(50) NOT NULL,
    entity_id INTEGER NOT NULL,
    similarity_score DECIMAL(5, 2),
    source VARCHAR(100), -- Added source column
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(cluster_id, entity_type, entity_id),
    CONSTRAINT chk_similarity_score CHECK (similarity_score >= 0 AND similarity_score <= 1) -- Added check constraint
);
COMMENT ON TABLE analytics.cluster_entities IS 'Таблиця для зберігання зв\'язків між кластерами та сутностями';
COMMENT ON COLUMN analytics.cluster_entities.id IS 'Унікальний ідентифікатор зв\'язку';
COMMENT ON COLUMN analytics.cluster_entities.cluster_id IS
