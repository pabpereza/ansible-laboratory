#!/usr/bin/env bash
# Sincroniza el workspace del control01 (alumno01) en practica/ y lo sube a GitHub.
# Lo lanza a diario el timer systemd de usuario "sync-practica.timer".
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/alumnos/alumno01/workspace/"
DST="$REPO_DIR/practica/"

cd "$REPO_DIR"

# Traer cambios remotos antes de commitear para no divergir
git pull --rebase --autostash -q

rsync -a --delete \
  --filter='P .gitignore' \
  --exclude='.vault_pass' \
  --exclude='*.retry' \
  --exclude='credentials/' \
  "$SRC" "$DST"

git add -A practica

if git diff --cached --quiet; then
  echo "Sin cambios en practica/"
  exit 0
fi

git -c user.name="pabpereza" -c user.email="pabloperezaradros@gmail.com" \
  commit -q -m "practica: estado del workspace $(TZ=Europe/Madrid date +%F)"
git push -q
echo "Subido: $(git log -1 --oneline)"
