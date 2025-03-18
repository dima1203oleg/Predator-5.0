CREATE TABLE IF NOT EXISTS user_login_attempts (
    username VARCHAR(255) PRIMARY KEY,
    login_attempts INTEGER DEFAULT 0,
    last_attempt_time TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS deactivated_tokens (
    token TEXT PRIMARY KEY,
    деактивовано_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Додаємо індекс для швидкого пошуку
CREATE INDEX IF NOT EXISTS idx_deactivated_tokens_token ON deactivated_tokens(token);

CREATE TABLE IF NOT EXISTS user_sessions (
    session_id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    token TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (username) REFERENCES users(username) ON DELETE CASCADE
);

ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS device_info TEXT;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS ip_address INET;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS last_activity TIMESTAMP WITH TIME ЗОНЕ;
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS is_suspicious BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_user_sessions_username ON user_sessions(username);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_activity ON user_sessions(last_activity);
CREATE INDEX IF NOT EXISTS idx_user_sessions_suspicious ON user_sessions(is_suspicious);

CREATE TABLE IF NOT EXISTS roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS user_roles (
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    role_id INTEGER REFERENCES roles(role_id) ON DELETE CASCADE,
    PRIMARY KEY (username, role_id)
);

CREATE TABLE IF NOT EXISTS permissions (
    permission_id SERIAL PRIMARY KEY,
    permission_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INTEGER REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_id INTEGER REFERENCES permissions(permission_id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_activity (
    activity_id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    action VARCHAR(100) NOT NULL,
    details JSONB,
    ip_address INET,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_activity_username ON user_activity(username);
CREATE INDEX IF NOT EXISTS idx_user_activity_created_at ON user_activity(created_at);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    token TEXT PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ЗОНЕ NOT NULL,
    used BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_username ON password_reset_tokens(username);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_expires ON password_reset_tokens(expires_at);

CREATE TABLE IF NOT EXISTS two_factor_auth (
    username VARCHAR(255) PRIMARY KEY REFERENCES users(username) ON DELETE CASCADE,
    secret_key TEXT NOT NULL,
    is_enabled BOOLEAN DEFAULT FALSE,
    backup_codes TEXT[] DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

-- Додаємо тригер для автоматичного оновлення updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_two_factor_auth_updated_at
    BEFORE UPDATE ON two_factor_auth
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Додаємо індекс для оптимізації очищення старих записів
CREATE INDEX IF NOT EXISTS idx_two_factor_auth_cleanup 
ON two_factor_auth(is_enabled, updated_at);

-- Додаємо індекс для токенів скидання паролю
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_cleanup 
ON password_reset_tokens(used, created_at, expires_at);

-- Додаємо базові ролі
INSERT INTO roles (role_name, description) 
VALUES 
    ('admin', 'Адміністратор системи'),
    ('user', 'Звичайний користувач'),
    ('analyst', 'Аналітик даних')
ON CONFLICT DO NOTHING;

-- Додаємо базові дозволи
INSERT INTO permissions (permission_name, description) 
VALUES 
    ('create_report', 'Створення звітів'),
    ('edit_report', 'Редагування звітів'),
    ('delete_report', 'Видалення звітів'),
    ('view_analytics', 'Перегляд аналітики'),
    ('manage_users', 'Керування користувачами'),
    ('manage_roles', 'Керування ролями'),
    ('view_user_activity', 'Перегляд активності користувачів'),
    ('manage_user_roles', 'Керування ролями користувачів'),
    ('block_users', 'Блокування користувачів'),
    ('reset_user_password', 'Скидання паролю користувача'),
    ('manage_2fa', 'Керування двофакторною автентифікацією')
ON CONFLICT DO NOTHING;

-- Призначаємо дозволи ролям
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM roles r, permissions p
WHERE 
    (r.role_name = 'admin') OR
    (r.role_name = 'analyst' AND p.permission_name IN ('create_report', 'edit_report', 'view_analytics')) OR
    (r.role_name = 'user' AND p.permission_name = 'view_analytics')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS auth_statistics (
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    last_successful_login TIMESTAMP WITH TIME ЗОНЕ,
    last_failed_login TIMESTAMP WITH TIME ЗОНЕ,
    successful_logins INTEGER DEFAULT 0,
    failed_logins INTEGER DEFAULT 0,
    last_ip_address INET,
    PRIMARY KEY (username)
);

CREATE INDEX IF NOT EXISTS idx_auth_statistics_logins 
ON auth_statistics(last_successful_login, last_failed_login);

-- Оновлюємо тригер для очищення даних
CREATE OR REPLACE FUNCTION cleanup_old_auth_data()
RETURNS void AS $$
BEGIN
    -- Видаляємо старі записи статистики (старші 90 днів)
    DELETE FROM auth_statistics 
    WHERE last_successful_login < NOW() - INTERVAL '90 days' 
    AND last_failed_login < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql;

-- Додаємо нову таблицю для підозрілої активності
CREATE TABLE IF NOT EXISTS suspicious_activity (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    session_id UUID REFERENCES user_sessions(session_id) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,
    details JSONB,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_suspicious_activity_username ON suspicious_activity(username);
CREATE INDEX IF NOT EXISTS idx_suspicious_activity_type ON suspicious_activity(activity_type);

-- Додаємо таблицю для зберігання геолокації
CREATE TABLE IF NOT EXISTS user_locations (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    ip_address INET,
    country_code VARCHAR(2),
    city VARCHAR(100),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    is_trusted BOOLEAN DEFAULT FALSE,
    first_seen TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_locations_username ON user_locations(username);
CREATE INDEX IF NOT EXISTS idx_user_locations_ip ON user_locations(ip_address);
CREATE INDEX IF NOT EXISTS idx_user_locations_trusted ON user_locations(is_trusted);

-- Додаємо таблицю для аномалій
CREATE TABLE IF NOT EXISTS user_anomalies (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    anomaly_type VARCHAR(50) NOT NULL,
    severity INTEGER NOT NULL, -- 1-низька, 2-середня, 3-висока
    details JSONB,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP WITH TIME ЗОНЕ,
    resolved_by VARCHAR(255) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_user_anomalies_username ON user_anomalies(username);
CREATE INDEX IF NOT EXISTS idx_user_anomalies_type ON user_anomalies(anomaly_type);
CREATE INDEX IF NOT EXISTS idx_user_anomalies_severity ON user_anomalies(severity);

-- Додаємо таблицю для збереження патернів поведінки користувачів
CREATE TABLE IF NOT EXISTS user_behavior_patterns (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    pattern_type VARCHAR(50) NOT NULL,
    pattern_data JSONB NOT NULL,
    confidence FLOAT NOT NULL,
    last_updated TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_patterns_username ON user_behavior_patterns(username);
CREATE INDEX IF NOT EXISTS idx_user_patterns_type ON user_behavior_patterns(pattern_type);

-- Додаємо таблицю для оцінки ризиків
CREATE TABLE IF NOT EXISTS risk_assessments (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) REFERENCES users(username) ON DELETE CASCADE,
    risk_score INTEGER NOT NULL,
    risk_factors JSONB,
    assessed_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_risk_assessment_username ON risk_assessments(username);
CREATE INDEX IF NOT EXISTS idx_risk_assessment_score ON risk_assessments(risk_score);

-- Додаємо таблицю для метрик безпеки
CREATE TABLE IF NOT EXISTS security_metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    dimension JSONB,
    measured_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_security_metrics_name ON security_metrics(metric_name);
CREATE INDEX IF NOT EXISTS idx_security_metrics_time ON security_metrics(measured_at);

-- Додаємо таблицю для порогових значень метрик
CREATE TABLE IF NOT EXISTS metric_thresholds (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    warning_threshold FLOAT,
    critical_threshold FLOAT,
    last_updated TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

-- Додаємо таблицю для сповіщень безпеки
CREATE TABLE IF NOT EXISTS security_alerts (
    id SERIAL PRIMARY KEY,
    alert_type VARCHAR(50) NOT NULL,
    severity INTEGER NOT NULL CHECK (severity BETWEEN 1 AND 5),
    details JSONB NOT NULL,
    is_resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP WITH TIME ЗОНЕ,
    resolved_by VARCHAR(255) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_security_alerts_type ON security_alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_security_alerts_severity ON security_alerts(severity);
CREATE INDEX IF NOT EXISTS idx_security_alerts_resolved ON security_alerts(is_resolved);

-- Додаємо базові порогові значення
INSERT INTO metric_thresholds (metric_name, warning_threshold, critical_threshold) 
VALUES 
    ('failed_login_rate', 0.1, 0.3),
    ('suspicious_sessions_rate', 0.05, 0.15),
    ('anomaly_detection_rate', 0.2, 0.4)
ON CONFLICT DO NOTHING;

-- Додаємо таблицю для шаблонів атак
CREATE TABLE IF NOT EXISTS attack_patterns (
    id SERIAL PRIMARY KEY,
    pattern_name VARCHAR(100) NOT NULL,
    pattern_type VARCHAR(50) NOT NULL,
    detection_rules JSONB NOT NULL,
    severity INTEGER NOT NULL CHECK (severity BETWEEN 1 AND 5),
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_attack_patterns_type ON attack_patterns(pattern_type);

-- Додаємо таблицю для виявлених атак
CREATE TABLE IF NOT EXISTS detected_attacks (
    id SERIAL PRIMARY KEY,
    pattern_id INTEGER REFERENCES attack_patterns(id),
    username VARCHAR(255) REFERENCES users(username),
    attack_data JSONB NOT NULL,
    confidence FLOAT NOT NULL,
    detected_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    is_false_positive BOOLEAN DEFAULT FALSE,
    reviewed_by VARCHAR(255) REFERENCES users(username),
    reviewed_at TIMESTAMP WITH TIME ЗОНЕ
);

CREATE INDEX IF NOT EXISTS idx_detected_attacks_pattern ON detected_attacks(pattern_id);
CREATE INDEX IF NOT EXISTS idx_detected_attacks_user ON detected_attacks(username);
CREATE INDEX IF NOT EXISTS idx_detected_attacks_time ON detected_attacks(detected_at);

-- Додаємо базові шаблони атак
INSERT INTO attack_patterns (pattern_name, pattern_type, detection_rules, severity) 
VALUES 
    ('Brute Force', 'authentication', 
     '{"conditions": {"failed_attempts": 10, "time_window": "5m"}}', 4),
    ('Password Spray', 'authentication', 
     '{"conditions": {"unique_users": 5, "time_window": "10m"}}', 4),
    ('Session Hijacking', 'session', 
     '{"conditions": {"ip_changes": 3, "time_window": "1m"}}', 5),
    ('Credential Stuffing', 'authentication', 
     '{"conditions": {"success_rate": 0.1, "min_attempts": 20}}', 4)
ON CONFLICT DO NOTHING;

-- Додаємо таблицю для аналітичних звітів
CREATE TABLE IF NOT EXISTS security_reports (
    id SERIAL PRIMARY KEY,
    report_type VARCHAR(50) NOT NULL,
    period_start TIMESTAMP WITH TIME ЗОНЕ NOT NULL,
    period_end TIMESTAMP WITH TIME ЗОНЕ NOT NULL,
    metrics JSONB NOT NULL,
    insights JSONB,
    recommendations JSONB,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    generated_by VARCHAR(255) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_security_reports_type ON security_reports(report_type);
CREATE INDEX IF NOT EXISTS idx_security_reports_period ON security_reports(period_start, period_end);

-- Додаємо таблицю для збереження тенденцій
CREATE TABLE IF NOT EXISTS security_trends (
    id SERIAL PRIMARY KEY,
    trend_type VARCHAR(50) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    trend_data JSONB NOT NULL,
    confidence FLOAT NOT NULL,
    detected_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_security_trends_type ON security_trends(trend_type);
CREATE INDEX IF NOT EXISTS idx_security_trends_metric ON security_trends(metric_name);

-- Додаємо таблицю для візуалізацій
CREATE TABLE IF NOT EXISTS security_visualizations (
    id SERIAL PRIMARY KEY,
    visualization_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    data_query TEXT NOT NULL,
    chart_config JSONB NOT NULL,
    parameters JSONB,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) REFERENCES users(username)
);

CREATE INDEX IF NOT EXISTS idx_security_visualizations_type 
ON security_visualizations(visualization_type);

-- Додаємо таблицю для збереження згенерованих звітів
CREATE TABLE IF NOT EXISTS exported_reports (
    id SERIAL PRIMARY KEY,
    report_id INTEGER REFERENCES security_reports(id),
    format VARCHAR(20) NOT NULL,
    file_path TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255) REFERENCES users(username),
    expiry_date TIMESTAMP WITH TIME ЗОНЕ
);

CREATE INDEX IF NOT EXISTS idx_exported_reports_report 
ON exported_reports(report_id);

-- Додаємо тригер для автоматичного оновлення updated_at
CREATE TRIGGER update_security_visualizations_updated_at
    BEFORE UPDATE ON security_visualizations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Додаємо таблицю для планування звітів
CREATE TABLE IF NOT EXISTS report_schedules (
    id SERIAL PRIMARY KEY,
    report_type VARCHAR(50) NOT NULL,
    schedule_config JSONB NOT NULL,
    parameters JSONB,
    created_by VARCHAR(255) REFERENCES users(username),
    created_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    next_run TIMESTAMP WITH TIME ЗОНЕ NOT NULL,
    last_run TIMESTAMP WITH TIME ЗОНЕ,
    last_status VARCHAR(20),
    last_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_report_schedules_next_run 
ON report_schedules(next_run);

-- Додаємо таблицю для збереження результатів запланованих звітів
CREATE TABLE IF NOT EXISTS scheduled_report_results (
    id SERIAL PRIMARY KEY,
    schedule_id INTEGER REFERENCES report_schedules(id),
    report_id INTEGER REFERENCES security_reports(id),
    run_at TIMESTAMP WITH TIME ЗОНЕ DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    error_message TEXT,
    notification_sent BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_scheduled_report_results_schedule 
ON scheduled_report_results(schedule_id);
