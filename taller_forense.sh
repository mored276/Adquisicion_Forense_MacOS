#!/bin/zsh
# =============================================================================
# TALLER DE INFORMÁTICA FORENSE - macOS
# Automatización de adquisición, verificación e integridad de evidencia digital
# Autor: Edwin Moreyra
# =============================================================================

set -euo pipefail

# --- Manual / Ayuda ----------------------------------------------------------
uso() {
    cat << 'MANUAL'
================================================================================
  TALLER DE INFORMÁTICA FORENSE - macOS
  Manual de uso del script de automatización
================================================================================

DESCRIPCIÓN:
  Este script automatiza el flujo de adquisición, verificación e integridad
  de evidencia digital en macOS usando exclusivamente herramientas nativas.

USO:
  ./taller_forense.sh [opciones]

OPCIONES:
  -o RUTA   Directorio ORIGEN (evidencia a adquirir)
  -d RUTA   Directorio DESTINO (donde se copia la evidencia)
  -l RUTA   Directorio de LOGS (bitácoras, hashes, reportes)
  -m MÓD    Módulo a ejecutar (ver sección MÓDULOS)
  -h        Mostrar este manual

  Si no se pasan opciones, se usan rutas por defecto:
    Origen:   ~/Taller_Forense/Origen
    Destino:  ~/Taller_Forense/Destino
    Logs:     ~/Taller_Forense/Logs

MÓDULOS DISPONIBLES (-m):
  all   Ejecutar flujo completo en secuencia (por defecto)
          → Orden: A (copia) → C (hashing) → Bloqueo (uchg) → B (metadatos)
          → La validación mdls se ejecuta DESPUÉS del bloqueo de evidencia
  a     Módulo A: Adquisición con rsync + bitácora (script)
          → Copia archivos preservando atributos extendidos (-E)
          → Graba la sesión de terminal en archivo de bitácora
          → Genera log detallado de rsync
  b     Módulo B: Verificación de metadatos (xattr + mdls)
          → Compara atributos extendidos (xattr -l) entre origen y destino
          → Compara metadatos de Spotlight (mdls) sin forzar indexación
          → Requiere haber ejecutado el Módulo A primero
  c     Módulo C: Hashing de integridad (MD5 + SHA-1 + SHA-256)
          → Genera hashes MD5, SHA-1 y SHA-256 de todos los archivos
          → Compara hashes entre origen y destino y registra resultado en reporte
          → Requiere haber ejecutado el Módulo A primero

EJEMPLOS:
  # Ejecutar todo con rutas por defecto (taller):
  ./taller_forense.sh

  # Ejecutar todo apuntando a rutas reales:
  ./taller_forense.sh -o /Users/sospechoso/Documents -d /Volumes/USB/Evidencia

  # Solo adquisición (Módulo A) con disco externo:
  ./taller_forense.sh -o /Users/victima/Desktop -d /Volumes/MiUSB/Caso001 -m a

  # Solo verificación de hashes (Módulo C):
  ./taller_forense.sh -m c

  # Personalizar todas las rutas:
  ./taller_forense.sh -o /origen -d /destino -l /mis/logs -m all

NOTAS:
  - Todos los comandos usados son nativos de macOS (no requiere software extra)
  - Cada ejecución genera archivos con timestamp único (no sobrescribe)
  - Método de adquisición usado en este script: rsync -avE (Módulo A)
================================================================================
MANUAL
    exit 0
}

# --- Configuración -----------------------------------------------------------
BASE_DIR="$HOME/Taller_Forense"
ORIGEN=""
DESTINO=""
LOGS_DIR=""
MODULO="all"

# Parsear argumentos de línea de comandos
while getopts ":o:d:l:m:h" opt; do
    case $opt in
        o) ORIGEN="$OPTARG" ;;
        d) DESTINO="$OPTARG" ;;
        l) LOGS_DIR="$OPTARG" ;;
        m) MODULO="$OPTARG" ;;
        h) uso ;;
        \?) echo "Opción inválida: -$OPTARG (use -h para ver el manual)" >&2; exit 1 ;;
        :)  echo "La opción -$OPTARG requiere un argumento (use -h para ver el manual)" >&2; exit 1 ;;
    esac
done

# Aplicar rutas por defecto donde no se especificaron
ORIGEN="${ORIGEN:-$BASE_DIR/Origen}"
DESTINO="${DESTINO:-$BASE_DIR/Destino}"
LOGS_DIR="${LOGS_DIR:-$BASE_DIR/Logs}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_EJECUCION="$LOGS_DIR/registro_ejecucion_${TIMESTAMP}.log"

# Detectar si se usan rutas por defecto
USANDO_DEFAULTS=false
if [[ "$ORIGEN" == "$BASE_DIR/Origen" && "$DESTINO" == "$BASE_DIR/Destino" ]]; then
    USANDO_DEFAULTS=true
fi

# --- Colores -----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # Reset

# --- Funciones auxiliares ----------------------------------------------------
banner() {
    echo ""
    echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo "${BOLD}  $1${NC}"
    echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

info()    { echo "${GREEN}[✓]${NC} $1"; }
warn()    { echo "${YELLOW}[!]${NC} $1"; }
error()   { echo "${RED}[✗]${NC} $1"; }
step()    { echo "\n${BOLD}▶ $1${NC}"; }
registrar_evento() {
    local marca_tiempo=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo "[$marca_tiempo] $1" >> "$LOG_EJECUCION"
}

validar_directorio() {
    if [[ ! -d "$1" ]]; then
        error "No existe el directorio: $1"
        exit 1
    fi
}

# --- Pre-vuelo ---------------------------------------------------------------
banner "TALLER FORENSE macOS - Inicio de Sesión"
echo "  Fecha/Hora : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "  Analista   : $(whoami)"
echo "  Equipo     : $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "  macOS      : $(sw_vers -productVersion)"
echo "  Origen     : $ORIGEN"
echo "  Destino    : $DESTINO"
echo "  Logs       : $LOGS_DIR"
echo "  Módulo     : $MODULO"
if $USANDO_DEFAULTS; then
    echo ""
    warn "Ejecutando con RUTAS POR DEFECTO (no se especificaron -o/-d)"
    warn "Use -h para ver cómo personalizar las rutas"
fi
echo ""

validar_directorio "$ORIGEN"
mkdir -p "$DESTINO" "$LOGS_DIR"
cat > "$LOG_EJECUCION" << EOF
# REGISTRO DE EJECUCIÓN FORENSE
# Fecha/Hora inicio: $(date '+%Y-%m-%d %H:%M:%S %Z')
# Analista: $(whoami)
# Equipo: $(scutil --get ComputerName 2>/dev/null || hostname)
# macOS: $(sw_vers -productVersion)
# Origen: $ORIGEN
# Destino: $DESTINO
# Logs: $LOGS_DIR
# Módulo: $MODULO
# ============================================
EOF
info "Registro de ejecución: $LOG_EJECUCION"
registrar_evento "Sesión iniciada"

# =============================================================================
# MÓDULO A: Adquisición con rsync + Bitácora con script
# =============================================================================
modulo_a() {
    banner "MÓDULO A: Adquisición con rsync y Trazabilidad"
    registrar_evento "Módulo A iniciado"

    local LOG_BITACORA="$LOGS_DIR/bitacora_rsync_${TIMESTAMP}.txt"
    local LOG_RSYNC="$LOGS_DIR/rsync_detalle_${TIMESTAMP}.log"

    step "Iniciando bitácora de sesión"
    info "Bitácora: $LOG_BITACORA"

    # Usamos script -q para grabar la ejecución de rsync
    # En macOS BSD, la sintaxis es: script [-q] archivo comando
    script -q "$LOG_BITACORA" rsync -avE --log-file="$LOG_RSYNC" "$ORIGEN/" "$DESTINO/"

    info "Copia forense completada"
    info "Log detallado de rsync: $LOG_RSYNC"
    info "Bitácora de terminal: $LOG_BITACORA"

    # Resumen rápido
    local n_origen=$(find "$ORIGEN" -type f | wc -l | tr -d ' ')
    local n_destino=$(find "$DESTINO" -type f | wc -l | tr -d ' ')
    echo ""
    warn "Archivos en origen:  $n_origen"
    warn "Archivos en destino: $n_destino"

    if [[ "$n_origen" -eq "$n_destino" ]]; then
        info "Conteo de archivos coincide ✓"
        registrar_evento "Módulo A completado: conteo de archivos coincide (origen=$n_origen, destino=$n_destino)"
    else
        error "¡ALERTA! Diferencia en conteo de archivos"
        registrar_evento "Módulo A alerta: diferencia de conteo (origen=$n_origen, destino=$n_destino)"
    fi
}

# =============================================================================
# MÓDULO B: Verificación de Atributos Extendidos con mdls
# =============================================================================
modulo_b() {
    banner "MÓDULO B: Verificación de Metadatos y Atributos Extendidos"
    registrar_evento "Módulo B iniciado"

    local REPORTE_XATTR="$LOGS_DIR/reporte_xattr_${TIMESTAMP}.txt"
    local REPORTE_MDLS="$LOGS_DIR/reporte_mdls_${TIMESTAMP}.txt"

    # ==========================================================
    # PARTE 1: Atributos Extendidos (xattr) — lectura directa
    # ==========================================================
    step "Parte 1: Comparando atributos extendidos (xattr -l)"
    info "xattr lee directamente del archivo, no del índice de Spotlight"
    info "Esto es lo que rsync -E preserva"

    local hay_dif_xattr=false

    echo "# REPORTE DE ATRIBUTOS EXTENDIDOS (xattr)" > "$REPORTE_XATTR"
    echo "# Fecha: $(date)" >> "$REPORTE_XATTR"
    echo "# ============================================" >> "$REPORTE_XATTR"

    while IFS= read -r archivo_origen; do
        local relativo="${archivo_origen#$ORIGEN/}"
        local archivo_destino="$DESTINO/$relativo"

        if [[ ! -f "$archivo_destino" ]]; then
            error "Archivo faltante en destino: $relativo"
            hay_dif_xattr=true
            continue
        fi

        local xattr_orig=$(xattr -l "$archivo_origen" 2>/dev/null)
        local xattr_dest=$(xattr -l "$archivo_destino" 2>/dev/null)

        echo "\n--- $relativo ---" >> "$REPORTE_XATTR"

        if diff <(echo "$xattr_orig") <(echo "$xattr_dest") >> "$REPORTE_XATTR" 2>&1; then
            info "xattr OK: $relativo"
        else
            warn "xattr diferencias: $relativo (ver reporte)"
            hay_dif_xattr=true
        fi
    done < <(find "$ORIGEN" -type f)

    echo ""
    if $hay_dif_xattr; then
        warn "Se detectaron diferencias en xattr - revisar $REPORTE_XATTR"
    else
        info "Atributos extendidos idénticos en todos los archivos ✓"
    fi

    # ==========================================================
    # PARTE 2: Metadatos Spotlight (mdls) — lectura del índice
    # Sin forzar indexación (mdimport) para no alterar el estado
    # ==========================================================
    step "Parte 2: Comparando metadatos Spotlight (mdls)"
    info "mdls lee del índice de Spotlight (sin forzar indexación)"
    info "Se comparan los metadatos tal como Spotlight los tiene indexados"
    registrar_evento "Módulo B: Inicio comparación mdls (sin mdimport)"

    local hay_dif_mdls=false

    echo "# REPORTE DE METADATOS SPOTLIGHT (mdls)" > "$REPORTE_MDLS"
    echo "# Fecha: $(date)" >> "$REPORTE_MDLS"
    echo "# ============================================" >> "$REPORTE_MDLS"

    # Campos que cambian legítimamente al copiar:
    local FILTRO="kMDItemPath\|kMDItemDateAdded\|kMDItemFSNodeCount\|kMDItemPhysicalSize\|_kMDItemPrimaryTextEmbedding\|kMDItemEmbeddingVersion\|kMDItemDocumentIdentifier\|vec_\|kMDItemInterestingDate_Ranking\|kMDItemContentCreationDate_Ranking"

    while IFS= read -r archivo_origen; do
        local relativo="${archivo_origen#$ORIGEN/}"
        local archivo_destino="$DESTINO/$relativo"

        [[ ! -f "$archivo_destino" ]] && continue

        local mdls_orig=$(mdls "$archivo_origen" 2>/dev/null | grep -v "$FILTRO")
        local mdls_dest=$(mdls "$archivo_destino" 2>/dev/null | grep -v "$FILTRO")

        echo "\n--- $relativo ---" >> "$REPORTE_MDLS"

        if diff <(echo "$mdls_orig") <(echo "$mdls_dest") >> "$REPORTE_MDLS" 2>&1; then
            info "mdls OK: $relativo"
        else
            warn "mdls diferencias: $relativo (ver reporte)"
            hay_dif_mdls=true
        fi
    done < <(find "$ORIGEN" -type f)

    echo ""
    info "Reporte xattr: $REPORTE_XATTR"
    info "Reporte mdls:  $REPORTE_MDLS"
    registrar_evento "Módulo B: Reportes generados — xattr: $REPORTE_XATTR, mdls: $REPORTE_MDLS"

    if $hay_dif_mdls; then
        warn "Spotlight aún no indexó algunos archivos del destino."
        warn "Esto es normal — Spotlight es asíncrono y no se forzó indexación."
        warn "Los atributos extendidos (xattr) son la verificación primaria."
        registrar_evento "Módulo B completado con diferencias en mdls (esperables: no se forzó indexación)"
    else
        info "Todos los metadatos Spotlight verificados ✓"
        registrar_evento "Módulo B completado sin diferencias relevantes"
    fi

    if $hay_dif_xattr; then
        registrar_evento "Módulo B ALERTA: diferencias en atributos extendidos (xattr)"
    else
        registrar_evento "Módulo B: atributos extendidos (xattr) idénticos en todos los archivos"
    fi
}

# =============================================================================
# MÓDULO C: Hashing Recursivo (MD5 + SHA-1 + SHA-256)
# =============================================================================
modulo_c() {
    banner "MÓDULO C: Verificación de Integridad (Hashing)"
    registrar_evento "Módulo C iniciado"

    local HASH_MD5_ORIG="$LOGS_DIR/hash_md5_origen_${TIMESTAMP}.txt"
    local HASH_MD5_DEST="$LOGS_DIR/hash_md5_destino_${TIMESTAMP}.txt"
    local HASH_SHA1_ORIG="$LOGS_DIR/hash_sha1_origen_${TIMESTAMP}.txt"
    local HASH_SHA1_DEST="$LOGS_DIR/hash_sha1_destino_${TIMESTAMP}.txt"
    local HASH_SHA_ORIG="$LOGS_DIR/hash_sha256_origen_${TIMESTAMP}.txt"
    local HASH_SHA_DEST="$LOGS_DIR/hash_sha256_destino_${TIMESTAMP}.txt"
    local REPORTE_VALIDACION="$LOGS_DIR/reporte_validacion_hashes_${TIMESTAMP}.txt"
    local validacion_exitosa=true

    echo "# REPORTE DE VALIDACIÓN DE HASHES" > "$REPORTE_VALIDACION"
    echo "# Fecha: $(date)" >> "$REPORTE_VALIDACION"
    echo "# Origen: $ORIGEN" >> "$REPORTE_VALIDACION"
    echo "# Destino: $DESTINO" >> "$REPORTE_VALIDACION"
    echo "# ============================================" >> "$REPORTE_VALIDACION"

    # --- MD5 ---
    step "Generando hashes MD5"

    # Generar hashes con rutas relativas para comparación
    (cd "$ORIGEN" && find . -type f -exec md5 {} \; | sed "s|MD5 (./|MD5 (|" | sort) > "$HASH_MD5_ORIG"
    (cd "$DESTINO" && find . -type f -exec md5 {} \; | sed "s|MD5 (./|MD5 (|" | sort) > "$HASH_MD5_DEST"

    info "MD5 Origen:  $HASH_MD5_ORIG"
    info "MD5 Destino: $HASH_MD5_DEST"
    echo "\n## MD5" >> "$REPORTE_VALIDACION"
    echo "Origen : $HASH_MD5_ORIG" >> "$REPORTE_VALIDACION"
    echo "Destino: $HASH_MD5_DEST" >> "$REPORTE_VALIDACION"

    echo ""
    step "Comparando hashes MD5"
    if diff "$HASH_MD5_ORIG" "$HASH_MD5_DEST" > /dev/null 2>&1; then
        info "MD5: Todos los hashes coinciden ✓"
        echo "[OK] MD5 coincide" >> "$REPORTE_VALIDACION"
    else
        error "MD5: ¡Se detectaron diferencias!"
        echo "[FAIL] MD5 con diferencias" >> "$REPORTE_VALIDACION"
        diff "$HASH_MD5_ORIG" "$HASH_MD5_DEST" >> "$REPORTE_VALIDACION" || true
        validacion_exitosa=false
    fi

    # --- SHA-1 ---
    echo ""
    step "Generando hashes SHA-1"

    (cd "$ORIGEN" && find . -type f -exec shasum -a 1 {} \; | sed "s|  ./|  |" | sort) > "$HASH_SHA1_ORIG"
    (cd "$DESTINO" && find . -type f -exec shasum -a 1 {} \; | sed "s|  ./|  |" | sort) > "$HASH_SHA1_DEST"

    info "SHA-1 Origen:  $HASH_SHA1_ORIG"
    info "SHA-1 Destino: $HASH_SHA1_DEST"
    echo "\n## SHA-1" >> "$REPORTE_VALIDACION"
    echo "Origen : $HASH_SHA1_ORIG" >> "$REPORTE_VALIDACION"
    echo "Destino: $HASH_SHA1_DEST" >> "$REPORTE_VALIDACION"

    echo ""
    step "Comparando hashes SHA-1"
    if diff "$HASH_SHA1_ORIG" "$HASH_SHA1_DEST" > /dev/null 2>&1; then
        info "SHA-1: Todos los hashes coinciden ✓"
        echo "[OK] SHA-1 coincide" >> "$REPORTE_VALIDACION"
    else
        error "SHA-1: ¡Se detectaron diferencias!"
        echo "[FAIL] SHA-1 con diferencias" >> "$REPORTE_VALIDACION"
        diff "$HASH_SHA1_ORIG" "$HASH_SHA1_DEST" >> "$REPORTE_VALIDACION" || true
        validacion_exitosa=false
    fi

    # --- SHA-256 ---
    echo ""
    step "Generando hashes SHA-256 (estándar forense)"

    (cd "$ORIGEN" && find . -type f -exec shasum -a 256 {} \; | sed "s|  ./|  |" | sort) > "$HASH_SHA_ORIG"
    (cd "$DESTINO" && find . -type f -exec shasum -a 256 {} \; | sed "s|  ./|  |" | sort) > "$HASH_SHA_DEST"

    info "SHA-256 Origen:  $HASH_SHA_ORIG"
    info "SHA-256 Destino: $HASH_SHA_DEST"
    echo "\n## SHA-256" >> "$REPORTE_VALIDACION"
    echo "Origen : $HASH_SHA_ORIG" >> "$REPORTE_VALIDACION"
    echo "Destino: $HASH_SHA_DEST" >> "$REPORTE_VALIDACION"

    echo ""
    step "Comparando hashes SHA-256"
    if diff "$HASH_SHA_ORIG" "$HASH_SHA_DEST" > /dev/null 2>&1; then
        info "SHA-256: Todos los hashes coinciden ✓"
        echo "[OK] SHA-256 coincide" >> "$REPORTE_VALIDACION"
    else
        error "SHA-256: ¡Se detectaron diferencias!"
        echo "[FAIL] SHA-256 con diferencias" >> "$REPORTE_VALIDACION"
        diff "$HASH_SHA_ORIG" "$HASH_SHA_DEST" >> "$REPORTE_VALIDACION" || true
        validacion_exitosa=false
    fi

    echo ""
    info "Reporte consolidado de validación: $REPORTE_VALIDACION"

    if $validacion_exitosa; then
        info "Validación de hashes exitosa (MD5, SHA-1 y SHA-256) ✓"
        registrar_evento "VALIDACION_EXITOSA: MD5/SHA-1/SHA-256 coinciden. Reporte: $REPORTE_VALIDACION"
    else
        error "Validación de hashes fallida: revise $REPORTE_VALIDACION"
        registrar_evento "VALIDACION_FALLIDA: diferencias en hashes. Reporte: $REPORTE_VALIDACION"
        return 1
    fi

    # --- Mostrar hashes para el registro ---
    echo ""
    step "Hashes SHA-256 generados (para Cadena de Custodia)"
    cat "$HASH_SHA_ORIG"
}
bloquear_destino() {
    banner "PROTECCIÓN DE EVIDENCIA EN DESTINO"
    step "Aplicando bloqueo con chflags -R uchg"
    registrar_evento "Intento de bloqueo de destino con chflags -R uchg: $DESTINO"

    if chflags -R uchg "$DESTINO"; then
        info "Bloqueo aplicado en destino ✓"
        info "Para desbloquear manualmente: chflags -R nouchg \"$DESTINO\""
        registrar_evento "BLOQUEO_EXITOSO: chflags -R uchg aplicado sobre $DESTINO"
    else
        error "No fue posible aplicar bloqueo en destino"
        registrar_evento "BLOQUEO_FALLIDO: error al ejecutar chflags -R uchg sobre $DESTINO"
        return 1
    fi
}


# =============================================================================
# EJECUCIÓN PRINCIPAL
# =============================================================================
main() {
    registrar_evento "Ejecución principal iniciada (all) — Orden: A → C → Bloqueo → B"
    modulo_a
    modulo_c
    bloquear_destino
    registrar_evento "Destino bloqueado. Procediendo a validación de metadatos (mdls post-bloqueo)"
    modulo_b

    banner "TALLER COMPLETADO"
    echo "  Finalizado: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    step "Archivos generados en $LOGS_DIR:"
    ls -la "$LOGS_DIR/"
    echo ""
    info "Todos los módulos ejecutados exitosamente."
    registrar_evento "Ejecución principal completada exitosamente"
}

# Ejecutar módulo seleccionado
case "$MODULO" in
    a)   modulo_a ;;
    b)   modulo_b ;;
    c)   modulo_c; bloquear_destino ;;
    all) main ;;
    *)   echo "Módulo inválido: $MODULO (use -h para ver opciones)"; exit 1 ;;
esac
