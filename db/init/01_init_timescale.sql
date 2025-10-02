-- =============================================================================
-- DATAYOTI - SCHÉMA DE BASE DE DONNÉES TIMESCALEDB
-- =============================================================================
-- Ce script initialise la base de données TimescaleDB pour le projet DataYoti
-- Il crée les tables nécessaires pour stocker les données des capteurs IoT
--
-- SÉCURITÉ: Ce script utilise des mots de passe temporaires pour les utilisateurs.
-- Les vrais mots de passe sont définis via le script 02_update_passwords.sh
-- qui utilise les variables d'environnement du docker-compose.yml
-- =============================================================================

-- Activer l'extension TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- =============================================================================
-- TABLE DES SITES
-- =============================================================================
-- Table de référence pour stocker les informations des sites
CREATE TABLE IF NOT EXISTS sites (
    site_id VARCHAR(50) PRIMARY KEY,
    site_name VARCHAR(255),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insérer quelques sites par défaut basés sur les données existantes
INSERT INTO sites (site_id, site_name, description) VALUES 
    ('SITE_001', 'Site Nord (Salon)', 'Capteur principal du salon'),
    ('SITE_002', 'Site Sud (Chambre Sab)', 'Capteur de la chambre de Sab'),
    ('SITE_003', 'Site Est (Chambre Anna)', 'Capteur de la chambre de Anna'),
    ('SITE_004', 'Site Ouest (Cave)', 'Capteur de la cave')
ON CONFLICT (site_id) DO NOTHING;

-- =============================================================================
-- TABLE DES CAPTEURS
-- =============================================================================
-- Table de référence pour stocker les informations des capteurs
CREATE TABLE IF NOT EXISTS devices (
    device_id VARCHAR(17) PRIMARY KEY,  -- Format MAC address: XX:XX:XX:XX:XX:XX
    site_id VARCHAR(50) REFERENCES sites(site_id),
    device_name VARCHAR(255),
    device_type VARCHAR(50) DEFAULT 'temperature_humidity',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =============================================================================
-- TABLE PRINCIPALE DES DONNÉES DES CAPTEURS (HYPERTABLE)
-- =============================================================================
-- Table principale pour stocker toutes les mesures des capteurs (les unités de mesures sont fixes donc pas besoin de les stocker)
CREATE TABLE IF NOT EXISTS sensor_data (
    time TIMESTAMP WITH TIME ZONE NOT NULL,  -- Timestamp du capteur
    device_id VARCHAR(17) NOT NULL,          -- ID du device (MAC address)
    site_id VARCHAR(50) NOT NULL,            -- ID du site
    temperature REAL,                        -- Température mesurée
    humidity REAL,                           -- Humidité mesurée
    reception_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Timestamp de réception

    -- Contraintes
    FOREIGN KEY (device_id) REFERENCES devices(device_id),
    FOREIGN KEY (site_id) REFERENCES sites(site_id)
);

-- Créer l'hypertable avec partitionnement par temps (1 jour par chunk)
SELECT create_hypertable('sensor_data', 'time', if_not_exists => TRUE, chunk_time_interval => INTERVAL '1 day');

-- Ajouter une contrainte unique (syntaxe compatible PostgreSQL)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sensor_data_uniq') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT sensor_data_uniq UNIQUE (device_id, time);
    END IF;
END
$$;

-- =============================================================================
-- TABLE DES HEARTBEATS
-- =============================================================================
-- Table pour stocker les heartbeats des capteurs
CREATE TABLE IF NOT EXISTS device_heartbeats (
    time TIMESTAMP WITH TIME ZONE NOT NULL,  -- Timestamp du heartbeat
    device_id VARCHAR(17) NOT NULL,          -- ID du device
    site_id VARCHAR(50) NOT NULL,            -- ID du site
    status VARCHAR(20) DEFAULT 'online',     -- Statut du device
    rssi INTEGER,                            -- Force du signal WiFi
    free_heap INTEGER,                       -- Mémoire libre
    reception_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Contraintes
    FOREIGN KEY (device_id) REFERENCES devices(device_id),
    FOREIGN KEY (site_id) REFERENCES sites(site_id)
);

-- Créer l'hypertable pour les heartbeats (1 jour par chunk)
SELECT create_hypertable('device_heartbeats', 'time', if_not_exists => TRUE, chunk_time_interval => INTERVAL '1 day');

-- Ajouter une contrainte unique pour les heartbeats
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'device_heartbeats_uniq') THEN
        ALTER TABLE device_heartbeats ADD CONSTRAINT device_heartbeats_uniq UNIQUE (device_id, time);
    END IF;
END
$$;

-- =============================================================================
-- TABLE DES STATUTS DES DEVICES
-- =============================================================================
-- Table pour stocker les messages de statut des capteurs
CREATE TABLE IF NOT EXISTS device_status (
    time TIMESTAMP WITH TIME ZONE NOT NULL,  -- Timestamp du message
    device_id VARCHAR(17) NOT NULL,          -- ID du device
    site_id VARCHAR(50) NOT NULL,            -- ID du site
    status_type VARCHAR(50),                 -- Type de statut
    status_data JSONB,                       -- Données de statut (format JSON)
    reception_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Contraintes
    FOREIGN KEY (device_id) REFERENCES devices(device_id),
    FOREIGN KEY (site_id) REFERENCES sites(site_id)
);

-- Créer l'hypertable pour les statuts (1 jour par chunk)
SELECT create_hypertable('device_status', 'time', if_not_exists => TRUE, chunk_time_interval => INTERVAL '1 day');

-- Ajouter une contrainte unique pour les statuts
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'device_status_uniq') THEN
        ALTER TABLE device_status ADD CONSTRAINT device_status_uniq UNIQUE (device_id, time, status_type);
    END IF;
END
$$;

-- =============================================================================
-- INDEX POUR OPTIMISER LES PERFORMANCES
-- =============================================================================

-- Index sur device_id pour les requêtes par capteur
CREATE INDEX IF NOT EXISTS idx_sensor_data_device_id ON sensor_data (device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_heartbeats_device_id ON device_heartbeats (device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_status_device_id ON device_status (device_id, time DESC);

-- Index sur site_id pour les requêtes par site
CREATE INDEX IF NOT EXISTS idx_sensor_data_site_id ON sensor_data (site_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_heartbeats_site_id ON device_heartbeats (site_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_status_site_id ON device_status (site_id, time DESC);

-- =============================================================================
-- VUES UTILES POUR L'ANALYSE
-- =============================================================================

-- Vue pour les dernières mesures de chaque capteur
CREATE OR REPLACE VIEW latest_sensor_readings AS
SELECT DISTINCT ON (device_id)
    device_id,
    site_id,
    time,
    temperature,
    humidity,
    reception_time
FROM sensor_data
ORDER BY device_id, time DESC;

-- Vue pour le statut des capteurs (derniers heartbeats)
CREATE OR REPLACE VIEW device_health AS
SELECT DISTINCT ON (device_id)
    device_id,
    site_id,
    time as last_heartbeat,
    status,
    rssi,
    free_heap,
    CASE 
        WHEN time > NOW() - INTERVAL '5 minutes' THEN 'online'
        WHEN time > NOW() - INTERVAL '30 minutes' THEN 'warning'
        ELSE 'offline'
    END as health_status
FROM device_heartbeats
ORDER BY device_id, time DESC;

-- Vue pour les statistiques quotidiennes par capteur
CREATE OR REPLACE VIEW daily_sensor_stats AS
SELECT 
    device_id,
    site_id,
    date_trunc('day', time) as day,
    COUNT(temperature) as measurement_count,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity
FROM sensor_data
GROUP BY device_id, site_id, date_trunc('day', time)
ORDER BY day DESC, device_id;

-- =============================================================================
-- POLITIQUES DE RÉTENTION DES DONNÉES
-- =============================================================================

-- Politique de rétention : garder les données détaillées pendant 1 an
SELECT add_retention_policy('sensor_data', INTERVAL '1 year');
SELECT add_retention_policy('device_heartbeats', INTERVAL '6 months');
SELECT add_retention_policy('device_status', INTERVAL '3 months');

-- =============================================================================
-- AGRÉGATIONS CONTINUES POUR LES PERFORMANCES
-- =============================================================================

-- Agrégation continue pour les moyennes horaires
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_data_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', time) AS bucket,
    device_id,
    site_id,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity,
    COUNT(*) as measurement_count
FROM sensor_data
GROUP BY bucket, device_id, site_id;

-- Politique de rafraîchissement pour l'agrégation horaire
SELECT add_continuous_aggregate_policy('sensor_data_hourly',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '0',
    schedule_interval => INTERVAL '5 minutes');

-- Agrégation continue pour les moyennes quotidiennes
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_data_daily
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', time) AS bucket,
    device_id,
    site_id,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity,
    COUNT(*) as measurement_count
FROM sensor_data
GROUP BY bucket, device_id, site_id;

-- Politique de rafraîchissement pour l'agrégation quotidienne
SELECT add_continuous_aggregate_policy('sensor_data_daily',
    start_offset => INTERVAL '30 days',
    end_offset => INTERVAL '0',
    schedule_interval => INTERVAL '1 hour');

-- =============================================================================
-- PERMISSIONS ET SÉCURITÉ
-- =============================================================================

-- Créer un utilisateur spécifique pour l'ingesteur MQTT
-- (sera utilisé par l'application ingestor)
-- IMPORTANT: Ce script utilise un mot de passe temporaire qui DOIT être changé
-- après l'initialisation via: ALTER ROLE mqtt_ingestor PASSWORD 'nouveau_mot_de_passe';
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mqtt_ingestor') THEN
        CREATE ROLE mqtt_ingestor WITH LOGIN PASSWORD 'TEMP_PASSWORD_CHANGE_ME';
    END IF;
END
$$;

-- Permissions pour l'ingesteur
-- Pour les hypertables TimescaleDB, il faut des permissions sur toutes les tables
GRANT INSERT, SELECT, UPDATE ON ALL TABLES IN SCHEMA public TO mqtt_ingestor;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mqtt_ingestor;
GRANT USAGE ON SCHEMA public TO mqtt_ingestor;

-- Permissions spécifiques pour les futures tables (chunks de TimescaleDB)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, SELECT, UPDATE ON TABLES TO mqtt_ingestor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO mqtt_ingestor;

-- Créer un utilisateur en lecture seule pour Grafana
-- IMPORTANT: Ce script utilise un mot de passe temporaire qui DOIT être changé
-- après l'initialisation via: ALTER ROLE grafana_reader PASSWORD 'nouveau_mot_de_passe';
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'grafana_reader') THEN
        CREATE ROLE grafana_reader WITH LOGIN PASSWORD 'TEMP_PASSWORD_CHANGE_ME';
    END IF;
END
$$;

-- Permissions pour Grafana (lecture seule)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO grafana_reader;
GRANT USAGE ON SCHEMA public TO grafana_reader;
GRANT SELECT ON sensor_data_hourly, sensor_data_daily TO grafana_reader;

-- =============================================================================
-- DONNÉES DE TEST (OPTIONNEL)
-- =============================================================================

-- Insérer quelques devices de test basés sur les données existantes
INSERT INTO devices (device_id, site_id, device_name, device_type) VALUES 
    ('1C:69:20:E9:18:24', 'SITE_001', 'Capteur Salon Principal', 'temperature_humidity'),
    ('88:13:BF:08:04:A4', 'SITE_004', 'Capteur Site 4', 'temperature_humidity'),
    ('1C:69:20:30:24:94', 'SITE_002', 'Capteur Site 2', 'temperature_humidity')
ON CONFLICT (device_id) DO NOTHING;

-- =============================================================================
-- MESSAGES DE CONFIRMATION
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'DATAYOTI - INITIALISATION DE LA BASE DE DONNÉES TERMINÉE';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Tables créées:';
    RAISE NOTICE '  ✓ sites - Informations des sites';
    RAISE NOTICE '  ✓ devices - Informations des capteurs';
    RAISE NOTICE '  ✓ sensor_data - Données des capteurs (hypertable)';
    RAISE NOTICE '  ✓ device_heartbeats - Heartbeats des capteurs (hypertable)';
    RAISE NOTICE '  ✓ device_status - Statuts des capteurs (hypertable)';
    RAISE NOTICE '';
    RAISE NOTICE 'Vues créées:';
    RAISE NOTICE '  ✓ latest_sensor_readings - Dernières mesures';
    RAISE NOTICE '  ✓ device_health - Statut des capteurs';
    RAISE NOTICE '  ✓ daily_sensor_stats - Statistiques quotidiennes';
    RAISE NOTICE '';
    RAISE NOTICE 'Agrégations continues:';
    RAISE NOTICE '  ✓ sensor_data_hourly - Moyennes horaires';
    RAISE NOTICE '  ✓ sensor_data_daily - Moyennes quotidiennes';
    RAISE NOTICE '';
    RAISE NOTICE 'Utilisateurs créés:';
    RAISE NOTICE '  ✓ mqtt_ingestor - Pour l''application d''ingestion';
    RAISE NOTICE '  ✓ grafana_reader - Pour Grafana (lecture seule)';
    RAISE NOTICE '';
    RAISE NOTICE 'Base de données prête pour l''ingestion des données MQTT!';
    RAISE NOTICE '=============================================================================';
END
$$;
