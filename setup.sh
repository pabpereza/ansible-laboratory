#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================
# FUNCIÓN: genera el docker-compose.yml de un alumno
# Uso: generate_compose <alumno_id> <num_targets> <server|local>
# ==============================================================
generate_compose() {
    local ALUMNO_ID="$1"
    local NUM_TARGETS="$2"
    local COMPOSE_MODE="$3"  # server | local

    # --- Cabecera y nodo control ---
    if [[ "$COMPOSE_MODE" == "server" ]]; then
        cat <<EOF
services:
  control:
    build:
      context: .
      dockerfile: Dockerfile.control
    container_name: ${ALUMNO_ID}-control
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - PASSWORD=\${CODER_PASSWORD}
      - SUDO_PASSWORD=\${CODER_PASSWORD}
    volumes:
      - ./workspace:/config/workspace
    networks:
      - ${ALUMNO_ID}-net
      - proxy
    restart: unless-stopped

EOF
    else
        cat <<EOF
services:
  control:
    profiles:
      - control
    build:
      context: .
      dockerfile: Dockerfile.control
    container_name: ${ALUMNO_ID}-control
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Madrid
      - PASSWORD=\${CODER_PASSWORD}
      - SUDO_PASSWORD=\${CODER_PASSWORD}
    volumes:
      - ./workspace:/config/workspace
    networks:
      - ${ALUMNO_ID}-net
    restart: unless-stopped

EOF
    fi

    # --- N nodos target ---
    for j in $(seq 1 "$NUM_TARGETS"); do
        cat <<EOF
  target${j}:
    build:
      context: .
      dockerfile: Dockerfile.target
    container_name: ${ALUMNO_ID}-target${j}
    privileged: true
    cgroup: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
      - ${ALUMNO_ID}-target${j}-docker:/var/lib/docker
    networks:
      - ${ALUMNO_ID}-net
    command: /lib/systemd/systemd
    restart: unless-stopped

EOF
    done

    # --- Redes ---
    if [[ "$COMPOSE_MODE" == "server" ]]; then
        cat <<EOF
networks:
  ${ALUMNO_ID}-net:
    name: ${ALUMNO_ID}-net
  proxy:
    external: true

EOF
    else
        cat <<EOF
networks:
  ${ALUMNO_ID}-net:
    name: ${ALUMNO_ID}-net

EOF
    fi

    # --- Volúmenes ---
    echo "volumes:"
    for j in $(seq 1 "$NUM_TARGETS"); do
        echo "  ${ALUMNO_ID}-target${j}-docker:"
    done
}

# ==============================================================
# CABECERA
# ==============================================================
echo ""
echo "============================================"
echo "  Laboratorio Ansible - Configuración"
echo "============================================"
echo ""

# ==============================================================
# DETECCIÓN DE INSTALACIÓN EXISTENTE
# ==============================================================
if [ -d "$SCRIPT_DIR/alumnos" ] && [ "$(ls -A "$SCRIPT_DIR/alumnos" 2>/dev/null)" ]; then

    if ls "$SCRIPT_DIR/traefik/dynamic/"*.yml &>/dev/null; then
        _PREV_MODE="server"
    else
        _PREV_MODE="local"
    fi

    echo "Se ha detectado un laboratorio ya desplegado (modo: $_PREV_MODE)."
    echo ""
    echo "¿Qué deseas hacer?"
    echo "  1) Relanzar   (volver a levantar todos los contenedores sin reconfigurar)"
    echo "  2) Desinstalar (borrar todos los contenedores, volúmenes y ficheros generados)"
    echo "  3) Reinstalar  (nueva configuración, sobreescribe la actual)"
    echo ""
    read -rp "Selecciona [1/2/3]: " _EXISTING_ACTION

    # --- RELANZAR ---
    if [[ "$_EXISTING_ACTION" == "1" ]]; then
        echo ""

        if [[ "$_PREV_MODE" == "server" ]]; then
            if [ -f "$SCRIPT_DIR/traefik/letsencrypt/acme.json" ]; then
                _TRAEFIK_COMPOSE="$SCRIPT_DIR/traefik/docker-compose.yml"
            else
                _TRAEFIK_COMPOSE="$SCRIPT_DIR/traefik/docker-compose.nossl.yml"
            fi
            echo "-> Relanzando Traefik..."
            docker compose -f "$_TRAEFIK_COMPOSE" up -d
            echo "   Listo."
            echo ""
        fi

        _HAS_CONTROL=$(docker ps -a --filter "name=-control" --format "{{.Names}}" | head -1)

        echo "-> Relanzando entornos de alumnos..."
        for d in "$SCRIPT_DIR/alumnos"/*/; do
            echo "   - $(basename "$d")"
            if [[ "$_PREV_MODE" == "local" && -n "$_HAS_CONTROL" ]]; then
                docker compose -f "$d/docker-compose.yml" --profile control up -d
            else
                docker compose -f "$d/docker-compose.yml" up -d
            fi
        done

        echo ""
        echo "¡Laboratorio relanzado con éxito!"
        exit 0

    # --- DESINSTALAR ---
    elif [[ "$_EXISTING_ACTION" == "2" ]]; then
        echo ""
        read -rp "¿Seguro? Se borrarán todos los contenedores y volúmenes. [s/N]: " _CONFIRM_UNINSTALL
        [[ ! "$_CONFIRM_UNINSTALL" =~ ^[sS]$ ]] && { echo "Cancelado."; exit 0; }

        echo ""
        echo "-> Eliminando entornos de alumnos..."
        for d in "$SCRIPT_DIR/alumnos"/*/; do
            echo "   - $(basename "$d")"
            docker compose -f "$d/docker-compose.yml" --profile control down -v 2>/dev/null || \
            docker compose -f "$d/docker-compose.yml" down -v 2>/dev/null || true
        done

        if [[ "$_PREV_MODE" == "server" ]]; then
            echo ""
            echo "-> Eliminando Traefik..."
            docker compose -f "$SCRIPT_DIR/traefik/docker-compose.yml" down -v 2>/dev/null || \
            docker compose -f "$SCRIPT_DIR/traefik/docker-compose.nossl.yml" down -v 2>/dev/null || true
            rm -f "$SCRIPT_DIR/traefik/dynamic/"*.yml
            echo "   Listo."
        fi

        echo ""
        echo "-> Borrando ficheros generados..."
        rm -rf "$SCRIPT_DIR/alumnos"
        echo ""
        echo "Laboratorio desinstalado correctamente."
        exit 0

    # --- REINSTALAR: continúa con el flujo normal ---
    elif [[ "$_EXISTING_ACTION" == "3" ]]; then
        echo ""
        echo "Continuando con la nueva instalación..."
        echo ""
    else
        echo "Opción no válida."; exit 1
    fi
fi

# ==============================================================
# CONFIGURACIÓN INTERACTIVA
# ==============================================================

# 1. Modo de despliegue
echo "¿Dónde vas a desplegar el laboratorio?"
echo "  1) Local (tu propia máquina)"
echo "  2) VPS / Cloud (servidor con dominio)"
echo ""
read -rp "Selecciona [1/2]: " _MODE
case "$_MODE" in
    1) MODE="local" ;;
    2) MODE="server" ;;
    *) echo "Opción no válida."; exit 1 ;;
esac

# 2. Número de alumnos
echo ""
read -rp "Número de alumnos: " NUM_ALUMNOS
if ! [[ "$NUM_ALUMNOS" =~ ^[0-9]+$ ]] || [ "$NUM_ALUMNOS" -lt 1 ]; then
    echo "Error: debe ser un número entero mayor que 0."
    exit 1
fi

# 3. Número de nodos target por alumno
echo ""
read -rp "Número de nodos target por alumno: " NUM_TARGETS
if ! [[ "$NUM_TARGETS" =~ ^[0-9]+$ ]] || [ "$NUM_TARGETS" -lt 1 ]; then
    echo "Error: debe ser un número entero mayor que 0."
    exit 1
fi

if [[ "$MODE" == "server" ]]; then

    # 4. Dominio
    echo ""
    read -rp "Dominio base (ej: midominio.com): " DOMINIO
    [ -z "$DOMINIO" ] && { echo "Error: el dominio no puede estar vacío."; exit 1; }

    # 5. SSL
    echo ""
    read -rp "¿Habilitar SSL automático con Let's Encrypt? [S/n]: " _SSL
    if [[ "$_SSL" =~ ^[nN]$ ]]; then
        USE_SSL=false
    else
        USE_SSL=true
        read -rp "Email para Let's Encrypt (ACME): " ACME_EMAIL
        [ -z "$ACME_EMAIL" ] && { echo "Error: el email no puede estar vacío."; exit 1; }
    fi

    # 6. Contraseña code-server
    DEPLOY_CONTROL=true
    echo ""
    echo "Contraseña de acceso al Code-Server para los alumnos:"
    while true; do
        read -rsp "  Contraseña : " CODER_PASSWORD; echo
        read -rsp "  Confirma   : " _CONFIRM; echo
        if [ -z "$CODER_PASSWORD" ]; then
            echo "  Error: no puede estar vacía."
        elif [ "$CODER_PASSWORD" = "$_CONFIRM" ]; then
            break
        else
            echo "  Error: no coinciden. Inténtalo de nuevo."
        fi
    done

else

    # 4. Nodo de control
    echo ""
    echo "El nodo de control es un VS Code web (code-server) accesible desde el navegador."
    echo "Puedes omitirlo y usar tu propio editor, conectándote por SSH a los nodos target."
    echo ""
    read -rp "¿Desplegar nodo de control (code-server)? [s/N]: " _CTRL
    if [[ "$_CTRL" =~ ^[sS]$ ]]; then
        DEPLOY_CONTROL=true
        echo ""
        echo "Contraseña de acceso al Code-Server para los alumnos:"
        while true; do
            read -rsp "  Contraseña : " CODER_PASSWORD; echo
            read -rsp "  Confirma   : " _CONFIRM; echo
            if [ -z "$CODER_PASSWORD" ]; then
                echo "  Error: no puede estar vacía."
            elif [ "$CODER_PASSWORD" = "$_CONFIRM" ]; then
                break
            else
                echo "  Error: no coinciden. Inténtalo de nuevo."
            fi
        done
    else
        DEPLOY_CONTROL=false
    fi

fi

# --- Resumen y confirmación ---
echo ""
echo "--------------------------------------------"
echo "  Resumen:"
echo "  Modo    : $MODE"
echo "  Alumnos : $NUM_ALUMNOS"
echo "  Targets : $NUM_TARGETS por alumno"
if [[ "$MODE" == "server" ]]; then
    echo "  Dominio : *.$DOMINIO"
    [[ "$USE_SSL" == "true" ]] && echo "  SSL     : sí (Let's Encrypt)" || echo "  SSL     : no"
fi
[[ "$DEPLOY_CONTROL" == "true" ]] && echo "  Control : sí (code-server)" || echo "  Control : no (solo targets)"
echo "--------------------------------------------"
echo ""
read -rp "¿Continuar con la instalación? [S/n]: " _GO
[[ "$_GO" =~ ^[nN]$ ]] && { echo "Instalación cancelada."; exit 0; }
echo ""
echo "Iniciando despliegue..."
echo ""

# ==============================================================
# MODO SERVIDOR
# ==============================================================
if [[ "$MODE" == "server" ]]; then

    # 1. Red proxy
    if ! docker network ls --format '{{.Name}}' | grep -q "^proxy$"; then
        echo "-> Creando la red 'proxy' para Traefik..."
        docker network create proxy
    else
        echo "-> La red 'proxy' ya existe."
    fi

    # 2. Generar stacks de alumnos
    echo "-> Generando stacks para $NUM_ALUMNOS alumnos ($NUM_TARGETS targets cada uno)..."
    mkdir -p "$SCRIPT_DIR/traefik/dynamic"

    if [[ "$USE_SSL" == "true" ]]; then
        ROUTE_TEMPLATE="$SCRIPT_DIR/templates/traefik-route.yml"
    else
        ROUTE_TEMPLATE="$SCRIPT_DIR/templates/traefik-route.nossl.yml"
    fi

    for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
        ALUMNO_ID="alumno$i"
        ALUMNO_DIR="$SCRIPT_DIR/alumnos/$ALUMNO_ID"
        mkdir -p "$ALUMNO_DIR/workspace"

        cp "$SCRIPT_DIR/templates/Dockerfile.control" "$ALUMNO_DIR/Dockerfile.control"
        cp "$SCRIPT_DIR/templates/Dockerfile.target"  "$ALUMNO_DIR/Dockerfile.target"

        generate_compose "$ALUMNO_ID" "$NUM_TARGETS" "server" > "$ALUMNO_DIR/docker-compose.yml"

        printf 'CODER_PASSWORD=%s\n' "$CODER_PASSWORD" > "$ALUMNO_DIR/.env"

        sed -e "s/__ALUMNO_ID__/$ALUMNO_ID/g" \
            -e "s/__DOMINIO__/$DOMINIO/g" \
            "$ROUTE_TEMPLATE" > "$SCRIPT_DIR/traefik/dynamic/$ALUMNO_ID.yml"

        echo "   - $ALUMNO_ID"
    done
    echo ""

    # 3. Levantar Traefik
    echo "-> Levantando Traefik..."
    if [[ "$USE_SSL" == "true" ]]; then
        printf 'ACME_EMAIL=%s\n' "$ACME_EMAIL" > "$SCRIPT_DIR/traefik/.env"
        docker compose -f "$SCRIPT_DIR/traefik/docker-compose.yml" up -d
    else
        docker compose -f "$SCRIPT_DIR/traefik/docker-compose.nossl.yml" up -d
    fi
    echo "   Traefik listo."
    echo ""

    # 4. Desplegar alumnos
    echo "-> Desplegando entornos de alumnos (puede tardar varios minutos)..."
    for d in "$SCRIPT_DIR/alumnos"/*/; do
        echo "   - Levantando $(basename "$d")..."
        docker compose -f "$d/docker-compose.yml" up -d --build
    done

    PROTO="https"; [[ "$USE_SSL" == "false" ]] && PROTO="http"
    echo ""
    echo "¡Laboratorio desplegado con éxito!"
    echo ""
    echo "Acceso para los alumnos:"
    for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
        echo "  $PROTO://alumno$i.$DOMINIO"
    done
    echo ""
    echo "La contraseña de acceso es la que introdujiste durante la instalación."

# ==============================================================
# MODO LOCAL
# ==============================================================
else

    # 1. Generar stacks de alumnos
    echo "-> Generando stacks para $NUM_ALUMNOS alumnos ($NUM_TARGETS targets cada uno)..."

    for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
        ALUMNO_ID="alumno$i"
        ALUMNO_DIR="$SCRIPT_DIR/alumnos/$ALUMNO_ID"
        mkdir -p "$ALUMNO_DIR/workspace"

        cp "$SCRIPT_DIR/templates/Dockerfile.control" "$ALUMNO_DIR/Dockerfile.control"
        cp "$SCRIPT_DIR/templates/Dockerfile.target"  "$ALUMNO_DIR/Dockerfile.target"

        generate_compose "$ALUMNO_ID" "$NUM_TARGETS" "local" > "$ALUMNO_DIR/docker-compose.yml"

        if [[ "$DEPLOY_CONTROL" == "true" ]]; then
            printf 'CODER_PASSWORD=%s\n' "$CODER_PASSWORD" > "$ALUMNO_DIR/.env"
        fi

        echo "   - $ALUMNO_ID"
    done
    echo ""

    # 2. Desplegar alumnos
    echo "-> Desplegando entornos de alumnos (puede tardar varios minutos)..."
    for d in "$SCRIPT_DIR/alumnos"/*/; do
        echo "   - Levantando $(basename "$d")..."
        if [[ "$DEPLOY_CONTROL" == "true" ]]; then
            docker compose -f "$d/docker-compose.yml" --profile control up -d --build
        else
            docker compose -f "$d/docker-compose.yml" up -d --build
        fi
    done

    echo ""
    echo "¡Laboratorio desplegado con éxito!"
    echo ""
    echo "IPs de los contenedores:"
    for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
        ALUMNO_ID="alumno$i"
        NET="${ALUMNO_ID}-net"
        LINE="  $ALUMNO_ID →"
        if [[ "$DEPLOY_CONTROL" == "true" ]]; then
            IP_C=$(docker inspect --format "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "${ALUMNO_ID}-control" 2>/dev/null || echo "N/A")
            LINE="$LINE control: https://$IP_C:8443"
        fi
        for j in $(seq 1 "$NUM_TARGETS"); do
            IP_T=$(docker inspect --format "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "${ALUMNO_ID}-target${j}" 2>/dev/null || echo "N/A")
            LINE="$LINE | target${j}: $IP_T"
        done
        echo "$LINE"
    done
    echo ""
    echo "Nota: Docker no ofrece DNS del host hacia los contenedores. Usa las IPs"
    echo "      mostradas arriba o añade entradas manualmente a /etc/hosts."
fi
