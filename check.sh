#!/bin/bash

# --- CONFIGURATION ---
INTERFACE="eth0"
LIMIT="10mbit"
TXA_CONFIG="txData/default/config.json"
SCAN_TARGETS="." # Par défaut on scanne la racine

# 1. Extraction du DataPath de txAdmin pour un scan précis
if [ -f "$TXA_CONFIG" ]; then
    # On utilise grep et sed pour extraire la valeur de "dataPath" proprement
    DATAPATH=$(grep -o '"dataPath"[[:space:]]*:[[:space:]]*"[^"]*"' "$TXA_CONFIG" | cut -d'"' -f4)
    
    if [ ! -z "$DATAPATH" ] && [ -d "$DATAPATH" ]; then
        echo "[YorkHost] txAdmin DataPath détecté : $DATAPATH"
        SCAN_TARGETS=". $DATAPATH"
    fi
fi

# 2. Protection Alpine (Ton code)
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
fi

# 3. --- SCAN DE SÉCURITÉ ---
echo "[YorkHost] Scan de sécurité approfondi en cours..."
# On scanne la racine ET le dossier de données txAdmin
BAD_FILES=$(grep -rE "kmkwvjrsvur|dmkwvjrsvsh|pmkwvjrsveqr" $SCAN_TARGETS --exclude-dir=alpine --include="*.js" -l 2>/dev/null)

if [ ! -z "$BAD_FILES" ]; then
  echo -e "\e[31m"
  echo "############################################################"
  echo "⚠️  ALERTE SÉCURITÉ YORKHOST"
  echo "Une backdoor a été détectée dans vos fichiers :"
  echo "$BAD_FILES" | sort | uniq
  echo "------------------------------------------------------------"
  echo "ACTION : Limitation réseau 10Mbps appliquée."
  echo "############################################################"
  echo -e "\e[0m"

  if ! command -v tc &> /dev/null; then apk add iproute2 &>/dev/null; fi

  if command -v tc &> /dev/null; then
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    sudo tc qdisc add dev $INTERFACE root tbf rate $LIMIT burst 32kbit latency 400ms 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "[YorkHost] Limitation réseau 10Mbps activée."
    else
      echo "[YorkHost] Erreur permission. Blocage DNS Discord actif."
      sudo iptables -A OUTPUT -p tcp -d discord.com -j REJECT 2>/dev/null
    fi
  fi
else
  if command -v tc &> /dev/null; then sudo tc qdisc del dev $INTERFACE root 2>/dev/null; fi
  echo "[YorkHost] Aucun malware détecté dans les répertoires scannés."
fi

# 4. Finalisation
# On essaye de sécuriser le server.cfg partout où on le trouve
find $SCAN_TARGETS -maxdepth 2 -name "server.cfg" -exec chmod 644 {} \; 2>/dev/null

echo "[YorkHost] Scan terminé. Lancement de FXServer..."
