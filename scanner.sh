#!/bin/bash

# Chemin Wisp spécifique
SCAN_DIR="/home/wisp/daemon-data"
LOG_FILE="/root/backdoor_report.log"

echo "=== Début du scan anti-backdoor : $(date) ===" | tee -a $LOG_FILE

# On cherche récursivement dans tous les sous-dossiers UUID
find "$SCAN_DIR" -type f -name "yarn_builder.js" | while read -r file; do
    
    # On extrait l'UUID du dossier pour savoir quel serveur est touché
    SERVER_UUID=$(echo "$file" | cut -d'/' -f5)
    
    # Analyse du contenu pour les patterns d'obfuscation que tu as donnés
    # On cherche : kmn + constante, dmn + boucle, ou les longues listes de nombres
    MATCH=$(grep -E "const kmn|function dmn|[0-9]{2,3},[0-9]{2,3},[0-9]{2,3}" "$file")

    if [ ! -z "$MATCH" ]; then
        echo -e "\n[!!!] DANGER sur le serveur : $SERVER_UUID" | tee -a $LOG_FILE
        echo "Fichier : $file" | tee -a $LOG_FILE
        
        # Extraction de la constante pour confirmer l'infection
        CONSTANTE=$(grep -oE "const kmn[a-z]+=[0-9]+" "$file" | head -n 1)
        echo "Type d'infection : Obfuscation détectée ($CONSTANTE)" | tee -a $LOG_FILE
        
        # ACTION : On retire les droits d'exécution et de lecture (Quarantaine)
        chmod 000 "$file"
        echo "Action : Mis en quarantaine (chmod 000)" | tee -a $LOG_FILE
    fi
done

echo -e "\n=== Scan terminé ===" | tee -a $LOG_FILE
echo "Rapport disponible dans : $LOG_FILE"

