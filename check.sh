#!/bin/bash
# Protection Alpine - YorkHost
set -e

ALPINE_DIR="$(pwd)/alpine"
FXSERVER="${ALPINE_DIR}/opt/cfx-server/FXServer"
LIBSTDCPP="${ALPINE_DIR}/usr/lib/libstdc++.so.6"
LIBCORERT="${ALPINE_DIR}/opt/cfx-server/libCoreRT.so"
LDMUSL="${ALPINE_DIR}/opt/cfx-server/ld-musl-x86_64.so.1"

needs_reinstall=0
reason=""

# 1. Binaires/libs critiques présents et exécutables
for f in "$FXSERVER" "$LIBSTDCPP" "$LIBCORERT" "$LDMUSL"; do
  if [ ! -s "$f" ]; then
    needs_reinstall=1
    reason="fichier manquant ou vide: $f"
    break
  fi
done

# 2. Vérif format ELF 64-bit (détecte corruption / mauvaise arch)
if [ "$needs_reinstall" -eq 0 ]; then
  for f in "$FXSERVER" "$LIBSTDCPP" "$LIBCORERT"; do
    # Magic ELF: 7f 45 4c 46 + classe 02 (64-bit)
    magic=$(head -c 5 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$magic" != "7f454c4602" ]; then
      needs_reinstall=1
      reason="format invalide (pas ELF64): $f"
      break
    fi
  done
fi

# 3. Smoke test : ld-musl arrive à charger FXServer ?
if [ "$needs_reinstall" -eq 0 ]; then
  test_out=$("$LDMUSL" \
    --library-path "${ALPINE_DIR}/usr/lib/v8/:${ALPINE_DIR}/lib/:${ALPINE_DIR}/usr/lib/" \
    -- "$FXSERVER" --version 2>&1 | head -50 || true)
  if echo "$test_out" | grep -qE "Exec format error|symbol not found|Error relocating|Error loading shared library"; then
    needs_reinstall=1
    reason="smoke test échoué (libs cassées)"
  fi
fi

# 4. Réinstall si besoin
if [ "$needs_reinstall" -eq 1 ]; then
  echo "[YorkHost] ⚠️  Alpine cassé : ${reason}"
  echo "[YorkHost] Réinstallation des artifacts FiveM..."
  rm -rf "$ALPINE_DIR" fx.tar.xz

  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server \
    | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$DOWNLOAD_LINK" ]; then
    echo "[YorkHost] ❌ Impossible de récupérer l'URL du build FXServer."
    exit 1
  fi

  echo "[YorkHost] Téléchargement: ${DOWNLOAD_LINK}"
  if ! curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_LINK}" -o fx.tar.xz; then
    echo "[YorkHost] ❌ Téléchargement échoué."
    rm -f fx.tar.xz
    exit 1
  fi

  # Vérif intégrité archive avant extraction
  if ! xz -t fx.tar.xz 2>/dev/null; then
    echo "[YorkHost] ❌ Archive corrompue."
    rm -f fx.tar.xz
    exit 1
  fi

  tar xf fx.tar.xz
  rm -f fx.tar.xz
  echo "[YorkHost] ✅ Réinstall terminée."
fi

echo "[YorkHost] Lancement de FXServer..."
