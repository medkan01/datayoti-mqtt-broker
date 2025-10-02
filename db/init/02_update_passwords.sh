#!/bin/bash
# =============================================================================
# DATAYOTI - MISE À JOUR DES MOTS DE PASSE DEPUIS LES VARIABLES D'ENVIRONNEMENT
# =============================================================================
# Ce script met à jour les mots de passe des utilisateurs créés dans 01_init_timescale.sql
# en utilisant les variables d'environnement définies dans docker-compose.yml
# =============================================================================

set -e

echo "🔐 Mise à jour des mots de passe depuis les variables d'environnement..."

# Vérifie les variables obligatoires
if [ -z "$MQTT_INGESTOR_PASSWORD" ] || [ -z "$GRAFANA_READER_PASSWORD" ]; then
    echo "⛔ ERREUR: Variables d'environnement manquantes!"
    echo "MQTT_INGESTOR_PASSWORD et/ou GRAFANA_READER_PASSWORD ne sont pas définies"
    echo "Ces variables doivent être définies dans votre fichier .env"
    echo "Utilisez .env.example comme modèle"
    exit 1
fi

# Mise à jour des mots de passe
echo "🔑 Configuration des mots de passe des utilisateurs de la base de données..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Mise à jour des mots de passe avec les variables d'environnement
    ALTER ROLE mqtt_ingestor PASSWORD '${MQTT_INGESTOR_PASSWORD}';
    ALTER ROLE grafana_reader PASSWORD '${GRAFANA_READER_PASSWORD}';
    
    -- Message de confirmation
    \echo '✅ Mots de passe mis à jour avec succès';
EOSQL

echo "🎉 Configuration de sécurité terminée !"