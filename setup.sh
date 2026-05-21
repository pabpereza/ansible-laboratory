#!/bin/bash

# Salir inmediatamente si algún comando falla
set -e

if [ "$#" -ne 2 ]; then
    echo "Error: Argumentos inválidos."
    echo "Uso: $0 <numero_alumnos> <dominio>"
    echo "Ejemplo: $0 15 midominio.com"
    exit 1
fi

NUM_ALUMNOS=$1
DOMINIO=$2

# Pedir email para Let's Encrypt
read -rp "Email para Let's Encrypt (ACME): " ACME_EMAIL
if [ -z "$ACME_EMAIL" ]; then
    echo "Error: el email no puede estar vacío."
    exit 1
fi

# Pedir contraseña de acceso al Code-Server de cada alumno (sin eco para no dejarla en historial)
while true; do
    read -rsp "Contraseña de acceso al Code-Server (alumnos): " CODER_PASSWORD
    echo
    read -rsp "Confirma la contraseña: " CODER_PASSWORD_CONFIRM
    echo
    if [ -z "$CODER_PASSWORD" ]; then
        echo "Error: la contraseña no puede estar vacía."
    elif [ "$CODER_PASSWORD" = "$CODER_PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Error: las contraseñas no coinciden. Inténtalo de nuevo."
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Iniciando la configuración del Laboratorio Ansible..."
echo "  Alumnos : $NUM_ALUMNOS"
echo "  Dominio : *.$DOMINIO"
echo ""

# 1. Crear red proxy de Traefik si no existe
if ! docker network ls --format '{{.Name}}' | grep -q "^proxy$"; then
    echo "-> Creando la red global 'proxy' para Traefik..."
    docker network create proxy
else
    echo "-> La red 'proxy' ya existe."
fi

# 2. Generar directorios para cada alumno y rutas de Traefik
echo "-> Generando stacks para $NUM_ALUMNOS alumnos bajo el dominio *.$DOMINIO..."

mkdir -p "$SCRIPT_DIR/traefik/dynamic"

for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
    ALUMNO_ID="alumno$i"
    ALUMNO_DIR="$SCRIPT_DIR/alumnos/$ALUMNO_ID"

    mkdir -p "$ALUMNO_DIR/workspace"

    cp "$SCRIPT_DIR/templates/Dockerfile.control" "$ALUMNO_DIR/Dockerfile.control"
    cp "$SCRIPT_DIR/templates/Dockerfile.target"  "$ALUMNO_DIR/Dockerfile.target"

    sed -e "s/__ALUMNO_ID__/$ALUMNO_ID/g" \
        -e "s/__DOMINIO__/$DOMINIO/g" \
        "$SCRIPT_DIR/templates/docker-compose.yml" > "$ALUMNO_DIR/docker-compose.yml"

    printf 'CODER_PASSWORD=%s\n' "$CODER_PASSWORD" > "$ALUMNO_DIR/.env"

    sed -e "s/__ALUMNO_ID__/$ALUMNO_ID/g" \
        -e "s/__DOMINIO__/$DOMINIO/g" \
        "$SCRIPT_DIR/templates/traefik-route.yml" > "$SCRIPT_DIR/traefik/dynamic/$ALUMNO_ID.yml"

    echo "   - Generado entorno para $ALUMNO_ID"
done

echo ""

# 3. Levantar Traefik (con las rutas ya generadas en dynamic/)
echo "-> Levantando Traefik..."
echo "ACME_EMAIL=$ACME_EMAIL" > "$SCRIPT_DIR/traefik/.env"
docker compose -f "$SCRIPT_DIR/traefik/docker-compose.yml" up -d
echo "   Traefik listo."

echo ""

# 4. Desplegar todos los entornos de alumnos (después de Traefik para que la red proxy exista)
echo "-> Desplegando entornos de alumnos (esto puede tardar varios minutos)..."

for d in "$SCRIPT_DIR/alumnos"/*/; do
    ALUMNO=$(basename "$d")
    echo "   - Levantando $ALUMNO..."
    docker compose -f "$d/docker-compose.yml" up -d --build
done

echo ""
echo "¡Laboratorio desplegado con éxito!"
echo ""
echo "Acceso para los alumnos:"
for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
    echo "  https://alumno$i.$DOMINIO"
done
echo ""
echo "La contraseña de acceso es la que introdujiste durante la instalación."
