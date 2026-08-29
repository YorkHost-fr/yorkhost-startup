#!/bin/bash
# =============================================================================
#  YorkHost - Script de demarrage DayZ
#  Resout la liste de mods, telecharge le Workshop, normalise la casse,
#  installe les cles BattlEye, puis lance le serveur.
#
#  Toute la logique de mods vit ici, PAS dans la startup command du panel.
#  Les variables de l'egg sont lues depuis l'environnement, il n'y a donc
#  aucune substitution {{VAR}} susceptible de se resoudre a vide.
# =============================================================================

set -o pipefail
cd /home/container || { echo "[YorkHost] /home/container introuvable"; exit 1; }
export HOME=/home/container

GAME_APPID=223350
WORKSHOP_APPID=221100
WORKSHOP_DIR="steamapps/workshop/content/${WORKSHOP_APPID}"
STEAMCMD="./steamcmd/steamcmd.sh"

C_INFO=$'\033[0;36m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[0;31m'; C_OK=$'\033[0;32m'; C_OFF=$'\033[0m'
log()  { echo "${C_INFO}[YorkHost]${C_OFF} $*"; }
ok()   { echo "${C_OK}[YorkHost]${C_OFF} $*"; }
warn() { echo "${C_WARN}[YorkHost]${C_OFF} $*"; }
err()  { echo "${C_ERR}[YorkHost]${C_OFF} $*"; }

# -----------------------------------------------------------------------------
# 0. Auto-mise a jour du script depuis BOOT_URL
#    Permet de corriger tout le parc sans reinstaller les instances.
#    Le remplacement n'a lieu que si le telechargement est non vide ET que
#    la syntaxe bash est valide, sinon on garde la version locale.
# -----------------------------------------------------------------------------
if [ -z "${YH_BOOT_SELFUPDATED}" ] && [ -n "${BOOT_URL}" ]; then
    _tmp=$(mktemp)
    if curl -fsSL --max-time 20 -o "${_tmp}" "${BOOT_URL}" 2>/dev/null \
       && [ -s "${_tmp}" ] && bash -n "${_tmp}" 2>/dev/null; then
        if ! cmp -s "${_tmp}" ./dayz-boot.sh; then
            install -m 755 "${_tmp}" ./dayz-boot.sh
            log "Script de demarrage mis a jour depuis ${BOOT_URL}"
        fi
        rm -f "${_tmp}"
        export YH_BOOT_SELFUPDATED=1
        exec bash ./dayz-boot.sh
    fi
    rm -f "${_tmp}"
    warn "Mise a jour du script de demarrage ignoree (telechargement ou syntaxe invalide)"
fi

# -----------------------------------------------------------------------------
# 1. Session Steam
# -----------------------------------------------------------------------------
STEAM_USER="${STEAM_USER:-anonymous}"
if [ "${STEAM_USER}" = "anonymous" ]; then
    LOGIN=(+login anonymous)
else
    LOGIN=(+login "${STEAM_USER}" "${STEAM_PASS}")
fi

if [ "${AUTO_UPDATE}" = "1" ]; then
    log "Verification des mises a jour du serveur (app ${GAME_APPID})..."
    VALIDATE_FLAG=""
    [ "${VALIDATE}" = "1" ] && VALIDATE_FLAG="validate"
    ${STEAMCMD} +force_install_dir /home/container "${LOGIN[@]}" \
        +app_update ${GAME_APPID} ${VALIDATE_FLAG} +quit \
        || warn "Mise a jour du serveur echouee, demarrage avec les fichiers existants"
else
    log "AUTO_UPDATE desactive, mise a jour du serveur ignoree"
fi

# -----------------------------------------------------------------------------
# 2. Outils de resolution de mods
# -----------------------------------------------------------------------------

# Normalise la casse d'un dossier de mod.
# Corrige le bug de l'ancien egg : les noms contenant des espaces etaient
# decoupes en plusieurs arguments par une boucle non quotee, d'ou les
# "mv: cannot stat 'BBP'" en cascade. Ici find -print0 + read -d '' + -depth.
normalize_case() {
    local dir="$1"
    local marker="${dir}/.yorkhost-lowercase"
    local item parent base lower count=0

    # Rien a faire si aucun fichier n'a change depuis le dernier passage.
    if [ -f "${marker}" ] && [ -z "$(find "${dir}" -newer "${marker}" -print -quit 2>/dev/null)" ]; then
        return 0
    fi

    while IFS= read -r -d '' item; do
        parent=$(dirname "${item}")
        base=$(basename "${item}")
        lower="${base,,}"
        [ "${base}" = "${lower}" ] && continue
        [ -e "${parent}/${lower}" ] && continue
        mv -T "${item}" "${parent}/${lower}" 2>/dev/null && count=$((count + 1))
    done < <(find "${dir}" -depth -mindepth 1 ! -name '.yorkhost-lowercase' -print0 2>/dev/null)

    touch "${marker}"
    [ "${count}" -gt 0 ] && log "  ${dir} : ${count} entree(s) passee(s) en minuscules"
    return 0
}

# Copie les cles BattlEye du mod vers keys/. Sans ca, BattlEye rejette les
# joueurs meme quand les mods sont correctement charges.
install_keys() {
    local dir="$1" n
    n=$(find "${dir}" -type f -iname '*.bikey' -print 2>/dev/null | wc -l)
    [ "${n}" -eq 0 ] && return 0
    find "${dir}" -type f -iname '*.bikey' -exec cp -f {} keys/ \; 2>/dev/null
    log "  ${dir} : ${n} cle(s) BattlEye installee(s)"
    return 0
}

# Decoupe une saisie utilisateur en entrees propres, sur stdout, une par ligne.
# Accepte "@123;456", "123, 456", des retours a la ligne, avec ou sans @.
split_entries() {
    printf '%s' "$1" \
        | tr ';,' '\n\n' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^@//' \
        | grep -v '^$'
}

# Resout une liste brute en liste prete pour -mod=, joignee par ';'.
# L'ORDRE DE SAISIE EST PRESERVE : DayZ exige que les frameworks (CF, Dabs)
# soient charges avant les mods qui en dependent. Ne jamais reconstruire
# cette liste depuis un find, qui renverrait un ordre arbitraire.
resolve_mods() {
    local raw="$1" label="$2"
    local -a declared=() ws_ids=() final=()
    local e x seen src dir

    while IFS= read -r e; do
        for x in "${declared[@]}"; do [ "${x}" = "${e}" ] && continue 2; done
        declared+=("${e}")
    done < <(split_entries "${raw}")

    # Repli sur le modlist.html exporte depuis le DayZ Launcher.
    if [ ${#declared[@]} -eq 0 ] && [ "${label}" = "mod" ] && [ -f modlist.html ]; then
        log "Aucun mod saisi dans le panel, lecture de modlist.html" >&2
        while IFS= read -r e; do
            for x in "${declared[@]}"; do [ "${x}" = "${e}" ] && continue 2; done
            declared+=("${e}")
        done < <(grep -oE 'filedetails/\?id=[0-9]+' modlist.html | grep -oE '[0-9]+')
    fi

    [ ${#declared[@]} -eq 0 ] && return 0

    for e in "${declared[@]}"; do
        [[ "${e}" =~ ^[0-9]+$ ]] && ws_ids+=("${e}")
    done

    # Telechargement Workshop en une seule session steamcmd.
    if [ ${#ws_ids[@]} -gt 0 ] && [ "${AUTO_UPDATE}" = "1" ]; then
        log "Telechargement / mise a jour de ${#ws_ids[@]} mod(s) Workshop..." >&2
        local -a args=(+force_install_dir /home/container "${LOGIN[@]}")
        for e in "${ws_ids[@]}"; do
            args+=(+workshop_download_item ${WORKSHOP_APPID} "${e}")
        done
        args+=(+quit)
        ${STEAMCMD} "${args[@]}" >&2 \
            || warn "steamcmd a signale une erreur, verification des mods deja presents" >&2
    fi

    mkdir -p keys

    for e in "${declared[@]}"; do
        if [[ "${e}" =~ ^[0-9]+$ ]]; then
            src="${WORKSHOP_DIR}/${e}"
            if [ ! -d "${src}" ]; then
                warn "${label} ${e} : absent du disque apres telechargement, ignore (ID invalide, mod prive ou supprime ?)" >&2
                continue
            fi
            normalize_case "${src}" >&2
            install_keys "${src}" >&2
            ln -sfn "${src}" "@${e}"
            final+=("@${e}")
        else
            dir=""
            [ -d "@${e}" ] && dir="@${e}"
            [ -z "${dir}" ] && [ -d "${e}" ] && dir="${e}"
            if [ -z "${dir}" ]; then
                warn "${label} '${e}' : aucun dossier correspondant a la racine, ignore" >&2
                continue
            fi
            normalize_case "${dir}" >&2
            install_keys "${dir}" >&2
            final+=("${dir}")
        fi
    done

    ( IFS=';'; printf '%s' "${final[*]}" )
}

# -----------------------------------------------------------------------------
# 3. Resolution
# -----------------------------------------------------------------------------
MODLIST=$(resolve_mods "${MODS}" "mod")
SERVERMODLIST=$(resolve_mods "${SERVER_MODS}" "serverMod")

if [ -n "${MODLIST}" ]; then
    ok "Mods actifs : ${MODLIST}"
else
    log "Aucun mod actif, demarrage en vanilla"
fi
[ -n "${SERVERMODLIST}" ] && ok "ServerMods actifs : ${SERVERMODLIST}"

# -----------------------------------------------------------------------------
# 4. Carte
#    Si MAP est vide, serverDZ.cfg n'est pas touche : le client garde la main.
# -----------------------------------------------------------------------------
CONFIG_FILE="${CONFIG_FILE:-serverDZ.cfg}"
if [ -n "${MAP}" ] && [ -f "${CONFIG_FILE}" ]; then
    TPL="dayzOffline.${MAP}"
    if [ ! -d "mpmissions/${TPL}" ]; then
        warn "Mission mpmissions/${TPL} absente, la carte risque de ne pas charger"
    fi
    if grep -qE '^[[:space:]]*template[[:space:]]*=' "${CONFIG_FILE}"; then
        sed -i -E "s|^([[:space:]]*)template[[:space:]]*=.*|\1template = \"${TPL}\";|" "${CONFIG_FILE}"
    else
        printf '\ntemplate = "%s";\n' "${TPL}" >> "${CONFIG_FILE}"
    fi
    log "Carte : ${TPL}"
fi

# -----------------------------------------------------------------------------
# 5. Lancement
# -----------------------------------------------------------------------------
mkdir -p profiles keys
chmod +x ./DayZServer 2>/dev/null

CMD=(./DayZServer
     -port="${SERVER_PORT}"
     -profiles=profiles
     -bepath=./
     -config="${CONFIG_FILE}"
     -dologs -adminlog -netlog -freezecheck)

# On n'ajoute -mod= que s'il y a quelque chose dedans : un -mod= vide est
# exactement le symptome qu'on cherche a ne plus jamais produire.
[ -n "${MODLIST}" ]       && CMD+=("-mod=${MODLIST}")
[ -n "${SERVERMODLIST}" ] && CMD+=("-serverMod=${SERVERMODLIST}")
[ -n "${EXTRA_ARGS}" ]    && CMD+=(${EXTRA_ARGS})

log "Commande de demarrage : ${CMD[*]}"
exec "${CMD[@]}"
