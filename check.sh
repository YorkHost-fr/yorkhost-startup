#!/bin/bash

# 1. Vérification/Réinstallation des Artifacts (Ton code d'origine)
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  echo "Downloading: ${DOWNLOAD_LINK}"
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
  echo "** Artifacts reinstalled."
fi

# 2. --- PROTECTION YORKHOST ANTI-BACKDOOR ---
echo "[YorkHost] Scan de sécurité des ressources en cours..."

# On définit la signature de la backdoor (la clé XOR 81 et le nom de variable spécifique)
# On cherche dans le répertoire courant (.) en excluant le dossier 'alpine' pour gagner du temps
BAD_FILES=$(grep -rE "kmkwvjrsvur|dmkwvjrsvsh|pmkwvjrsveqr" . --exclude-dir=alpine --include="*.js" -l)

if [ ! -z "$BAD_FILES" ]; then
  echo " "
  echo "############################################################"
  echo "⚠️  ALERTE SÉCURITÉ YORKHOST"
  echo "Une backdoor (malware) a été détectée dans vos fichiers JS !"
  echo "Fichiers infectés trouvés :"
  echo "$BAD_FILES"
  echo " "
  echo "CONSEIL : Supprimez ces fichiers ou nettoyez le code suspect."
  echo "Par sécurité, le démarrage est interrompu."
  echo "############################################################"
  
  # Optionnel : Bloquer le démarrage pour forcer le client à nettoyer
  exit 1 
fi

# 3. --- VERROUILLAGE DES CONFIGS ---
# On s'assure que si un server.cfg existe, on tente de limiter les écritures sauvages
if [ -f "server.cfg" ]; then
    chmod 644 server.cfg
    echo "[YorkHost] Permissions server.cfg vérifiées."
fi

echo "[YorkHost] Scan terminé. Démarrage du serveur..."
