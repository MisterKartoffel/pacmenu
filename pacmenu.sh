#!/usr/bin/env bash

trap 'exit_handler' INT TERM
trap 'cleanup' EXIT

function usage() {
cat << EOF
pacmenu - An opinionated fzf-powered menu for Pacman

    Project URL:
    Author: Felipe Duarte <felipesdrs@hotmail.com>

    Usage: pacmenu.sh [OPTIONS]

    Options:
        -h          Help: show this help message.

    Menu actions:
        Ctrl-s      Cycle between menus.
        Tab         Select current item.
        Enter       Submit selection.
EOF
}

function exit_handler() {
    trap - INT TERM
    cleanup
    exit 1
}

function cleanup() {
    rm -f "${FILES[@]}" 2>/dev/null

    pkill -P $$ 2>/dev/null || true
    wait 2>/dev/null || true
}

function check_depends() {
    if ! command -v "${DEPENDS[@]}" >/dev/null; then
        echo "${COMMAND} is missing. Exiting."
        exit 1
    fi
}

function split_list() {
    declare -a INSTALLED REPOS AUR || exit 1

    while read -r REPO PACKAGE VERSION OPTIONAL; do
        if [[ "${OPTIONAL}" == *"[installed]"* ]]; then
            INSTALLED+=("${REPO} ${PACKAGE} ${VERSION}")
        else
            [[ "${REPO}" == "aur" ]] && \
                AUR+=("${PACKAGE} ${VERSION}") || \
                REPOS+=("${REPO} ${PACKAGE} ${VERSION}")
        fi
    done

    printf '%s\n' "${REPOS[@]}" > "${FILES[repos]}"
    printf '%s\n' "${AUR[@]}" > "${FILES[aur]}" &
    printf '%s\n' "${INSTALLED[@]}" > "${FILES[installed]}" &
}

declare -i START_MODE=0 || exit 1

declare -A FILES=(
    [installed]="/tmp/pac_installed.txt"
    [repos]="/tmp/pac_repos.txt"
    [aur]="/tmp/pac_aur.txt"
    [mode]="/tmp/pac_mode.txt"
) || exit 1

declare -a PACKAGES || exit 1
declare -a DEPENDS=(fzf paru)
declare -a FZF_ARGS=(
    --no-mouse
    --multi
    --sync
    --reverse
    --info="inline-right"
    --border="rounded"
    --border-label="⎸ pacman ⎹"
    --prompt=": "
    --input-border="rounded"
    --input-label="⎸ [core] and [extra] ⎹"
    --list-border="rounded"
    --list-label=""
    --preview=""
    --preview-label=""
    --preview-border="rounded"
    --footer-label="⎸ Selected packages ⎹"
    --footer-border="rounded"
    --bind="change:first"
    --bind="start:transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )"
    --bind="ctrl-s:reload(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0) cat /tmp/pac_repos.txt ;;
                    1) cat /tmp/pac_aur.txt ;;
                    2) cat /tmp/pac_installed.txt ;;
                esac
            )+transform-input-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0) echo \"⎸ AUR ⎹\" ;;
                    1) echo \"⎸ Uninstall ⎹\" ;;
                    2) echo \"⎸ [core] and [extra] ⎹\" ;;
                esac
                MODE=\$(( (MODE + 1) % 3 ))
                echo \$MODE > /tmp/pac_mode.txt
            )"
    --bind="result:transform-list-label(
                [[ -n \$FZF_QUERY ]] && \\
                    echo \"⎸ \$FZF_MATCH_COUNT matches for '\$FZF_QUERY' ⎹\" || \\
                    echo \"\"
            )"
    --bind="multi:transform-footer(
                if [[ \$FZF_SELECT_COUNT -ge 1 ]]; then
                    [[ \$(<\"/tmp/pac_mode.txt\") == 2 ]] && COLOR=\$(tput setaf 1)
                    printf '%s%s\n' \"\$COLOR\" {+}
                fi
            )"
    --bind="load:transform-preview-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0|2) echo \"⎸ {2} ⎹\" ;;
                    1) echo \"⎸ {1} ⎹\" ;;
                esac
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0) paru -Si {2} ;;
                    1) paru -Si {1} ;;
                    2) paru -Qi {2} ;;
                esac
            )"
    --bind="focus:transform-preview-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0|2) echo \"⎸ {2} ⎹\" ;;
                    1) echo \"⎸ {1} ⎹\" ;;
                esac
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    0) paru -Si {2} ;;
                    1) paru -Si {1} ;;
                    2) paru -Qi {2} ;;
                esac
            )"
    --color="info:#4C4F69,spinner:#4C4F69,border:#FAB387,label:#FAB387,
            prompt:#89B4FA,hl:#A6E3A1,hl+:#A6E3A1,input-border:#A6E3A1,
            input-label:#A6E3A1,footer-border:#4C4F69,footer-label:#4C4F69,
            footer-fg:#89B4FA,list-border:#CDD6F4,list-label:#CDD6F4,
            marker:#A6E3A1,preview-border:#89B4FA,preview-label:#89B4FA"
) || exit 1

function main() {
    declare OPT
    while getopts "h" OPT; do
        case "${OPT}" in
            h) usage; exit 0;;
            *) usage >&2; exit 1;;
        esac
    done

    check_depends
    split_list < <(paru -Sl)

    echo "${START_MODE}" > "${FILES[mode]}" &

    mapfile -t SELECTION < <(fzf "${FZF_ARGS[@]}" < "${FILES[repos]}") || exit 1
    [[ -z "${SELECTION[*]}" ]] && echo "No packages selected." && exit 0

    case "$(<"${FILES[mode]}")" in
        0)
            PACKAGES=("${SELECTION[@]#* }")
            PACKAGES=("${PACKAGES[@]%% *}")
            paru -S "${PACKAGES[@]}"
            ;;

        1)
            PACKAGES=("${SELECTION[@]%% *}")
            paru -S "${PACKAGES[@]}"
            ;;

        2)
            PACKAGES=("${SELECTION[@]#* }")
            PACKAGES=("${PACKAGES[@]%% *}")
            paru -Rns "${PACKAGES[@]}"
            ;;

        *)
            echo "ERROR: Unknown mode ${MODE}."
            exit 1
            ;;
    esac
}

main "${@}"
