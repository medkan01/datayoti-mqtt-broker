#!/usr/bin/env python3
"""
DATAYOTI - INGESTEUR MQTT VERS TIMESCALEDB
============================================
Ingesteur MQTT qui récupère les données des capteurs DataYoti
et les stocke directement dans TimescaleDB au lieu de fichiers CSV.

Basé sur le code original collect_data.py
"""

import json
import os
import time
import logging
import psycopg2
from datetime import datetime, timezone
from typing import Optional, Dict, Any
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion

# Configuration depuis les variables d'environnement
MQTT_HOST = os.getenv("MQTT_HOST")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")

# Configuration PostgreSQL/TimescaleDB
PG_HOST = os.getenv("PG_HOST")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER")
PG_PASSWORD = os.getenv("PG_PASSWORD")
PG_DATABASE = os.getenv("PG_DATABASE")

# Validation des variables d'environnement requises
required_vars = {
    "MQTT_HOST": MQTT_HOST,
    "MQTT_USER": MQTT_USER,
    "MQTT_PASSWORD": MQTT_PASSWORD,
    "PG_HOST": PG_HOST,
    "PG_USER": PG_USER,
    "PG_PASSWORD": PG_PASSWORD,
    "PG_DATABASE": PG_DATABASE
}

missing_vars = [var_name for var_name, var_value in required_vars.items() if not var_value]
if missing_vars:
    raise ValueError(f"Variables d'environnement manquantes : {', '.join(missing_vars)}")

# Topics MQTT à surveiller
TOPICS = [
    "datayoti/sensor/+/data",
    "datayoti/sensor/+/heartbeat",
]

# Configuration du logging
if os.path.exists('/app/logs'):
    # Mode production : logs dans fichier + console
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler('/app/logs/ingestor.log')
        ]
    )
else:
    # Mode développement : logs uniquement en console
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler()
        ]
    )
logger = logging.getLogger(__name__)

class DatabaseManager:
    """Gestionnaire de connexion à la base de données TimescaleDB"""
    
    def __init__(self):
        self.connection = None
        self.connect()
    
    def connect(self):
        """Établit la connexion à la base de données"""
        try:
            self.connection = psycopg2.connect(
                host=PG_HOST,
                port=PG_PORT,
                user=PG_USER,
                password=PG_PASSWORD,
                database=PG_DATABASE,
                connect_timeout=10
            )
            self.connection.autocommit = True
            logger.info(f"✅ Connecté à TimescaleDB : {PG_HOST}:{PG_PORT}/{PG_DATABASE}")
            
            # Test de la connexion
            with self.connection.cursor() as cursor:
                cursor.execute("SELECT version();")
                version = cursor.fetchone()
                logger.info(f"📊 Version PostgreSQL : {version[0]}")
                
        except Exception as e:
            logger.error(f"❌ Erreur de connexion à la base de données : {e}")
            raise
    
    def ensure_device_exists(self, device_id: str, site_id: str):
        """S'assure que le device et le site existent dans la base"""
        try:
            with self.connection.cursor() as cursor:
                # Vérifier/créer le site
                cursor.execute(
                    "INSERT INTO sites (site_id, site_name) VALUES (%s, %s) ON CONFLICT (site_id) DO NOTHING",
                    (site_id, f"Site {site_id}")
                )
                
                # Vérifier/créer le device
                cursor.execute(
                    "INSERT INTO devices (device_id, site_id, device_name) VALUES (%s, %s, %s) ON CONFLICT (device_id) DO NOTHING",
                    (device_id, site_id, f"Capteur {device_id}")
                )
                
        except Exception as e:
            logger.error(f"❌ Erreur lors de la création device/site : {e}")
            raise
    
    def insert_sensor_data(self, device_id: str, temperature: float, 
                          humidity: float, sensor_timestamp: str):
        """Insert les données de capteur dans la table sensor_data"""
        try:
            # S'assurer que le device existe (récupération automatique du site_id)
            site_id = self.get_device_site_id(device_id) or "UNKNOWN"
            self.ensure_device_exists(device_id, site_id)
            
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO sensor_data (time, device_id, temperature, humidity, reception_time)
                    VALUES (%s, %s, %s, %s, NOW())
                    ON CONFLICT (device_id, time) DO UPDATE SET
                        temperature = EXCLUDED.temperature,
                        humidity = EXCLUDED.humidity,
                        reception_time = EXCLUDED.reception_time
                """, (sensor_timestamp, device_id, temperature, humidity))
                
                logger.info(f"✅ Données insérées pour {device_id} : T={temperature}°C, H={humidity}%")
                
        except Exception as e:
            logger.error(f"❌ Erreur insertion sensor_data : {e}")
            # Reconnection en cas d'erreur
            self.connect()
    
    def insert_heartbeat(self, device_id: str, site_id: str, 
                        rssi: int, free_heap: int, uptime: int, min_heap: int, 
                        ntp_sync: bool, timestamp: str):
        """Insert les données de heartbeat dans la table device_heartbeats"""
        try:
            # S'assurer que le device existe
            self.ensure_device_exists(device_id, site_id)
            
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO device_heartbeats (time, device_id, site_id, rssi, free_heap, uptime, min_heap, ntp_sync, reception_time)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
                    ON CONFLICT (device_id, time) DO UPDATE SET
                        site_id = EXCLUDED.site_id,
                        rssi = EXCLUDED.rssi,
                        free_heap = EXCLUDED.free_heap,
                        uptime = EXCLUDED.uptime,
                        min_heap = EXCLUDED.min_heap,
                        ntp_sync = EXCLUDED.ntp_sync,
                        reception_time = EXCLUDED.reception_time
                """, (timestamp, device_id, site_id, rssi, free_heap, uptime, min_heap, ntp_sync))
                
                logger.info(f"💓 Heartbeat inséré pour {device_id} : RSSI={rssi}dBm, Uptime={uptime}s, NTP={ntp_sync}")
                
        except Exception as e:
            logger.error(f"❌ Erreur insertion heartbeat : {e}")
            # Reconnection en cas d'erreur
            self.connect()

class MQTTIngestor:
    """Ingesteur MQTT principal"""
    
    def __init__(self):
        self.db = DatabaseManager()
        self.mqtt_client = None
        self.setup_mqtt()
    
    def setup_mqtt(self):
        """Configure le client MQTT"""
        self.mqtt_client = mqtt.Client(callback_api_version=CallbackAPIVersion.VERSION2)
        
        # Configuration des credentials si nécessaire
        if MQTT_USER and MQTT_PASSWORD:
            self.mqtt_client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
        
        # Configuration des callbacks
        self.mqtt_client.on_connect = self.on_connect
        self.mqtt_client.on_message = self.on_message
        self.mqtt_client.on_disconnect = self.on_disconnect
    
    def on_connect(self, client, userdata, flags, reason_code, properties):
        """Callback de connexion MQTT"""
        if reason_code == 0:
            logger.info("✅ Connecté au broker MQTT DataYoti")
            
            # S'abonner aux topics
            for topic in TOPICS:
                client.subscribe(topic)
                logger.info(f"📡 Abonné au topic : {topic}")
        else:
            logger.error(f"❌ Échec de la connexion MQTT, code : {reason_code}")
    
    def on_disconnect(self, client, userdata, reason_code, properties):
        """Callback de déconnexion MQTT"""
        logger.warning(f"⚠️ Déconnecté du broker MQTT, code : {reason_code}")
    
    def handle_data_message(self, payload: Dict[str, Any]):
        """Traite les messages de données des capteurs"""
        try:
            device_id = payload.get("device_id")
            temperature = payload.get("temperature")
            humidity = payload.get("humidity")
            sensor_timestamp = payload.get("timestamp")
            
            # Validation des données
            if not all([device_id, temperature is not None, humidity is not None, sensor_timestamp]):
                raise ValueError("Données manquantes dans le message data")
            
            # Conversion du timestamp
            if sensor_timestamp == "1970-01-01 01:00:02":
                # Timestamp invalide, utiliser le timestamp de réception UTC
                sensor_timestamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
            
            # Validation et normalisation du format ISO8601 UTC
            sensor_timestamp = self.normalize_timestamp_utc(sensor_timestamp)
            
            # Insertion en base (site_id récupéré automatiquement)
            self.db.insert_sensor_data(
                device_id=device_id,
                temperature=float(temperature),
                humidity=float(humidity),
                sensor_timestamp=sensor_timestamp
            )
            
        except Exception as e:
            logger.error(f"❌ Erreur traitement message data : {e}")
    
    def get_device_site_id(self, device_id: str) -> Optional[str]:
        """Récupère le site_id d'un device depuis la base de données"""
        try:
            with self.db.connection.cursor() as cursor:
                cursor.execute("SELECT site_id FROM devices WHERE device_id = %s", (device_id,))
                result = cursor.fetchone()
                return result[0] if result else None
        except Exception as e:
            logger.warning(f"⚠️ Impossible de récupérer le site_id pour {device_id}: {e}")
            return None
    
    def normalize_timestamp_utc(self, timestamp_str: str) -> str:
        """
        Normalise un timestamp au format ISO8601 UTC
        Accepte plusieurs formats et les convertit tous en UTC avec suffix Z
        """
        try:
            # Si déjà au bon format avec Z, retourner tel quel
            if timestamp_str.endswith('Z'):
                return timestamp_str
            
            # Si format avec +00:00, remplacer par Z
            if timestamp_str.endswith('+00:00'):
                return timestamp_str.replace('+00:00', 'Z')
            
            # Si pas de timezone, considérer comme UTC et ajouter Z
            if 'T' in timestamp_str and not any(tz in timestamp_str for tz in ['+', '-', 'Z']):
                return timestamp_str + 'Z'
            
            # Pour autres formats, essayer de parser et convertir en UTC
            try:
                # Essayer de parser le timestamp
                if '+' in timestamp_str or timestamp_str.endswith('Z'):
                    dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                else:
                    # Assumer UTC si pas de timezone
                    dt = datetime.fromisoformat(timestamp_str).replace(tzinfo=timezone.utc)
                
                # Convertir en UTC et formater
                dt_utc = dt.astimezone(timezone.utc)
                return dt_utc.isoformat().replace('+00:00', 'Z')
                
            except ValueError:
                logger.warning(f"⚠️ Format de timestamp non reconnu : {timestamp_str}")
                # Fallback : timestamp actuel UTC
                return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
                
        except Exception as e:
            logger.error(f"❌ Erreur normalisation timestamp : {e}")
            # Fallback : timestamp actuel UTC
            return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    
    def handle_heartbeat_message(self, payload: Dict[str, Any]):
        """Traite les messages de heartbeat des capteurs"""
        try:
            device_id = payload.get("device_id")
            site_id = payload.get("site_id", "UNKNOWN")
            rssi = payload.get("rssi")
            free_heap = payload.get("free_heap")
            uptime = payload.get("uptime")
            min_heap = payload.get("min_heap")
            ntp_sync = payload.get("ntp_sync", False)
            timestamp = payload.get("timestamp", datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'))
            
            # Validation des données
            if not device_id:
                raise ValueError("device_id manquant dans le heartbeat")
            
            # Normaliser le timestamp UTC
            timestamp = self.normalize_timestamp_utc(timestamp)
            
            # Insertion en base
            self.db.insert_heartbeat(
                device_id=device_id,
                site_id=site_id,
                rssi=rssi if rssi is not None else -999,
                free_heap=free_heap if free_heap is not None else 0,
                uptime=uptime if uptime is not None else 0,
                min_heap=min_heap if min_heap is not None else 0,
                ntp_sync=ntp_sync,
                timestamp=timestamp
            )
            
        except Exception as e:
            logger.error(f"❌ Erreur traitement heartbeat : {e}")
    
    def handle_status_message(self, payload: Dict[str, Any]):
        """Traite les messages de statut des capteurs"""
        try:
            device_id = payload.get("device_id")
            site_id = payload.get("site_id", "UNKNOWN")
            timestamp = payload.get("timestamp", datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'))
            
            # Validation des données
            if not device_id:
                raise ValueError("device_id manquant dans le message status")
            
            # Normaliser le timestamp UTC
            timestamp = self.normalize_timestamp_utc(timestamp)
        except Exception as e:
            logger.error(f"❌ Erreur traitement heartbeat : {e}")

    def on_message(self, client, userdata, message):
        """Traite tous les messages MQTT reçus"""
        try:
            # Décomposer le topic
            topic_parts = message.topic.split('/')
            
            if len(topic_parts) != 4 or topic_parts[0] != "datayoti" or topic_parts[1] != "sensor":
                logger.warning(f"⚠️ Topic non conforme ignoré : {message.topic}")
                return
            
            message_type = topic_parts[3]
            if message_type not in ["data", "heartbeat"]:
                logger.warning(f"⚠️ Type de message non supporté : {message_type}")
                return
            
            # Décodage du JSON
            try:
                payload = json.loads(message.payload.decode())
            except json.JSONDecodeError as e:
                logger.error(f"❌ Erreur de décodage JSON : {e}")
                return
            
            # Vérification de la cohérence du device_id
            topic_device_id = topic_parts[2]
            payload_device_id = payload.get("device_id")
            
            if payload_device_id != topic_device_id:
                logger.warning(f"⚠️ Incohérence device_id : topic={topic_device_id}, payload={payload_device_id}")
                return
            
            # Router vers la bonne fonction
            if message_type == "data":
                self.handle_data_message(payload)
            elif message_type == "heartbeat":
                self.handle_heartbeat_message(payload)
            else:
                logger.warning(f"⚠️ Type de message non supporté ignoré : {message_type}")
                
        except Exception as e:
            logger.error(f"❌ Erreur traitement message MQTT : {e}")
    
    def start(self):
        """Démarre l'ingesteur"""
        logger.info("🚀 DÉMARRAGE DE L'INGESTEUR DATAYOTI")
        logger.info("=" * 50)
        logger.info(f"📡 MQTT Broker: {MQTT_HOST}:{MQTT_PORT}")
        logger.info(f"👤 MQTT User: {MQTT_USER}")
        logger.info(f"🗄️  Database: {PG_HOST}:{PG_PORT}/{PG_DATABASE}")
        logger.info(f"👤 DB User: {PG_USER}")
        logger.info("=" * 50)
        
        try:
            # Connexion au broker MQTT
            logger.info("🔄 Connexion au broker MQTT...")
            self.mqtt_client.connect(MQTT_HOST, MQTT_PORT, 60)
            
            # Démarrage de la boucle MQTT
            logger.info("📊 Ingestion des données en cours... (Ctrl+C pour arrêter)")
            self.mqtt_client.loop_forever()
            
        except KeyboardInterrupt:
            logger.info("\n🛑 Arrêt de l'ingesteur demandé")
        except Exception as e:
            logger.error(f"❌ Erreur fatale : {e}")
            raise
        finally:
            if self.mqtt_client:
                self.mqtt_client.disconnect()
            if self.db.connection:
                self.db.connection.close()
            logger.info("👋 Ingesteur arrêté proprement")

def main():
    """Fonction principale"""
    # Attendre que la base soit prête (pour Docker)
    logger.info("⏳ Attente de la disponibilité de la base de données...")
    time.sleep(10)
    
    try:
        ingestor = MQTTIngestor()
        ingestor.start()
    except Exception as e:
        logger.error(f"❌ Erreur fatale lors du démarrage : {e}")
        exit(1)

if __name__ == "__main__":
    main()
