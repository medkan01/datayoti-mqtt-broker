# 💾 DataYoti Realtime

> **Du signal à l'action** - Infrastructure de monitoring temps réel sur Raspberry Pi

**DataYoti Realtime** est le cœur opérationnel du projet DataYoti. Cette infrastructure, déployée sur **Raspberry Pi**, collecte, stocke et visualise les données environnementales en temps réel, optimisée pour fonctionner efficacement sur des ressources limitées.

## 🎯 Place dans l'écosystème DataYoti

```
┌─────────────────────────────────────────┐
│  1️⃣  Capteurs ESP32 (DHT22)            │  → datayoti-firmware
│      ↓ MQTT                             │
│  2️⃣  Infrastructure temps réel          │  ← VOUS ÊTES ICI (🍓 Raspberry Pi)
│      ↓ Ingestion & monitoring           │
│  3️⃣  Data Warehouse + Analytics        │  → datayoti-warehouse
│      ↓ Dashboards & Conformité          │
│  4️⃣  Insights actionnables              │
└─────────────────────────────────────────┘
```

Ce composant assure :
- 📡 **Réception** des données MQTT des capteurs
- 💾 **Stockage** optimisé pour séries temporelles (TimescaleDB)
- 📊 **Visualisation** temps réel (Grafana)
- 🔗 **Source OLTP** pour l'entrepôt de données analytique
- 🍓 **Déploiement** optimisé pour Raspberry Pi

---

## 🏗️ Architecture

```
Capteurs ESP32 (DHT22) 
    ↓ MQTT topics
Eclipse Mosquitto (MQTT Broker) 🍓
    ↓ Subscribe & process
Ingestor Python 🍓
    ↓ Insert
TimescaleDB (PostgreSQL + time-series) 🍓
    ↓ Visualize
Grafana (Dashboards) 🍓

🍓 = Déployé sur Raspberry Pi
```

### Stack technique

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| **MQTT Broker** | Eclipse Mosquitto 2.0.18 | Réception messages IoT |
| **Ingestor** | Python 3.x | Transfert MQTT → DB |
| **Base de données** | TimescaleDB (PostgreSQL) | Stockage séries temporelles |
| **Visualisation** | Grafana | Dashboards temps réel |
| **Orchestration** | Docker Compose | Infrastructure as Code |
| **Plateforme** | 🍓 Raspberry Pi | Déploiement edge computing |


---

## � Fonctionnalités clés

### Collecte et traçabilité

- 📡 **Topics MQTT** :
  - `datayoti/sensor/{device_mac}/data` : Température et humidité
  - `datayoti/sensor/{device_mac}/heartbeat` : Santé des capteurs
  - `datayoti/sensor/{device_mac}/status` : État online/offline

### Stockage optimisé

- 🗄️ **Tables TimescaleDB** :
  - `sensor_data` : Mesures environnementales (hypertable)
  - `device_heartbeats` : Monitoring santé capteurs (hypertable)
  - `devices` : Référentiel des capteurs
  - `sites` : Organisation par site

- 📊 **Vues matérialisées** :
  - `sensor_data_hourly` : Agrégations horaires
  - `latest_sensor_readings` : Dernières valeurs
  - `device_health` : Statut temps réel (online/warning/offline)

### Performance

- ⚡ **Cache intelligent** : Devices en cache (TTL: 5 min)
- 📦 **Partitionnement temporel** : Chunks de 1 jour
- 🔄 **Rétention automatique** : 1 an données capteurs, 6 mois heartbeats
- � **Optimisé Raspberry Pi** : Configuration mémoire adaptée (100MB shared_buffers, 1 CPU)
- ⚙️ **Ressources limitées** : Fonctionne avec 2 GB RAM

---

## 🚀 Installation rapide

### Prérequis

- **Raspberry Pi** 3B+ ou supérieur (4 GB RAM recommandé)
- **Raspberry Pi OS** (64-bit recommandé)
- **Docker** 20.10+ et **Docker Compose** 2.0+
- 2 GB RAM minimum (4 GB recommandé)
- 16 GB carte SD minimum (32 GB recommandé)
- Capteurs ESP32 configurés (voir [datayoti-firmware](../datayoti-firmware))

### Installation sur Raspberry Pi

```bash
# Sur votre Raspberry Pi

# 1. Cloner le projet
git clone https://github.com/medkan01/datayoti-realtime.git
cd datayoti-realtime

# 2. Configurer l'environnement
cp .env.example .env
# Éditer .env avec vos mots de passe

# 3. Démarrer l'infrastructure
docker-compose up -d

# 4. Créer les vues (première fois)
./manage_views.sh create           # Sur Raspberry Pi (Linux)
# ou .\manage_views.ps1 -Action create  # Si Windows
```

**Note** : L'infrastructure est accessible sur le réseau local via l'IP du Raspberry Pi.

### Configuration minimale (.env)

```bash
# Base de données
PG_USER=postgres
PG_PASSWORD=VotreMotDePasseSecurise123!
PG_DATABASE=datayoti_db

# MQTT
MQTT_USER=datayoti_monitor
MQTT_PASSWORD=VotreMotDePasseMQTT123!

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=VotreMotDePasseGrafana123!
```

### Vérification

```bash
# Statut des services
docker-compose ps

# Logs de l'ingestor
docker-compose logs -f ingestor

# Test connexion DB
docker exec -it timescale_db psql -U postgres -d datayoti_db
```

---

## 📊 Utilisation

### Ports exposés

| Service | Port | Usage |
|---------|------|-------|
| **Mosquitto** | 1883 | MQTT standard |
| **TimescaleDB** | 5432 | PostgreSQL |
| **Grafana** | 3000 | Interface web |

### Accès Grafana

1. Ouvrir **http://<IP_RASPBERRY_PI>:3000** depuis n'importe quel appareil sur le réseau local
2. Se connecter avec les identifiants `.env`
3. Configurer la source de données PostgreSQL :
   - Host : `postgres:5432`
   - Database : `datayoti_db`
   - User : `grafana_reader`
   - Password : Depuis `GRAFANA_READER_PASSWORD`

**Astuce** : Trouvez l'IP du Raspberry Pi avec `hostname -I`

### Gestion des vues

```bash
# Sur Raspberry Pi (Linux/Bash)
./manage_views.sh create
./manage_views.sh recreate
./manage_views.sh drop

# Windows PowerShell (si applicable)
.\manage_views.ps1 -Action create
.\manage_views.ps1 -Action recreate
.\manage_views.ps1 -Action drop
```

### Requêtes utiles

```sql
-- Dernières mesures de tous les capteurs
SELECT * FROM latest_sensor_readings;

-- Statut santé des capteurs
SELECT * FROM device_health;

-- Statistiques horaires des dernières 24h
SELECT * FROM sensor_data_hourly 
WHERE bucket_start > NOW() - INTERVAL '24 hours'
ORDER BY bucket_start DESC;
```

---

## 🔐 Sécurité

### Approche multi-couches

1. **Isolation réseau** : Services dans le réseau Docker `mqtt-network`
2. **Authentification MQTT** : Obligatoire pour tous les clients
3. **Utilisateurs DB dédiés** :
   - `mqtt_ingestor` : Droits écriture limités
   - `grafana_reader` : Lecture seule
4. **Variables d'environnement** : Mots de passe dans `.env` (non versionné)

### Bonnes pratiques

- ⚠️ **Ne jamais commiter `.env`**
- 🔒 Mots de passe forts (20+ caractères)
- 🔄 Changer les mots de passe par défaut
- 🚫 Ne pas exposer les ports sans TLS en production
- 📝 Consulter les logs régulièrement

---

## 🛠️ Maintenance

### Commandes essentielles

```bash
# Arrêter les services
docker-compose down

# Redémarrer un service
docker-compose restart ingestor

# Logs en temps réel
docker-compose logs -f

# Backup base de données
docker exec timescale_db pg_dump -U postgres datayoti_db > backup_$(date +%Y%m%d).sql

# Restaurer depuis backup
docker exec -i timescale_db psql -U postgres -d datayoti_db < backup_20251103.sql
```

### Monitoring système

```sql
-- Nombre de mesures par device
SELECT device_id, COUNT(*) as nb_measurements
FROM sensor_data
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY device_id;

-- Espace disque utilisé
SELECT 
    pg_size_pretty(pg_database_size('datayoti_db')) as db_size,
    pg_size_pretty(pg_total_relation_size('sensor_data')) as sensor_data_size;
```

---

## � Structure du projet

```
datayoti-realtime/
├── docker-compose.yml           # Orchestration services
├── .env.example                 # Template configuration
├── manage_views.sh              # Gestion vues (Linux/Raspberry Pi)
├── manage_views.ps1             # Gestion vues (Windows)
├── db/
│   ├── Dockerfile               # Image TimescaleDB
│   └── init/
│       ├── 01_init_timescale.sql     # Schéma DB
│       ├── 02_update_passwords.sh    # Sécurisation
│       └── 03_create_views.sql       # Vues matérialisées
├── ingestor/
│   ├── app.py                   # Application Python
│   ├── Dockerfile
│   └── requirements.txt
└── mosquitto/
    ├── config/
    │   └── mosquitto.conf       # Configuration MQTT
    ├── data/                    # Persistance
    ├── log/                     # Logs
    └── passwords/               # Authentification
```

---

## 🐛 Dépannage

### Services ne démarrent pas

```bash
# Vérifier les logs
docker-compose logs

# Vérifier l'espace disque
docker system df

# Nettoyer les ressources
docker system prune -a
```

### Ingestor ne reçoit pas de messages

- Vérifier que Mosquitto fonctionne : `docker-compose logs mosquitto`
- Tester avec : `mosquitto_sub -h localhost -t datayoti/# -v -u datayoti_monitor -P <password>`
- Vérifier les credentials MQTT dans `.env`
- Vérifier que les capteurs ESP32 pointent vers l'IP correcte du Raspberry Pi

### Grafana ne se connecte pas à la DB

- Vérifier que TimescaleDB fonctionne : `docker-compose ps`
- Tester la connexion : `docker exec timescale_db pg_isready`
- Vérifier le user `grafana_reader` et ses droits

### Performance Raspberry Pi

```bash
# Vérifier l'utilisation des ressources
docker stats

# Vérifier la température du CPU
vcgencmd measure_temp

# Libérer de l'espace
docker system prune -a
```

---

## 📚 Ressources

- 📖 [Documentation TimescaleDB](https://docs.timescale.com/)
- 📖 [Documentation Mosquitto](https://mosquitto.org/documentation/)
- 📖 [Documentation Grafana](https://grafana.com/docs/)
- � [Docker sur Raspberry Pi](https://docs.docker.com/engine/install/raspberry-pi-os/)
- �🔗 [Firmware ESP32](../datayoti-firmware) - Capteurs IoT
- 🔗 [Data Warehouse](../datayoti-warehouse) - Plateforme d'analyse

---

## 📄 Licence

Ce projet est sous licence MIT. Voir [LICENSE](LICENSE) pour plus de détails.

---

## 👨‍� Contact

- **LinkedIn** : [Mehdi Akniou](https://linkedin.com/in/mehdi-akniou)
- **Email** : contact@mehdi-akniou.com
- **GitHub** : [@medkan01](https://github.com/medkan01)

---

**DataYoti Realtime** - Du signal à l'action 💾

*Infrastructure de monitoring temps réel optimisée pour Raspberry Pi*