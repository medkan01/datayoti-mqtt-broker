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
-- CONFIGURATION UTC
-- =============================================================================
-- Forcer le fuseau horaire à UTC pour toute la base de données
-- Ceci garantit que toutes les opérations temporelles sont en UTC
SET timezone = 'UTC';
ALTER DATABASE datayoti_db SET timezone = 'UTC';

-- Message de confirmation de la configuration UTC
DO $$
BEGIN
    RAISE NOTICE 'Base de données configurée en UTC : %', current_setting('timezone');
END
$$;

-- =============================================================================
-- TABLE DES SITES
-- =============================================================================
-- Table de référence pour stocker les informations des sites
CREATE TABLE IF NOT EXISTS sites (
    id SERIAL PRIMARY KEY,                   -- ID auto-incrémenté
    site_ref VARCHAR(50) UNIQUE NOT NULL,    -- Référence unique du site
    site_name VARCHAR(255),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index sur site_ref pour les recherches rapides
CREATE INDEX IF NOT EXISTS idx_sites_site_ref ON sites(site_ref);

-- Insérer quelques sites par défaut basés sur les données existantes
INSERT INTO sites (site_ref, site_name, description) VALUES 
    ('SITE_001', 'Site Nord (Salon)', 'Capteur principal du salon'),
    ('SITE_002', 'Site Sud (Chambre Sab)', 'Capteur de la chambre de Sab'),
    ('SITE_003', 'Site Est (Chambre Anna)', 'Capteur de la chambre de Anna'),
    ('SITE_004', 'Site Ouest (Cave)', 'Capteur de la cave')
ON CONFLICT (site_ref) DO NOTHING;

-- =============================================================================
-- TABLE DES CAPTEURS
-- =============================================================================
-- Table de référence pour stocker les informations minimales des capteurs
-- Structure simplifiée : seules les informations essentielles sont conservées
CREATE TABLE IF NOT EXISTS devices (
    id SERIAL PRIMARY KEY,                   -- ID auto-incrémenté pour référence interne
    device_mac_addr VARCHAR(17) UNIQUE NOT NULL,   -- Format MAC address: XX:XX:XX:XX:XX:XX
    site_ref VARCHAR(50) REFERENCES sites(site_ref), -- Référence vers le site d'installation
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Date de création de l'entrée
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()  -- Date de dernière modification
);

-- Index sur device_mac_addr pour les recherches rapides
CREATE INDEX IF NOT EXISTS idx_devices_device_mac_addr ON devices(device_mac_addr);
CREATE INDEX IF NOT EXISTS idx_devices_site_ref ON devices(site_ref);

-- Insérer quelques devices de test basés sur les vraies adresses MAC ESP32
INSERT INTO devices (device_mac_addr, site_ref) VALUES
    ('1C:69:20:E9:18:24', 'SITE_001'),  -- ESP32 #1
    ('88:13:BF:08:04:A4', 'SITE_002'),  -- ESP32 #2  
    ('1C:69:20:30:24:94', 'SITE_003'),  -- ESP32 #3
    ('1C:69:20:E9:10:4C', 'SITE_004')   -- ESP32 #4
ON CONFLICT (device_mac_addr) DO NOTHING;

-- =============================================================================
-- TABLE PRINCIPALE DES DONNÉES DES CAPTEURS (HYPERTABLE)
-- =============================================================================
-- Table principale pour stocker toutes les mesures des capteurs
-- Les unités sont fixes : température en °C, humidité en %
-- Le site_ref est volontairement absent car non envoyé par les capteurs ESP32
CREATE TABLE IF NOT EXISTS sensor_data (
    time TIMESTAMP WITH TIME ZONE NOT NULL,  -- Timestamp du capteur (UTC)
    device_mac_addr VARCHAR(17) NOT NULL,          -- ID du device (MAC address)
    temperature REAL,                        -- Température mesurée en °C
    humidity REAL,                           -- Humidité mesurée en %
    reception_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Timestamp de réception (UTC)

    -- Contraintes
    FOREIGN KEY (device_mac_addr) REFERENCES devices(device_mac_addr)
);

-- Créer l'hypertable avec partitionnement par temps (1 jour par chunk)
SELECT create_hypertable('sensor_data', 'time', if_not_exists => TRUE, chunk_time_interval => INTERVAL '1 day');

-- Ajouter une contrainte unique (syntaxe compatible PostgreSQL)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sensor_data_uniq') THEN
        ALTER TABLE sensor_data ADD CONSTRAINT sensor_data_uniq UNIQUE (device_mac_addr, time);
    END IF;
END
$$;

-- =============================================================================
-- TABLE DES HEARTBEATS
-- =============================================================================
-- Table pour stocker les heartbeats des capteurs ESP32
-- Contient les informations de santé et de connectivité des capteurs
CREATE TABLE IF NOT EXISTS device_heartbeats (
    time TIMESTAMP WITH TIME ZONE NOT NULL,  -- Timestamp du heartbeat (UTC)
    device_mac_addr VARCHAR(17) NOT NULL,          -- ID du device (MAC address)
    rssi INTEGER,                            -- Force du signal WiFi en dBm
    free_heap INTEGER,                       -- Mémoire libre actuelle en bytes
    uptime INTEGER,                          -- Temps de fonctionnement en secondes
    min_heap INTEGER,                        -- Mémoire libre minimale atteinte en bytes
    ntp_sync BOOLEAN,                        -- Statut de synchronisation NTP (true/false)
    reception_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(), -- Timestamp de réception (UTC)
    
    -- Contraintes
    FOREIGN KEY (device_mac_addr) REFERENCES devices(device_mac_addr),
    FOREIGN KEY (site_ref) REFERENCES sites(site_ref)
);

-- Créer l'hypertable pour les heartbeats (1 jour par chunk)
SELECT create_hypertable('device_heartbeats', 'time', if_not_exists => TRUE, chunk_time_interval => INTERVAL '1 day');

-- Ajouter une contrainte unique pour les heartbeats
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'device_heartbeats_uniq') THEN
        ALTER TABLE device_heartbeats ADD CONSTRAINT device_heartbeats_uniq UNIQUE (device_mac_addr, time);
    END IF;
END
$$;

-- =============================================================================
-- INDEX POUR OPTIMISER LES PERFORMANCES
-- =============================================================================

-- Index sur device_mac_addr pour les requêtes par capteur (avec tri temporel descendant)
CREATE INDEX IF NOT EXISTS idx_sensor_data_device_mac_addr ON sensor_data (device_mac_addr, time DESC);
CREATE INDEX IF NOT EXISTS idx_heartbeats_device_mac_addr ON device_heartbeats (device_mac_addr, time DESC);

-- Index sur site_ref pour les requêtes par site (seulement pour les tables qui contiennent site_ref)
-- Note: sensor_data n'a pas de site_ref car non fourni par les capteurs ESP32
CREATE INDEX IF NOT EXISTS idx_heartbeats_site_ref ON device_heartbeats (site_ref, time DESC);

-- =============================================================================
-- POLITIQUES DE RÉTENTION DES DONNÉES
-- =============================================================================

-- Politique de rétention pour optimiser l'espace disque et les performances
-- Les données anciennes sont automatiquement supprimées par TimescaleDB
SELECT add_retention_policy('sensor_data', INTERVAL '1 year');        -- Données capteurs : 1 an
SELECT add_retention_policy('device_heartbeats', INTERVAL '6 months'); -- Heartbeats : 6 mois

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
-- Note: Les permissions pour les vues matérialisées sont maintenant dans 03_create_views.sql

-- =============================================================================
-- MESSAGES DE CONFIRMATION
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'DATAYOTI - INITIALISATION DE LA BASE DE DONNÉES TERMINÉE';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Structure finale:';
    RAISE NOTICE '  ✓ sites (id, site_ref, site_name, description)';
    RAISE NOTICE '  ✓ devices (id, device_mac_addr, site_ref) - Structure simplifiée';
    RAISE NOTICE '  ✓ sensor_data (time, device_mac_addr, temperature, humidity) - Hypertable';
    RAISE NOTICE '  ✓ device_heartbeats (time, device_mac_addr, site_ref, rssi, free_heap, uptime, min_heap, ntp_sync) - Hypertable';
    RAISE NOTICE '';
    RAISE NOTICE 'Topics MQTT supportés:';
    RAISE NOTICE '  📡 datayoti/sensor/{device_mac_addr}/data → sensor_data';
    RAISE NOTICE '  💓 datayoti/sensor/{device_mac_addr}/heartbeat → device_heartbeats';
    RAISE NOTICE '';
    RAISE NOTICE 'Configuration:';
    RAISE NOTICE '  🕐 Timezone: UTC pour toutes les opérations temporelles';
    RAISE NOTICE '  🗂️  Rétention: sensor_data (1 an), heartbeats (6 mois)';
    RAISE NOTICE '  📊 Partitionnement: 1 jour par chunk TimescaleDB';
    RAISE NOTICE '';
    RAISE NOTICE 'Utilisateurs créés:';
    RAISE NOTICE '  👤 mqtt_ingestor - Ingestion des données MQTT';
    RAISE NOTICE '  👤 grafana_reader - Lecture pour Grafana (lecture seule)';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: Vues séparées dans 03_create_views.sql';
    RAISE NOTICE '  📊 latest_sensor_readings - Dernières mesures';
    RAISE NOTICE '  💓 device_health - Statut des capteurs';
    RAISE NOTICE '  📈 semi_hourly_sensor_stats - Agrégations 30min';
    RAISE NOTICE '  📊 sensor_data_hourly - Agrégations horaires';
    RAISE NOTICE 'Exécutez: .\manage_views.ps1 -Action create';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Base de données prête pour l''ingestion des données ESP32!';
    RAISE NOTICE '=============================================================================';
END
$$;
