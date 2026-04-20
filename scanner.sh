#!/bin/bash
# Chemin Wisp spécifique
SCAN_DIR="/home/wisp/daemon-data"
LOG_FILE="/root/backdoor_report.log"

echo "=== Début du scan anti-backdoor : $(date) ===" | tee -a $LOG_FILE

# On cherche récursivement dans tous les sous-dossiers UUID
find "$SCAN_DIR" -type f -name "yarn_builder.js" | while read -r file; do
    
    # On extrait l'UUID du dossier pour savoir quel serveur est touché
    SERVER_UUID=$(echo "$file" | cut -d'/' -f5)
    
    # Analyse du contenu pour les patterns d'obfuscation
    MATCH=$(grep -E "const kmn|function dmn|[0-9]{2,3},[0-9]{2,3},[0-9]{2,3}" "$file")

    if [ ! -z "$MATCH" ]; then
        echo -e "\n[!!!] DANGER sur le serveur : $SERVER_UUID" | tee -a $LOG_FILE
        echo "Fichier : $file" | tee -a $LOG_FILE
        
        # Extraction de la constante pour confirmer l'infection
        CONSTANTE=$(grep -oE "const kmn[a-z]+=[0-9]+" "$file" | head -n 1)
        echo "Type d'infection : Obfuscation détectée ($CONSTANTE)" | tee -a $LOG_FILE
        
        # ACTION 1 : Stopper le conteneur Docker associé au serveur
        # On cherche le conteneur qui contient l'UUID dans son nom (compatible WISP/Pterodactyl)
        CONTAINER_ID=$(docker ps -q --filter "name=$SERVER_UUID")
        
        if [ ! -z "$CONTAINER_ID" ]; then
            echo "Conteneur Docker trouvé : $CONTAINER_ID" | tee -a $LOG_FILE
            docker stop "$CONTAINER_ID" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "Action : Conteneur stoppé avec succès" | tee -a $LOG_FILE
            else
                echo "[WARN] Échec du stop du conteneur $CONTAINER_ID" | tee -a $LOG_FILE
            fi
        else
            echo "[INFO] Aucun conteneur Docker actif trouvé pour $SERVER_UUID" | tee -a $LOG_FILE
        fi
        
        # ACTION 2 : On retire les droits (Quarantaine du fichier)
        chmod 000 "$file"
        echo "Action : Fichier mis en quarantaine (chmod 000)" | tee -a $LOG_FILE
    fi
done

echo -e "\n=== Scan terminé ===" | tee -a $LOG_FILE
echo "Rapport disponible dans : $LOG_FILE"
