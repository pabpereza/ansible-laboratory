# Laboratorio de Ansible

Infraestructura para desplegar un laboratorio de Ansible para múltiples alumnos en un único VPS o en local, usando contenedores Docker.

> [!WARNING]
> **Entorno inseguro por diseño.**
> Para simplificar la puesta a punto de una infraestructura compleja de aprendizaje, los contenedores target se ejecutan con configuraciones deliberadamente inseguras:
> - Modo `privileged` activo (acceso total al kernel del host).
> - `cgroup: host` compartido entre contenedor y host.
> - Volumen `/sys/fs/cgroup` montado en modo escritura.
> - Docker-in-Docker (DinD) habilitado.
>
> **No uses este laboratorio en producción ni expongas los contenedores a internet sin un control de acceso adicional.**

## Arquitectura

- **Traefik** *(solo modo VPS/Cloud)*: Proxy inverso que enruta `alumnoXX.dominio.com` al contenedor Code-Server correcto y gestiona certificados SSL via Let's Encrypt.
- **Entorno por alumno**:
  - `control`: IDE web (VS Code via code-server) con `ansible`, `sshpass` y herramientas instaladas. Opcional en modo local.
  - `targetN`: N contenedores Debian (configurable en la instalación) preparados para ejecutar Ansible, con soporte para `systemd` y Docker-in-Docker (DinD).

## Modos de despliegue

### Modo VPS / Cloud
Pensado para un servidor remoto con un dominio wildcard apuntando a su IP. Traefik expone cada entorno en `alumnoXX.dominio.com` con HTTPS (opcional).

### Modo local
Pensado para pruebas en tu propia máquina. No requiere dominio ni Traefik. El nodo de control (code-server) es opcional: puedes usar tu propio editor y conectarte por SSH a los nodos target usando las IPs de los contenedores.

> **DNS local**: Docker no ofrece resolución de nombres de contenedores desde el host. Usa las IPs que muestra el instalador al terminar, o añade entradas a `/etc/hosts` manualmente.

## Instalación

### Requisitos previos
- Docker y Docker Compose instalados.
- *(Solo modo VPS)* Dominio con registro A Wildcard apuntando a la IP del servidor (ej. `*.midominio.com → <IP>`).

### Ejecutar el instalador

```bash
chmod +x setup.sh
./setup.sh
```

El instalador es completamente interactivo y guiará por los siguientes pasos:

```
¿Dónde vas a desplegar el laboratorio?
  1) Local (tu propia máquina)
  2) VPS / Cloud (servidor con dominio)

Número de alumnos: ...

# Si es VPS/Cloud:
  Dominio base: ...
  ¿Habilitar SSL con Let's Encrypt? → email ACME
  Contraseña de acceso al Code-Server (con confirmación, sin eco)

# Si es local:
  ¿Desplegar nodo de control (code-server)?
  → Si sí: contraseña de acceso (con confirmación, sin eco)
```

Al final muestra un resumen y pide confirmación antes de ejecutar.

### Acceso tras la instalación

**Modo VPS/Cloud:**
```
https://alumno01.midominio.com   ← con SSL
http://alumno01.midominio.com    ← sin SSL
```
La contraseña es la introducida durante la instalación.

**Modo local:**
```
IPs de los contenedores:
  alumno01 → control: https://172.x.x.x:8443 | target1: 172.x.x.x | target2: 172.x.x.x
```

## Dashboard de Traefik *(solo modo VPS/Cloud)*

El dashboard está disponible únicamente en `localhost:8080` del servidor (no expuesto al exterior). Accede mediante un túnel SSH desde tu máquina:

```bash
ssh -L 8080:localhost:8080 usuario@ip-del-vps
# Luego abre: http://localhost:8080/dashboard/
```

## Destruir el laboratorio

```bash
# Apagar y borrar volúmenes de todos los alumnos
for d in alumnos/*/; do
  docker compose -f "$d/docker-compose.yml" down -v
done

# Borrar carpetas generadas
rm -rf alumnos/

# Apagar Traefik (solo modo VPS/Cloud)
docker compose -f traefik/docker-compose.yml down -v
```
