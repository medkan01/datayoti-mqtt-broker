# DataYoti - Mise à jour Base de Données et Ingestion

Ce document décrit les mises à jour apportées au système DataYoti pour supporter les nouvelles fonctionnalités du firmware ESP32.

## 🔄 Changements apportés

### 1. Firmware ESP32 mis à jour
Le firmware ESP32 envoie maintenant des données enrichies :

**Messages de données** (`datayoti/sensor/{device_id}/data`) :
```json
{
  "device_id": "1C:69:20:E9:18:24",
  "timestamp": "2025-10-04T14:30:45",
  "temperature": 22.5,
  "humidity": 65.3
}
```

**Messages de heartbeat** (`datayoti/sensor/{device_id}/heartbeat`) :
```json
{
  "device_id": "1C:69:20:E9:18:24",
  "site_id": "SITE_001",
  "timestamp": "2025-10-04T14:30:45",
  "rssi": -45,
  "free_heap": 185432,
  "uptime": 3600,
  "min_heap": 180000,
  "ntp_sync": true
}
```

### 2. Schéma de base de données mis à jour

#### Nouvelles colonnes dans `device_heartbeats` :
- `uptime` (INTEGER) : Temps de fonctionnement en secondes
- `min_heap` (INTEGER) : Mémoire libre minimale atteinte
- `ntp_sync` (BOOLEAN) : Statut de synchronisation NTP

#### Séparation des vues :
- **Script principal** (`01_init_timescale.sql`) : Tables, index, agrégations continues
- **Script des vues** (`03_create_views.sql`) : Toutes les vues d'analyse

### 3. Script d'ingestion Python mis à jour

#### Nouvelles fonctionnalités :
- Support des nouveaux champs de heartbeat
- Récupération automatique du `site_id` depuis la base de données
- Logging amélioré avec les nouvelles informations

#### Gestion améliorée des données :
- Les messages de données ne contiennent plus `site_id` (récupéré automatiquement)
- Validation renforcée des données reçues
- Gestion des erreurs améliorée

## 📁 Nouveaux fichiers

### Scripts de gestion des vues
- `manage_views.sh` : Script Bash pour gérer les vues
- `manage_views.ps1` : Script PowerShell pour Windows
- `db/init/03_create_views.sql` : Définition de toutes les vues

### Nouvelles vues créées

#### Vues de base :
- `latest_sensor_readings` : Dernières mesures de chaque capteur
- `device_health` : Santé des capteurs avec nouveaux champs
- `daily_sensor_stats` : Statistiques quotidiennes

#### Vues de monitoring système :
- `device_memory_stats` : Statistiques mémoire avec alertes
- `device_signal_quality` : Qualité du signal WiFi

#### Vues d'analyse avancée :
- `hourly_sensor_stats_24h` : Statistiques horaires des dernières 24h
- `temperature_trends_by_site` : Tendances de température par site
- `inactive_devices` : Détection des capteurs inactifs
- `temperature_anomalies` : Détection d'anomalies de température

#### Vues interface utilisateur :
- `dashboard_overview` : Vue d'ensemble complète pour tableau de bord
- `export_last_24h` : Export des données des dernières 24h

## � Gestion UTC des timestamps

### Configuration UTC complète
Le système DataYoti est maintenant entièrement configuré pour UTC :

#### 1. Firmware ESP32 ✅
- Utilise `gmtime()` pour générer des timestamps UTC
- Format ISO8601 avec suffix 'Z' : `2025-10-04T14:30:45.000Z`
- Synchronisation NTP pour maintenir la précision

#### 2. Base de données PostgreSQL ✅
- `timezone = 'UTC'` configuré au niveau base
- Toutes les colonnes en `TIMESTAMP WITH TIME ZONE`
- `NOW()` retourne l'heure UTC

#### 3. Script d'ingestion Python ✅
- `datetime.now(timezone.utc)` pour les timestamps de fallback
- Normalisation automatique des formats de timestamp
- Validation et conversion vers UTC systématique

#### 4. Docker containers ✅
- Variable `TZ=UTC` pour tous les conteneurs
- `PGTZ=UTC` spécifique pour PostgreSQL

### Vérification UTC

#### Vérification automatique :
```powershell
# Vérification complète
.\check_utc.ps1 -Detailed

# Vérification avec correction automatique
.\check_utc.ps1 -Fix

# Vérification rapide
.\check_utc.ps1
```

#### Vérification manuelle en base :
```sql
-- Vérifier la configuration
SELECT current_setting('timezone');

-- Vérifier les données récentes
SELECT 
    device_id,
    time,
    reception_time,
    EXTRACT(TIMEZONE FROM time) as tz_offset
FROM sensor_data 
ORDER BY reception_time DESC 
LIMIT 5;
```

### Formats de timestamp supportés

Le script d'ingestion accepte et normalise automatiquement :
- `2025-10-04T14:30:45Z` ✅ (préféré)
- `2025-10-04T14:30:45+00:00` ✅ (converti vers Z)
- `2025-10-04T14:30:45` ✅ (assumé UTC, Z ajouté)
- Autres formats ISO8601 ✅ (convertis vers UTC)

### Détection d'anomalies temporelles

Le système détecte automatiquement :
- **Temps rétrograde** : `gap_seconds < 0`
- **Gros écarts** : `gap_seconds > 2h`
- **Problèmes de synchronisation NTP** : `ntp_sync = false`

## �🚀 Migration et déploiement

### 1. Arrêter le système actuel
```bash
docker-compose down
```

### 2. Sauvegarder la base de données (optionnel)
```bash
docker-compose up -d db
docker exec datayoti-db pg_dump -U postgres datayoti_db > backup_$(date +%Y%m%d_%H%M%S).sql
docker-compose down
```

### 3. Relancer le système
```bash
docker-compose up -d
```

### 4. Créer les vues (si nécessaire)
```bash
# Linux/Mac
./manage_views.sh create

# Windows PowerShell
.\manage_views.ps1 -Action create
```

## 🔧 Gestion des vues

### Commandes disponibles

#### Linux/Mac (Bash)
```bash
./manage_views.sh create     # Créer toutes les vues
./manage_views.sh drop       # Supprimer toutes les vues
./manage_views.sh recreate   # Recréer toutes les vues
./manage_views.sh list       # Lister les vues existantes
```

#### Windows (PowerShell)
```powershell
.\manage_views.ps1 -Action create     # Créer toutes les vues
.\manage_views.ps1 -Action drop       # Supprimer toutes les vues
.\manage_views.ps1 -Action recreate   # Recréer toutes les vues
.\manage_views.ps1 -Action list       # Lister les vues existantes
```

### Ajouter une nouvelle vue

1. Éditer le fichier `db/init/03_create_views.sql`
2. Ajouter votre nouvelle vue
3. Exécuter : `./manage_views.sh recreate`

### Exemple d'ajout de vue :
```sql
-- Nouvelle vue pour les alertes de température
CREATE OR REPLACE VIEW temperature_alerts AS
SELECT 
    device_id,
    site_id,
    time,
    temperature,
    CASE 
        WHEN temperature > 30 THEN 'high'
        WHEN temperature < 10 THEN 'low'
        ELSE 'normal'
    END as alert_level
FROM sensor_data
WHERE time > NOW() - INTERVAL '1 hour'
    AND (temperature > 30 OR temperature < 10)
ORDER BY time DESC;
```

## 📊 Nouvelles métriques disponibles

### Monitoring système :
- **Uptime** : Temps de fonctionnement des capteurs
- **Mémoire minimale** : Détection des problèmes de mémoire
- **Synchronisation NTP** : Fiabilité des timestamps
- **Qualité du signal** : Évaluation de la connectivité

### Alertes automatiques :
- Capteurs inactifs (pas de données depuis 30 min)
- Mémoire critique (< 10KB libre)
- Signal faible (< -80 dBm)
- Anomalies de température (écart-type > 2.5)

## 🔍 Requêtes utiles

### Vérifier l'état général des capteurs :
```sql
SELECT * FROM dashboard_overview;
```

### Surveiller la mémoire :
```sql
SELECT * FROM device_memory_stats WHERE memory_status != 'ok';
```

### Détecter les anomalies :
```sql
SELECT * FROM temperature_anomalies WHERE z_score > 3;
```

### Export des données :
```sql
SELECT * FROM export_last_24h;
```

## ⚠️ Points d'attention

1. **Compatibilité** : Les anciens firmwares peuvent ne pas envoyer tous les nouveaux champs
2. **Migration** : Les vues sont recréées à chaque redémarrage si le fichier est modifié
3. **Performances** : Les nouvelles vues d'analyse peuvent être coûteuses sur de gros volumes
4. **Monitoring** : Surveillez les logs de l'ingesteur pour les erreurs de traitement

## 📝 Recommandations

### Bonne pratique pour les vues :
✅ **Recommandé** : Fichier séparé pour les vues (implémenté)
- Facilite les modifications
- Permet les tests indépendants
- Évite les redéploiements complets

### Alternative non recommandée :
❌ **Éviter** : Vues dans le script d'initialisation
- Modifications complexes
- Risque de perte de données lors des tests
- Redéploiement complet nécessaire

### Pour l'avenir :
- Considérer un système de migrations versionnées
- Implémenter des tests automatisés pour les vues
- Documenter les performances des requêtes complexes

## 🆘 Dépannage

### Problème : Vues manquantes après redémarrage
```bash
./manage_views.sh create
```

### Problème : Erreur dans une vue
```bash
./manage_views.sh recreate
```

### Problème : Données heartbeat incomplètes
Vérifier les logs de l'ingesteur :
```bash
docker-compose logs ingestor
```

### Problème : Performance dégradée
Analyser les requêtes lentes :
```sql
SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;
```