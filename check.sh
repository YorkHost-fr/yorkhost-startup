#!/bin/bash

# --- CONFIGURATION ---
INTERFACE="eth0" # L'interface réseau par défaut dans Docker
LIMIT="10mbit"   # La limite de débit

# 1. Protection contre la suppression accidentelle d'Alpine (Ton code)
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
fi

# 2. --- SCAN DE SÉCURITÉ ---
echo "[YorkHost] Scan de sécurité des ressources en cours..."
BAD_FILES=$(grep -rE "kmkwvjrsvur|dmkwvjrsvsh|pmkwvjrsveqr" . --exclude-dir=alpine --include="*.js" -l)

if [ ! -z "$BAD_FILES" ]; then
  echo -e "\e[31m"
  echo "############################################################"
  echo "⚠️  ALERTE SÉCURITÉ YORKHOST"
  echo "Une backdoor a été détectée dans vos fichiers :"
  echo "$BAD_FILES"
  echo "------------------------------------------------------------"
  echo "ACTION : Pour protéger vos clés et nos infrastructures,"
  echo "votre serveur est bridé à 10Mbps pour cette session."
  echo "############################################################"
  echo -e "\e[0m"

  # --- APPLICATION DU BRIDAGE (RATE LIMIT) ---
  # On essaye d'installer tc (iproute2) si absent (spécifique Alpine/Docker)
  if ! command -v tc &> /dev/null; then
    apk add iproute2 &>/dev/null
  fi

  if command -v tc &> /dev/null; then
    # Nettoyage d'une ancienne règle
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    # Ajout de la limite à 10Mbps
    sudo tc qdisc add dev $INTERFACE root tbf rate $LIMIT burst 32kbit latency 400ms 2>/dev/null
    
    if [ $? -eq 0 ]; then
      echo "[YorkHost] Limitation réseau 10Mbps activée."
    else
      # Si tc échoue (permissions Docker), on bloque au moins Discord
      echo "[YorkHost] Erreur permission réseau. Blocage DNS Discord de secours."
      sudo iptables -A OUTPUT -p tcp -d discord.com -j REJECT 2>/dev/null
    fi
  fi
else
  # Si le serveur est propre, on s'assure qu'il n'y a pas de reste de bridage
  if command -v tc &> /dev/null; then
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
  fi
  echo "[YorkHost] Aucun malware détecté. Connexion illimitée."
fi

# 3. Finalisation
if [ -f "server.cfg" ]; then
    chmod 644 server.cfg
fi

echo "[YorkHost] Scan terminé. Lancement de FXServer..."
# PAS de "exit 1" ici, donc le serveur démarrera toujours.
