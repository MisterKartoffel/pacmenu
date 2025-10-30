#!/usr/bin/env bash

trap 'exit_handler' INT TERM
trap 'cleanup' EXIT

function usage() {
cat << EOF
pacmenu - An opinionated fzf-powered menu for Pacman

    Project URL: https://github.com/MisterKartoffel/pacmenu
    Author: Felipe Duarte <felipesdrs@hotmail.com>

    Usage: pacmenu.sh [OPTIONS]

    Options:
        -p          Package manager: selects a package manager to use,
                        enabling the aur menu if applicable.
        -s [MENU]   Start mode: allows starting from any of the three
                        available menus - repos, aur, uninstall.
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
    for COMMAND in "${DEPENDS[@]}"; do
        if ! command -v "${COMMAND}" >/dev/null; then
            echo "${COMMAND} is missing. Exiting."
            exit 1
        fi
    done
}

function split_list() {
    declare -a INSTALLED REPOS AUR || exit 1
    declare LIST_FORMAT REPO PACKAGE VERSION OPTIONAL

    while read -r REPO PACKAGE VERSION OPTIONAL; do
        LIST_FORMAT="${COLORS[gray]}${REPO} ${COLORS[white]}${PACKAGE} ${COLORS[gray]}${VERSION}"
        if [[ "${OPTIONAL}" == *"[installed]"* ]]; then
            INSTALLED+=("${LIST_FORMAT}")
        else
            [[ "${REPO}" == "aur" ]] && \
                AUR+=("${LIST_FORMAT}") || \
                REPOS+=("${LIST_FORMAT}")
        fi
    done

    printf '%s\n' "${REPOS[@]}" > "${FILES[repos]}"
    printf '%s\n' "${AUR[@]}" > "${FILES[aur]}"
    printf '%s\n' "${INSTALLED[@]}" > "${FILES[uninstall]}"
}

declare -A FILES=(
    [uninstall]="/tmp/pac_uninstall.txt"
    [repos]="/tmp/pac_repos.txt"
    [aur]="/tmp/pac_aur.txt"
    [mode]="/tmp/pac_mode.txt"
    [manager]="/tmp/pac_manager.txt"
) || exit 1

declare -A COLORS=(
    [white]=$(tput setaf 15)
    [gray]=$(tput setaf 0)
)

declare -a PACKAGES || exit 1
declare -a DEPENDS=(fzf)
declare -a FZF_ARGS=(
    --no-mouse
    --multi
    --sync
    --ansi
    --reverse
    --info="inline-right"
    --border="rounded"
    --border-label="⎸ pacman ⎹"
    --prompt=": "
    --input-border="rounded"
    --input-label=""
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
            )+transform-input-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    repos) echo \"⎸ [core] and [extra] ⎹\" ;;
                    aur) echo \"⎸ AUR ⎹\" ;;
                    uninstall) echo \"⎸ Uninstall ⎹\" ;;
                esac
            )"
    --bind="ctrl-s:transform-input-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    repos)
                        if [[ \$(<\"/tmp/pac_manager.txt\") != \"pacman\" ]]; then
                            MODE=\"aur\"
                            echo \"⎸ AUR ⎹\"
                        else
                            MODE=\"uninstall\"
                            echo \"⎸ Uninstall ⎹\"
                        fi
                    ;;

                    aur)
                        MODE=\"uninstall\"
                        echo \"⎸ Uninstall ⎹\"
                    ;;

                    uninstall)
                        MODE=\"repos\"
                        echo \"⎸ [core] and [extra] ⎹\"
                    ;;
                esac
                echo \$MODE > /tmp/pac_mode.txt
            )+reload(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    repos) cat /tmp/pac_repos.txt ;;
                    aur) cat /tmp/pac_aur.txt ;;
                    uninstall) cat /tmp/pac_uninstall.txt ;;
                esac
            )"
    --bind="result:transform-list-label(
                [[ -n \$FZF_QUERY ]] && \\
                    echo \"⎸ \$FZF_MATCH_COUNT matches for '\$FZF_QUERY' ⎹\" || \\
                    echo \"\"
            )"
    --bind="multi:transform-footer(
                if [[ \$FZF_SELECT_COUNT -ge 1 ]]; then
                    MODE=\$(<\"/tmp/pac_mode.txt\")
                    [[ \$MODE == \"uninstall\" ]] && \\
                        COLOR=\$(tput setaf 1)
                    printf \"\$COLOR%s\n\" {+}
                fi
            )"
    --bind="load:transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                PKG_MANAGER=\$(<\"/tmp/pac_manager.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$PKG_MANAGER -Qi {2} || \\
                    \$PKG_MANAGER -Si {2}
            )"
    --bind="focus:transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                PKG_MANAGER=\$(<\"/tmp/pac_manager.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$PKG_MANAGER -Qi {2} || \\
                    \$PKG_MANAGER -Si {2}
            )"
    --color="info:#4C4F69,spinner:#4C4F69,border:#FAB387,label:#FAB387,
            prompt:#89B4FA,hl:#A6E3A1,hl+:#A6E3A1,input-border:#A6E3A1,
            input-label:#A6E3A1,footer-border:#4C4F69,footer-label:#4C4F69,
            footer-fg:#89B4FA,list-border:#CDD6F4,list-label:#CDD6F4,
            marker:#A6E3A1,preview-border:#89B4FA,preview-label:#89B4FA"
) || exit 1

declare PKG_MANAGER="pacman" || exit 1
declare START_MODE="repos" || exit 1

function main() {
    declare -a SELECTION PACKAGES
    declare OPT OPTARG OPTIND
    while getopts "p:s:h" OPT; do
        case "${OPT}" in
            p)
                case "${OPTARG}" in
                    paru|yay)
                        PKG_MANAGER="${OPTARG}"
                        DEPENDS+=("${PKG_MANAGER}")
                        ;;

                    *)
                        echo "[ERROR] Invalid package manager ${OPTARG}"
                        usage >&2
                        exit 1
                        ;;
                esac
                ;;

            s)
                case "${OPTARG}" in
                    aur)
                        if [[ "${PKG_MANAGER}" == "pacman" ]]; then
                            echo "[ERROR] Invalid mode ${OPTARG} with package manager ${PKG_MANAGER}"
                            usage >&2
                            exit 1
                        fi
                        ;&

                    repos|uninstall)
                        START_MODE="${OPTARG}"
                        ;;

                    *)
                        echo "[ERROR] Invalid mode ${OPTARG}"
                        usage >&2
                        exit 1
                        ;;
                esac
                ;;

            h)
                usage
                exit 0
                ;;

            *)
                usage >&2
                exit 1
                ;;
        esac
    done

    check_depends
    split_list < <(${PKG_MANAGER} -Sl)

    echo "${PKG_MANAGER}" > "${FILES[manager]}" &
    echo "${START_MODE}" > "${FILES[mode]}" &

    mapfile -t SELECTION < <(fzf "${FZF_ARGS[@]}" < "${FILES["${START_MODE}"]}") || exit 1
    [[ -z "${SELECTION[*]}" ]] && echo "No packages selected." && exit 0

    PACKAGES=("${SELECTION[@]#* }")
    PACKAGES=("${PACKAGES[@]%% *}")

    case "$(<"${FILES[mode]}")" in
        repos|aur)
            "${PKG_MANAGER}" -S "${PACKAGES[@]}"
            ;;

        uninstall)
            "${PKG_MANAGER}" -Rns "${PACKAGES[@]}"
            ;;

        *)
            echo "ERROR: Unknown mode ${MODE}."
            exit 1
            ;;
    esac
}

main "${@}"
