FROM timescale/timescaledb:latest-pg16

# Copie des scripts d'initialisation
COPY ./init/ /docker-entrypoint-initdb.d/

# Rendre le script de mise à jour des mots de passe exécutable
RUN chmod +x /docker-entrypoint-initdb.d/02_update_passwords.sh

# Note: Les variables d'environnement comme POSTGRES_PASSWORD,
# MQTT_INGESTOR_PASSWORD, etc. seront fournies par docker-compose