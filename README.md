# DataYoti MQTT Broker

Système de collecte et stockage de données IoT basé sur MQTT et TimescaleDB.

## Architecture

- **MQTT Broker** : Eclipse Mosquitto
- **Base de données** : TimescaleDB (PostgreSQL avec extension TimescaleDB)
- **Ingestor** : Service Python qui transfère les données de MQTT vers TimescaleDB
- **Visualisation** : Grafana

## Installation

### Prérequis

- Docker et Docker Compose
- Fichier `.env` configuré (voir `.env.example`)

### Configuration

1. **Créez votre fichier `.env`** :
   ```bash
   cp .env.example .env
   ```

2. **Modifiez les variables d'environnement** :
   - Changez tous les mots de passe par défaut
   - Configurez les autres paramètres selon vos besoins

### Démarrage

```bash
docker-compose up -d
```

## Sécurité

Ce projet utilise une approche en couches pour sécuriser les accès :

1. **Variables d'environnement** :
   - Tous les mots de passe sont stockés dans un fichier `.env` non versionné
   - Les variables sont injectées dans les conteneurs via docker-compose

2. **Automatisation de la configuration des mots de passe** :
   - Script d'initialisation de la base de données avec des mots de passe temporaires
   - Script de mise à jour qui remplace les mots de passe temporaires par ceux définis dans `.env`

3. **Authentification MQTT** :
   - Fichier de mots de passe MQTT généré à partir des variables d'environnement
   - Authentification requise pour tous les clients

## Utilisation

- **MQTT Broker** : Accessible sur le port 1883 (MQTT) et 9001 (WebSockets)
- **TimescaleDB** : Accessible sur le port 5432
- **Grafana** : Accessible sur http://localhost:3000

## Contribuer

1. Clonez le dépôt
2. Créez votre fichier `.env` à partir de `.env.example`
3. Apportez vos modifications
4. Soumettez une pull request

## Remarque de sécurité

Ne jamais commiter le fichier `.env` ou tout autre fichier contenant des informations sensibles !