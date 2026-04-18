#!/bin/bash

# 1. Vérification/Réinstallation des Artifacts (Origine)
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
fi

# 2. --- PROTECTION YORKHOST AVEC BRIDAGE (RATE LIMIT) ---
echo "[YorkHost] Scan de sécurité des ressources..."

# Recherche des signatures malveillantes
BAD_FILES=$(grep -rE "kmkwvjrsvur|dmkwvjrsvsh|pmkwvjrsveqr" . --exclude-dir=alpine --include="*.js" -l)

if [ ! -z "$BAD_FILES" ]; then
  echo -e "\e[31m############################################################\e[0m"
  echo -e "\e[31m⚠️  ALERTE SÉCURITÉ YORKHOST : BACKDOOR DÉTECTÉE\e[0m"
  echo "Fichier : $BAD_FILES"
  echo " "
  echo -e "\e[33mSÉCURITÉ : Votre serveur est bridé à 10Mbps pour éviter l'exfiltration.\e[0m"
  echo -e "\e[31m############################################################\e[0m"

  # --- APPLICATION DU RATE LIMIT (10Mbps) ---
  # On utilise 'tc' pour limiter le trafic sortant sur l'interface principale (souvent eth0)
  if command -v tc &> /dev/null; then
    # On nettoie d'éventuelles anciennes règles pour éviter les erreurs
    sudo tc qdisc del dev eth0 root 2>/dev/null
    
    # On limite à 10Mbit avec un burst de 32kbit pour la stabilité
    sudo tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms 2>/dev/null
    
    echo "[YorkHost] Bridage réseau 10Mbps activé avec succès."
  else
    # Si 'tc' n'est pas dispo, on replie sur un blocage DNS Discord pour la sécurité
    sudo iptables -A OUTPUT -p tcp -d discord.com -j REJECT 2>/dev/null
    echo "[YorkHost] 'tc' non trouvé. Blocage Discord activé par défaut."
  fi
else
  # Si aucune backdoor n'est trouvée, on s'assure que le serveur n'est PAS bridé
  if command -v tc &> /dev/null; then
    sudo tc qdisc del dev eth0 root 2>/dev/null
  fi
  echo "[YorkHost] Analyse terminée : Aucun malware détecté."
fi

# 3. --- PERMISSIONS ---
if [ -f "server.cfg" ]; then
    chmod 644 server.cfg
fi

echo "[YorkHost] Lancement du serveur FXServer..."
