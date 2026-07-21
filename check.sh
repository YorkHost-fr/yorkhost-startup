#!/bin/bash
# Protection Alpine - YorkHost (Legacy + Enhanced BETA)
set -e
ALPINE_DIR="$(pwd)/alpine"
CFX_DIR="${ALPINE_DIR}/opt/cfx-server"
LIBSTDCPP="${ALPINE_DIR}/usr/lib/libstdc++.so.6"
LIBCORERT="${CFX_DIR}/libCoreRT.so"

# Loader musl : emplacement historique, fallback sur alpine/lib
LDMUSL="${CFX_DIR}/ld-musl-x86_64.so.1"
[ -s "$LDMUSL" ] || LDMUSL="${ALPINE_DIR}/lib/ld-musl-x86_64.so.1"

# Binaire serveur : cfx-server (Enhanced) ou FXServer (Legacy)
# En mode Enhanced on accepte les deux noms, Cfx.re n'ayant renomme que le .exe Windows pour l'instant
SERVER_BIN=""
if [ "${FIVEM_ENHANCED}" == "1" ]; then
  for C in "${CFX_DIR}/cfx-server" "${CFX_DIR}/FXServer"; do
    [ -s "$C" ] && SERVER_BIN="$C" && break
  done
else
  SERVER_BIN="${CFX_DIR}/FXServer"
fi

needs_reinstall=0
reason=""

# 1. Binaires/libs critiques presents et non vides
#    libCoreRT n'est verifie qu'en Legacy (runtime .NET different sur Enhanced)
if [ -z "$SERVER_BIN" ] || [ ! -s "$SERVER_BIN" ]; then
  needs_reinstall=1
  reason="binaire serveur manquant ou vide (${CFX_DIR})"
fi
if [ "$needs_reinstall" -eq 0 ]; then
  CRITICAL="$LIBSTDCPP $LDMUSL"
  [ "${FIVEM_ENHANCED}" != "1" ] && CRITICAL="$CRITICAL $LIBCORERT"
  for f in $CRITICAL; do
    if [ ! -s "$f" ]; then
      needs_reinstall=1
      reason="fichier manquant ou vide: $f"
      break
    fi
  done
fi

# 2. Verif format ELF 64-bit (detecte corruption / mauvaise arch)
if [ "$needs_reinstall" -eq 0 ]; then
  ELF_CHECK="$SERVER_BIN $LIBSTDCPP"
  [ "${FIVEM_ENHANCED}" != "1" ] && ELF_CHECK="$ELF_CHECK $LIBCORERT"
  for f in $ELF_CHECK; do
    # Magic ELF: 7f 45 4c 46 + classe 02 (64-bit)
    magic=$(head -c 5 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$magic" != "7f454c4602" ]; then
      needs_reinstall=1
      reason="format invalide (pas ELF64): $f"
      break
    fi
  done
fi

# 3. Smoke test : ld-musl arrive a charger le binaire ?
if [ "$needs_reinstall" -eq 0 ]; then
  test_out=$("$LDMUSL" \
    --library-path "${ALPINE_DIR}/usr/lib/v8/:${ALPINE_DIR}/lib/:${ALPINE_DIR}/usr/lib/" \
    -- "$SERVER_BIN" --version 2>&1 | head -50 || true)
  if echo "$test_out" | grep -qE "Exec format error|symbol not found|Error relocating|Error loading shared library"; then
    needs_reinstall=1
    reason="smoke test echoue (libs cassees)"
  fi
fi

# 4. Reinstall si besoin, depuis la bonne source selon le mode
if [ "$needs_reinstall" -eq 1 ]; then
  echo "[YorkHost] ⚠️  Alpine casse : ${reason}"
  echo "[YorkHost] Reinstallation des artifacts FiveM..."
  rm -rf "$ALPINE_DIR" fx.tar.xz

  if [ "${FIVEM_ENHANCED}" == "1" ]; then
    # Enhanced (BETA) : URL dynamique publiee sur la page server-download de Cfx.re
    # Extraction sans jq (pas garanti dans le conteneur de runtime), independante de l'ordre des cles JSON
    DOWNLOAD_LINK=$(curl -sSL https://docs.fivem.net/docs/server-download/ \
      | grep -o 'https://[^"]*cfx-server_linux_x64\.tar\.xz' | head -1)
  else
    DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server \
      | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  fi

  if [ -z "$DOWNLOAD_LINK" ]; then
    echo "[YorkHost] ❌ Impossible de recuperer l'URL du build serveur."
    exit 1
  fi
  echo "[YorkHost] Telechargement: ${DOWNLOAD_LINK}"
  if ! curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_LINK}" -o fx.tar.xz; then
    echo "[YorkHost] ❌ Telechargement echoue."
    rm -f fx.tar.xz
    exit 1
  fi
  # Verif integrite archive avant extraction (Legacy et Enhanced sont tous deux en .tar.xz)
  if ! xz -t fx.tar.xz 2>/dev/null; then
    echo "[YorkHost] ❌ Archive corrompue."
    rm -f fx.tar.xz
    exit 1
  fi
  tar xf fx.tar.xz
  rm -f fx.tar.xz
  # Le binaire doit etre executable apres extraction
  for C in "${CFX_DIR}/cfx-server" "${CFX_DIR}/FXServer"; do
    [ -f "$C" ] && chmod +x "$C"
  done
  echo "[YorkHost] ✅ Reinstall terminee."
fi
echo "[YorkHost] Lancement du serveur FiveM..."
