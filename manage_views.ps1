# =============================================================================
# DATAYOTI - SCRIPT DE GESTION DES VUES (PowerShell)
# =============================================================================
# Ce script permet de gérer les vues de base de données de manière indépendante
# 
# Usage:
#   .\manage_views.ps1 create    # Créer toutes les vues
#   .\manage_views.ps1 drop      # Supprimer toutes les vues
#   .\manage_views.ps1 recreate  # Supprimer puis recréer toutes les vues
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("create", "drop", "recreate", "list", "help")]
    [string]$Action
)

# Configuration
$CONTAINER_NAME = "datayoti-db"
$DB_NAME = "datayoti_db"
$DB_USER = "postgres"
$VIEWS_FILE = "/docker-entrypoint-initdb.d/03_create_views.sql"

# Fonction pour afficher les messages colorés
function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Blue
}

function Write-Success($message) {
    Write-Host "[SUCCESS] $message" -ForegroundColor Green
}

function Write-Warning($message) {
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

function Write-Error($message) {
    Write-Host "[ERROR] $message" -ForegroundColor Red
}

# Fonction pour vérifier si le conteneur existe et est en cours d'exécution
function Test-Container {
    $container = docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}" | Select-String $CONTAINER_NAME
    if (-not $container) {
        Write-Error "Le conteneur $CONTAINER_NAME n'est pas en cours d'exécution"
        Write-Info "Assurez-vous que Docker Compose est démarré : docker-compose up -d"
        exit 1
    }
}

# Fonction pour créer les vues
function New-Views {
    Write-Info "Création des vues de base de données..."
    
    $scriptPath = Join-Path $PSScriptRoot "db\init\03_create_views.sql"
    
    try {
        Get-Content $scriptPath | docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME
        Write-Success "Vues créées avec succès"
    }
    catch {
        Write-Error "Erreur lors de la création des vues: $($_.Exception.Message)"
        exit 1
    }
}

# Fonction pour supprimer toutes les vues
function Remove-Views {
    Write-Warning "Suppression de toutes les vues..."
    
    # Liste des vues standards à supprimer
    $views = @(
        "device_health",
        "latest_sensor_readings"
    )
    
    # Liste des vues matérialisées (agrégations continues)
    $materializedViews = @(
        "semi_hourly_sensor_stats",
        "sensor_data_hourly"
    )
    
    foreach ($view in $views) {
        Write-Info "Suppression de la vue $view..."
        try {
            docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "DROP VIEW IF EXISTS $view CASCADE;" 2>$null
        }
        catch {
            # Ignorer les erreurs de suppression
        }
    }
    
    foreach ($matView in $materializedViews) {
        Write-Info "Suppression de la vue matérialisée $matView..."
        try {
            docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "DROP MATERIALIZED VIEW IF EXISTS $matView CASCADE;" 2>$null
        }
        catch {
            # Ignorer les erreurs de suppression
        }
    }
    
    Write-Success "Toutes les vues ont été supprimées"
}

# Fonction pour lister les vues existantes
function Get-Views {
    Write-Info "Vues existantes dans la base de données :"
    docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "\dv"
    Write-Info "Vues matérialisées existantes :"
    docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "\dm"
}

# Fonction pour afficher l'aide
function Show-Help {
    Write-Host @"
Usage: .\manage_views.ps1 -Action {create|drop|recreate|list|help}

Commandes:
  create     Créer toutes les vues depuis 03_create_views.sql
  drop       Supprimer toutes les vues existantes (normales et matérialisées)
  recreate   Supprimer puis recréer toutes les vues
  list       Lister toutes les vues existantes (normales et matérialisées)
  help       Afficher cette aide

Exemples:
  .\manage_views.ps1 -Action create      # Créer les vues
  .\manage_views.ps1 -Action recreate    # Recréer toutes les vues
"@
}

# Fonction principale
switch ($Action) {
    "create" {
        Test-Container
        New-Views
    }
    "drop" {
        Test-Container
        Remove-Views
    }
    "recreate" {
        Test-Container
        Remove-Views
        New-Views
    }
    "list" {
        Test-Container
        Get-Views
    }
    "help" {
        Show-Help
    }
    default {
        Write-Error "Commande inconnue: $Action"
        Show-Help
        exit 1
    }
}