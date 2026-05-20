# Laboratorio de Ansible

Este repositorio contiene la infraestructura para desplegar un laboratorio de Ansible para múltiples alumnos en un único VPS utilizando contenedores Docker. 

## Arquitectura

- **Traefik**: Proxy inverso global encargado de rutear `alumnoXX.dominio.com` al contenedor Code-Server (IDE) correcto.
- **Entorno por Alumno**:
  - `control`: IDE Web (linuxserver/code-server) con `ansible`, `sshpass` y herramientas instaladas.
  - `target1` y `target2`: Contenedores Ubuntu preparados para correr Ansible, con soporte para `systemd` y Docker-in-Docker (DinD).

## Despliegue del Laboratorio

### 1. Requisitos Previos
- Docker y Docker Compose instalados en el VPS.
- Dominio configurado apuntando a la IP del VPS mediante un registro A Wildcard (ej. `*.midominio.com -> <IP-VPS>`).

### 2. Desplegar el Laboratorio Completo
El script `setup.sh` automatiza todo el proceso: crea la red de Traefik, levanta el proxy, genera los entornos de alumnos y los despliega.

```bash
# Otorgar permisos de ejecución al script (solo la primera vez)
chmod +x setup.sh

# Ejecutar el script indicando número de alumnos y dominio
./setup.sh 15 midominio.com
```
*El script generará la carpeta `alumnos/` con 15 subcarpetas (alumno01 a alumno15), cada una con su respectivo `docker-compose.yml` y Dockerfiles, y levantará todos los contenedores automáticamente.*

> **Nota**: Al ser un total de 45 contenedores (3 por alumno × 15 alumnos), tardará varios minutos en compilar las imágenes.

### 5. Acceso para los Alumnos
Cada alumno podrá acceder a su IDE web en su navegador:
- **URL**: `http://alumno01.midominio.com` (Sustituir 01 por su número)
- **Password Code-Server**: `ansible` (configurable en el archivo `templates/docker-compose.yml`)

Desde la terminal del Code-Server, podrán probar la conexión SSH o Ansible contra sus target nodes (`alumno01-target1` y `alumno01-target2`).

## Destruir el Laboratorio
Para limpiar completamente el laboratorio una vez finalizado el curso:

```bash
# Apagar todos los entornos y borrar volúmenes
for d in alumnos/*; do
  (cd "$d" && docker compose down -v)
done

# Borrar carpetas de alumnos
rm -rf alumnos/

# Apagar Traefik
cd traefik
docker compose down -v
cd ..
```
