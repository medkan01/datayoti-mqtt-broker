# DataYoti MQTT Broker

## 📋 Vue d'ensemble

**DataYoti MQTT Broker** est une infrastructure complète de collecte, stockage et visualisation de données IoT pour capteurs de température et d'humidité. Le système est conçu pour être déployé sur des environnements à ressources limitées comme le Raspberry Pi, tout en offrant des capacités d'analyse avancées grâce à TimescaleDB.

### Architecture

```
Capteurs ESP32 (DHT22) 
    ↓ MQTT (datayoti/sensor/+/data)
Eclipse Mosquitto (MQTT Broker)
    ↓
Ingestor Python
    ↓
TimescaleDB (PostgreSQL + extension temps-réel)
    ↓
Grafana (Visualisation)
```

### Composants principaux

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| **MQTT Broker** | Eclipse Mosquitto 2.0.18 | Réception des messages des capteurs IoT |
| **Base de données** | TimescaleDB | Stockage optimisé pour séries temporelles |
| **Ingestor** | Python 3 + paho-mqtt + psycopg2 | Transfert MQTT → TimescaleDB |
| **Visualisation** | Grafana | Dashboards et alertes en temps réel |

## 🎯 Fonctionnalités

### Collecte de données

- **Topics MQTT** :
  - `datayoti/sensor/{device_mac_addr}/data` : Données de température/humidité
  - `datayoti/sensor/{device_mac_addr}/heartbeat` : Statut de santé des capteurs

- **Format des données** :
  ```json
  {
    "device_id": "1C:69:20:E9:18:24",
    "temperature": 22.5,
    "humidity": 65.3,
    "timestamp": "2025-11-03T14:30:00Z"
  }
  ```

### Base de données

- **Tables principales** :
  - `sensor_data` : Mesures de température et humidité (hypertable)
  - `device_heartbeats` : Monitoring de la santé des capteurs (hypertable)
  - `devices` : Référentiel des capteurs (MAC address)
  - `sites` : Organisation par site d'installation

- **Vues matérialisées** :
  - `sensor_data_semi_hourly` : Agrégations par tranches de 30 minutes
  - `sensor_data_hourly` : Statistiques horaires
  - `latest_sensor_readings` : Dernières valeurs par capteur
  - `device_health` : Statut en temps réel (online/warning/offline)

### Optimisations

- **Cache intelligent** : Les devices sont mis en cache (TTL: 5 min) pour réduire les requêtes DB
- **Partitionnement temporel** : Chunks de 1 jour pour performances optimales
- **Rétention automatique** : 
  - Données capteurs : 1 an
  - Heartbeats : 6 mois
- **Configuration Raspberry Pi** : Paramètres mémoire adaptés (100MB, 1 CPU)
- **Timezone UTC** : Tous les timestamps sont en UTC pour éviter les problèmes de fuseau horaire

## 🚀 Installation

### Prérequis

- Docker 20.10+
- Docker Compose 2.0+
- 2 GB RAM minimum (recommandé : 4 GB)
- 10 GB espace disque

### Configuration rapide

1. **Clonez le dépôt** :
   ```bash
   git clone https://github.com/medkan01/datayoti-mqtt-broker.git
   cd datayoti-mqtt-broker
   ```

2. **Créez le fichier `.env`** :
   ```bash
   cp .env.example .env
   ```

3. **Configurez les mots de passe** dans `.env` :
   ```env
   # Base de données PostgreSQL/TimescaleDB
   PG_USER=postgres
   PG_PASSWORD=votre_mot_de_passe_postgres
   PG_DATABASE=datayoti_db

   # Utilisateurs de base de données
   MQTT_INGESTOR_PASSWORD=votre_mot_de_passe_ingestor
   GRAFANA_READER_PASSWORD=votre_mot_de_passe_grafana

   # MQTT
   MQTT_USER=datayoti_monitor
   MQTT_PASSWORD=votre_mot_de_passe_mqtt

   # Grafana
   GF_SECURITY_ADMIN_USER=admin
   GF_SECURITY_ADMIN_PASSWORD=votre_mot_de_passe_admin
   ```

4. **Démarrez l'infrastructure** :
   ```bash
   docker-compose up -d
   ```

5. **Créez les vues** (première fois uniquement) :
   ```powershell
   .\manage_views.ps1 -Action create
   ```

### Vérification

```bash
# Vérifier les conteneurs
docker-compose ps

# Logs de l'ingestor
docker-compose logs -f ingestor

# Se connecter à la base de données
docker exec -it timescale_db psql -U postgres -d datayoti_db
```

## 📊 Utilisation

### Ports exposés

| Service | Port | Usage |
|---------|------|-------|
| Mosquitto | 1883 | MQTT standard |
| Mosquitto | 8883 | MQTT over TLS |
| Mosquitto | 9001 | MQTT WebSockets |
| TimescaleDB | 5432 | PostgreSQL |
| Grafana | 3000 | Interface web |

### Configuration des capteurs ESP32

Les capteurs doivent publier sur les topics :
```
datayoti/sensor/{MAC_ADDRESS}/data
datayoti/sensor/{MAC_ADDRESS}/heartbeat
```

Exemple de configuration pour ESP32 :
```cpp
const char* mqtt_server = "votre_ip_raspberry";
const int mqtt_port = 1883;
const char* mqtt_user = "datayoti_monitor";
const char* mqtt_password = "votre_mot_de_passe";
```

### Accès Grafana

1. Ouvrez http://localhost:3000
2. Connectez-vous avec les identifiants définis dans `.env`
3. Configurez la source de données PostgreSQL :
   - Host : `postgres:5432`
   - Database : `datayoti_db`
   - User : `grafana_reader`
   - Password : Celui défini dans `GRAFANA_READER_PASSWORD`

### Gestion des vues

Le script `manage_views.ps1` permet de gérer les vues matérialisées :

```powershell
# Créer toutes les vues
.\manage_views.ps1 -Action create

# Recréer les vues (suppression + création)
.\manage_views.ps1 -Action recreate

# Supprimer toutes les vues
.\manage_views.ps1 -Action drop
```

## 🔐 Sécurité

### Approche multi-couches

1. **Isolation réseau** : Tous les services communiquent via le réseau Docker `mqtt-network`
2. **Authentification MQTT** : Obligatoire pour tous les clients
3. **Utilisateurs DB dédiés** :
   - `mqtt_ingestor` : Droits d'écriture limités
   - `grafana_reader` : Lecture seule
4. **Variables d'environnement** : Mots de passe stockés dans `.env` (non versionné)
5. **Mots de passe temporaires** : Remplacés automatiquement au démarrage

### Bonnes pratiques

- ⚠️ **Ne jamais commiter le fichier `.env`**
- 🔒 Utilisez des mots de passe forts (20+ caractères)
- 🔄 Changez les mots de passe par défaut
- 🚫 N'exposez pas les ports publiquement sans TLS
- 📝 Consultez les logs régulièrement

## 🛠️ Maintenance

### Commandes utiles

```bash
# Arrêter tous les services
docker-compose down

# Arrêter et supprimer les volumes (⚠️ perte de données)
docker-compose down -v

# Redémarrer un service
docker-compose restart ingestor

# Voir les logs en temps réel
docker-compose logs -f

# Backup de la base de données
docker exec timescale_db pg_dump -U postgres datayoti_db > backup_$(date +%Y%m%d).sql
```

### Monitoring

```sql
-- Dernières mesures
SELECT * FROM latest_sensor_readings;

-- Statut des capteurs
SELECT * FROM device_health;

-- Statistiques semi-horaires
SELECT * FROM sensor_data_semi_hourly 
WHERE bucket_start > NOW() - INTERVAL '24 hours';
```

## 📚 Structure du projet

```
datayoti-mqtt-broker/
├── docker-compose.yml          # Orchestration des services
├── .env                         # Configuration (non versionné)
├── manage_views.ps1            # Gestion des vues matérialisées
├── db/
│   ├── Dockerfile              # Image TimescaleDB personnalisée
│   └── init/
│       ├── 01_init_timescale.sql    # Schéma de la base
│       ├── 02_update_passwords.sh   # Sécurisation des comptes
│       └── 03_create_views.sql      # Création des vues
├── ingestor/
│   ├── app.py                  # Application d'ingestion
│   ├── Dockerfile
│   └── requirements.txt
└── mosquitto/
    ├── config/
    │   └── mosquitto.conf      # Configuration MQTT
    ├── data/                    # Persistance MQTT
    ├── log/                     # Logs MQTT
    └── passwords/               # Authentification MQTT
```

## 🤝 Contribution

Les contributions sont les bienvenues ! 

1. Forkez le projet
2. Créez une branche (`git checkout -b feature/amelioration`)
3. Committez vos changements (`git commit -am 'Ajout d'une fonctionnalité'`)
4. Pushez vers la branche (`git push origin feature/amelioration`)
5. Ouvrez une Pull Request

## 📄 Licence

Ce projet est distribué sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.

## 🐛 Support

- **Issues** : https://github.com/medkan01/datayoti-mqtt-broker/issues
- **Discussions** : https://github.com/medkan01/datayoti-mqtt-broker/discussions

## 🙏 Remerciements

- TimescaleDB pour l'extension PostgreSQL
- Eclipse Foundation pour Mosquitto
- Grafana Labs pour l'outil de visualisation