#!/bin/bash
# =============================================================================
# DATAYOTI - SCRIPT DE GESTION DES VUES
# =============================================================================
# Ce script permet de gérer les vues de base de données de manière indépendante
# 
# Usage:
#   ./manage_views.sh create    # Créer toutes les vues
#   ./manage_views.sh drop      # Supprimer toutes les vues
#   ./manage_views.sh recreate  # Supprimer puis recréer toutes les vues
# =============================================================================

set -e

# Configuration
CONTAINER_NAME="datayoti-db"
DB_NAME="datayoti_db"
DB_USER="postgres"
VIEWS_FILE="/docker-entrypoint-initdb.d/03_create_views.sql"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages colorés
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fonction pour vérifier si le conteneur existe et est en cours d'exécution
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "Le conteneur $CONTAINER_NAME n'est pas en cours d'exécution"
        log_info "Assurez-vous que Docker Compose est démarré : docker-compose up -d"
        exit 1
    fi
}

# Fonction pour créer les vues
create_views() {
    log_info "Création des vues de base de données..."
    
    if docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$(dirname "$0")/db/init/03_create_views.sql"; then
        log_success "Vues créées avec succès"
    else
        log_error "Erreur lors de la création des vues"
        exit 1
    fi
}

# Fonction pour supprimer toutes les vues
drop_views() {
    log_warning "Suppression de toutes les vues..."
    
    # Liste des vues à supprimer (dans l'ordre inverse de création pour éviter les dépendances)
    VIEWS=(
        "export_last_24h"
        "dashboard_overview"
        "temperature_anomalies"
        "inactive_devices"
        "temperature_trends_by_site"
        "hourly_sensor_stats_24h"
        "device_signal_quality"
        "device_memory_stats"
        "daily_sensor_stats"
        "device_health"
        "latest_sensor_readings"
    )
    
    for view in "${VIEWS[@]}"; do
        log_info "Suppression de la vue $view..."
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "DROP VIEW IF EXISTS $view CASCADE;" 2>/dev/null || true
    done
    
    log_success "Toutes les vues ont été supprimées"
}

# Fonction pour lister les vues existantes
list_views() {
    log_info "Vues existantes dans la base de données :"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "\dv"
}

# Fonction pour afficher l'aide
show_help() {
    echo "Usage: $0 {create|drop|recreate|list|help}"
    echo ""
    echo "Commandes:"
    echo "  create     Créer toutes les vues depuis 03_create_views.sql"
    echo "  drop       Supprimer toutes les vues existantes"
    echo "  recreate   Supprimer puis recréer toutes les vues"
    echo "  list       Lister toutes les vues existantes"
    echo "  help       Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 create      # Créer les vues"
    echo "  $0 recreate    # Recréer toutes les vues"
    echo ""
}

# Fonction principale
main() {
    case "${1:-}" in
        "create")
            check_container
            create_views
            ;;
        "drop")
            check_container
            drop_views
            ;;
        "recreate")
            check_container
            drop_views
            create_views
            ;;
        "list")
            check_container
            list_views
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            log_error "Aucune commande spécifiée"
            show_help
            exit 1
            ;;
        *)
            log_error "Commande inconnue: $1"
            show_help
            exit 1
            ;;
    esac
}

# Point d'entrée
main "$@"