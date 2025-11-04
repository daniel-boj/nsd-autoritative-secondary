#!/bin/bash
set -e

# Config Vars
POWERDNS_MASTER="${POWERDNS_MASTER}"
API_KEY="${API_KEY}"
ZONES_DIR="/etc/nsd/zones"

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create directories
setup_directories() {
    log "Creating runtime directories"
    mkdir -p /run/nsd /var/run/nsd
    chown -R nsd:nsd /run/nsd /var/run/nsd /etc/nsd
    chmod 755 /run/nsd /var/run/nsd
}

# Get and validate NSD config
validate_config() {
    log "Validatingb NSD config"
    if ! nsd-checkconf /etc/nsd/nsd.conf; then
        log "Error in NSD config file"
        exit 1
    fi
    log "Validated"
}

# Addingb zones
add_zones_to_nsd() {
    log "Adding zones to NSD configuration"
    
    local PATTERN_NAME=".*"  # ← Este es el nombre real de tu patrón
    
    # Verificar que el patrón existe probando con una zona temporal
    local test_zone="temp-verify-pattern-$(date +%s).test"
    if ! nsd-control addzone "$test_zone" "$PATTERN_NAME" 2>/dev/null; then
        log "ERROR: Pattern '$PATTERN_NAME' does not exist or is invalid"
        return 1
    else
        # Limpiar zona de prueba
        nsd-control delzone "$test_zone" 2>/dev/null
    fi
    
    local zones_added=0
    for zonefile in "$ZONES_DIR"/*.zone; do
        if [ -f "$zonefile" ]; then
            zonename=$(basename "$zonefile" .zone)
            
            if ! nsd-control zonestatus "$zonename" >/dev/null 2>&1; then
                log "Adding zone to NSD: $zonename"
                if nsd-control addzone "$zonename" "$PATTERN_NAME"; then
                    ((zones_added++))
                else
                    log "Warning: Failed to add zone $zonename"
                fi
            fi
        fi
    done
    
    log "Added $zones_added zones to NSD"
    
    if [ "$zones_added" -gt 0 ]; then
        nsd-control reconfig
    fi
}

# Función para sincronizar zonas inicialmente
sync_initial_zones() {
    log "Syncing master zones"
    
    # Crear directorio de zonas si no existe
    mkdir -p "$ZONES_DIR"
    
    # Verificar si ya existen zonas (para no resincronizar si ya hay datos)
    if [ "$(ls -A $ZONES_DIR 2>/dev/null)" ]; then
        log "All the zones alredy exists"
        return 0
    fi
    
    # Verificar conectividad con el master
    if ! dig +short "$POWERDNS_MASTER" > /dev/null; then
        log "Cannot stablish connection with Master server"
        return 0
    fi
    
    # Sincronizar zonas via API + AXFR
    log "Obtaining zones from API..."
    
    # Método 1: Via API (preferido)
    if ZONES=$(curl -s -H "X-API-Key: $API_KEY" \
        "http://$POWERDNS_MASTER:8081/api/v1/servers/localhost/zones" 2>/dev/null | \
        jq -r '.[].id' 2>/dev/null); then
        
        log "Found $(echo "$ZONES" | wc -l) zones via API"
        
        echo "$ZONES" | while read -r ZONE; do
            if [ -n "$ZONE" ]; then
                log "Synbcing: $ZONE"
                if dig +tcp +time=10 +retry=2 @"$POWERDNS_MASTER" "$ZONE" AXFR > "$ZONES_DIR/$ZONE.zone" 2>/dev/null; then
                    if [ -s "$ZONES_DIR/$ZONE.zone" ]; then
                        log "$ZONE transfered"
                    else
                        log "Empty  $ZONE"
                        rm -f "$ZONES_DIR/$ZONE.zone"
                    fi
                else
                    log "Error syncing $ZONE"
                fi
            fi
        done
    
    else
        # Método 2: Fallback - zonas preconfiguradas
        log "Error: Crit fail -> Cannot connect to the API"
    fi
    
    log "Initial config complete"
}

# Función para configurar permisos
setup_permissions() {
    log "Setting permissions..."
    chown -R nsd:nsd "$ZONES_DIR"
    chmod 644 "$ZONES_DIR"/*.zone 2>/dev/null || true
}

# Función para iniciar NSD
start_nsd() {
    log "Initializing NSD..."
    
    # Validar configuración final
    validate_config
    
    # Iniciar NSD en primer plano (requerido por Docker)
    exec nsd -d -c /etc/nsd/nsd.conf
}

# Función de limpieza al salir
cleanup() {
    log "Stopping NSD..."
    nsd-control stop 2>/dev/null || true
    exit 0
}

# Manejar señales de Docker
trap cleanup SIGTERM SIGINT

# Entrypoint
# Función principal
main() {
    log "Starting NSD container"

    # Setup inicial
    setup_directories
    setup_permissions
    
    # Sincronizar zonas (sin NSD corriendo)
    sync_initial_zones
    setup_permissions

    # Start service
    log "Starting NSD server"
    start_nsd
    
    # Waiting
    log "Waiting for NSD to start..."
    sleep 10
    
    # Add zones to NSD
    add_zones_to_nsd

    log "NSD is running with all zones loaded"
    #wait
}

# Manejar señales de Docker
trap "log 'Stopping NSD...'; nsd-control stop 2>/dev/null || true; exit 0" SIGTERM SIGINT

# Ejecutar función principal
main "$@"
