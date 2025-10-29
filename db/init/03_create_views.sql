-- =============================================================================
-- DATAYOTI - VUES DE BASE DE DONNÉES
-- =============================================================================
-- Ce script crée toutes les vues utiles pour l'analyse des données DataYoti
-- Il peut être exécuté indépendamment pour ajouter/modifier des vues
-- 
-- IMPORTANT: Toutes les comparaisons temporelles utilisent UTC
-- Les capteurs envoient leurs données en UTC et la base est configurée en UTC
-- 
-- Usage:
--   docker exec -i datayoti-db psql -U postgres -d datayoti_db < 03_create_views.sql
-- 
-- Ou depuis un client PostgreSQL :
--   \i /docker-entrypoint-initdb.d/03_create_views.sql
-- =============================================================================

-- Vérification de la configuration UTC
DO $$
BEGIN
    IF current_setting('timezone') != 'UTC' THEN
        RAISE WARNING 'Base de données non configurée en UTC: %', current_setting('timezone');
        RAISE WARNING 'Les requêtes temporelles pourraient être incorrectes';
    ELSE
        RAISE NOTICE 'Configuration UTC confirmée: %', current_setting('timezone');
    END IF;
END
$$;

-- =============================================================================
-- VUES POUR LES DONNÉES DE CAPTEURS
-- =============================================================================

-- Vue pour les dernières mesures de chaque capteur
CREATE OR REPLACE VIEW latest_sensor_readings AS
SELECT DISTINCT ON (device_mac_addr)
    device_mac_addr,
    time,
    temperature,
    humidity,
    reception_time
FROM 
    sensor_data
ORDER BY 
    device_mac_addr, 
    time DESC;

-- Vue pour le statut des capteurs (derniers heartbeats)
CREATE OR REPLACE VIEW device_health AS
SELECT DISTINCT ON (device_mac_addr)
    device_mac_addr,
    time AS last_heartbeat,
    rssi,
    free_heap,
    uptime,
    min_heap,
    ntp_sync,
    CASE
        WHEN time > NOW() - INTERVAL '5 minutes' THEN 'online'
        WHEN time > NOW() - INTERVAL '30 minutes' THEN 'warning'
        ELSE 'offline'
    END AS health_status
FROM 
    device_heartbeats
ORDER BY 
    device_mac_addr, 
    time DESC;

-- Vue pour les statistiques semi-horaires des capteurs
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_data_semi_hourly
WITH (timescaledb.continuous) AS
SELECT
    device_mac_addr,
    time_bucket('30 minutes', time) AS bucket_start,
    time_bucket('30 minutes', time) + INTERVAL '30 minutes' AS bucket_end,
    COUNT(temperature) as measurement_count,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity
FROM 
    sensor_data
GROUP BY 
    device_mac_addr, 
    bucket_start
ORDER BY 
    bucket_start DESC, 
    device_mac_addr;

-- Politique de rafraîchissement pour l'agrégation semi-horaire
SELECT add_continuous_aggregate_policy('sensor_data_semi_hourly',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '0',
    schedule_interval => INTERVAL '5 minutes');

-- Agrégation continue pour les moyennes horaires
CREATE MATERIALIZED VIEW IF NOT EXISTS sensor_data_hourly
WITH (timescaledb.continuous) AS
SELECT 
    device_mac_addr,
    time_bucket('1 hour', time) AS bucket_start,
    time_bucket('1 hour', time) + INTERVAL '1 hour' AS bucket_end,
    AVG(temperature) as avg_temperature,
    MIN(temperature) as min_temperature,
    MAX(temperature) as max_temperature,
    AVG(humidity) as avg_humidity,
    MIN(humidity) as min_humidity,
    MAX(humidity) as max_humidity,
    COUNT(*) as measurement_count
FROM 
    sensor_data
GROUP BY 
    device_mac_addr,
    bucket_start
ORDER BY 
    bucket_start DESC,
    device_mac_addr;

-- Politique de rafraîchissement pour l'agrégation horaire
SELECT add_continuous_aggregate_policy('sensor_data_hourly',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '0',
    schedule_interval => INTERVAL '5 minutes');

-- =============================================================================
-- PERMISSIONS POUR LES VUES MATÉRIALISÉES
-- =============================================================================

-- Permissions pour Grafana sur les vues matérialisées
GRANT SELECT ON sensor_data_semi_hourly, sensor_data_hourly TO grafana_reader;

-- Permissions pour Grafana sur les vues standards
GRANT SELECT ON latest_sensor_readings, device_health TO grafana_reader;

-- =============================================================================
-- MESSAGES DE CONFIRMATION
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'DATAYOTI - VUES CRÉÉES AVEC SUCCÈS';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'Vues standards:';
    RAISE NOTICE '  ✓ latest_sensor_readings - Dernières mesures de chaque capteur';
    RAISE NOTICE '  ✓ device_health - Statut et santé des capteurs (online/warning/offline)';
    RAISE NOTICE '';
    RAISE NOTICE 'Agrégations continues TimescaleDB:';
    RAISE NOTICE '  ✓ sensor_data_semi_hourly - Statistiques par tranches de 30 minutes (bucket_start + bucket_end)';
    RAISE NOTICE '  ✓ sensor_data_hourly - Moyennes et extrêmes horaires (bucket_start + bucket_end)';
    RAISE NOTICE '';
    RAISE NOTICE 'Configuration automatique:';
    RAISE NOTICE '  🔄 Rafraîchissement des agrégations: toutes les 5 minutes';
    RAISE NOTICE '  📊 Rétention des agrégations: 7 jours en arrière';
    RAISE NOTICE '  🔐 Permissions Grafana accordées sur toutes les vues';
    RAISE NOTICE '  🕐 Toutes les vues utilisent UTC';
    RAISE NOTICE '';
    RAISE NOTICE 'Pour ajouter des vues, modifiez ce fichier et relancez-le.';
    RAISE NOTICE '=============================================================================';
END
$$;