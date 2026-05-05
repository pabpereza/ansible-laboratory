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

echo "Iniciando la configuración del Laboratorio Ansible..."

# 1. Crear red proxy de Traefik si no existe
if ! docker network ls | grep -q "proxy"; then
    echo "-> Creando la red global 'proxy' para Traefik..."
    docker network create proxy
else
    echo "-> La red 'proxy' ya existe."
fi

# 2. Generar directorios para cada alumno
echo "-> Generando stacks para $NUM_ALUMNOS alumnos bajo el dominio *.$DOMINIO..."

for i in $(seq -f "%02g" 1 "$NUM_ALUMNOS"); do
    ALUMNO_ID="alumno$i"
    ALUMNO_DIR="alumnos/$ALUMNO_ID"
    
    # Crear directorio base y subdirectorios necesarios
    mkdir -p "$ALUMNO_DIR/workspace"
    
    # Copiar los Dockerfiles (control y target)
    cp templates/Dockerfile.control "$ALUMNO_DIR/Dockerfile.control"
    cp templates/Dockerfile.target "$ALUMNO_DIR/Dockerfile.target"
    
    # Generar el docker-compose.yml del alumno sustituyendo las variables
    sed -e "s/__ALUMNO_ID__/$ALUMNO_ID/g" \
        -e "s/__DOMINIO__/$DOMINIO/g" \
        templates/docker-compose.yml > "$ALUMNO_DIR/docker-compose.yml"
        
    echo "   - Creado entorno para $ALUMNO_ID en ./$ALUMNO_DIR"
done

echo ""
echo "¡Generación completada con éxito!"
echo "Revisa el archivo README.md para ver las instrucciones de despliegue."
