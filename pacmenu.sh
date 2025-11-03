#!/usr/bin/env bash
#
# TODO: issuing a reload() while streaming in input
# causes list parsing to stop, debug

trap 'exit_handler' INT TERM
trap 'cleanup' EXIT

function usage() {
cat << EOF
pacmenu - An opinionated fzf-powered menu for Pacman

    ${ANSI[bold]}Project URL:${ANSI[reset]} ${ANSI[italic]}https://github.com/MisterKartoffel/pacmenu${ANSI[reset]}
    ${ANSI[bold]}Author:${ANSI[reset]} Felipe Duarte ${ANSI[italic]}<felipesdrs@hotmail.com>${ANSI[reset]}

    ${ANSI[bold]}Usage: pacmenu.sh${ANSI[reset]} [OPTIONS]

    ${ANSI[bold]}Options:${ANSI[reset]}
        ${ANSI[bold]}-p, --package-manager${ANSI[reset]} [paru|yay]
                select alternative package manager to use, enabling the aur menu if applicable.

        ${ANSI[bold]}-s, --start-mode${ANSI[reset]} [repos|aur|uninstall]
                allows starting from any of the three available menus.

        ${ANSI[bold]}-r, --reinstall${ANSI[reset]}
                shows installed packages in the install menus with the "[installed]" tag.

        ${ANSI[bold]}-h, --help${ANSI[reset]}
                show this help message.

    ${ANSI[bold]}Menu actions:${ANSI[reset]}
        ${ANSI[bold]}Ctrl-s${ANSI[reset]}      Cycle between menus.
        ${ANSI[bold]}Tab${ANSI[reset]}         Select current item.
        ${ANSI[bold]}Enter${ANSI[reset]}       Submit selection.
EOF
}

function exit_handler() {
    trap - INT TERM
    cleanup
    exit 1
}

function cleanup() {
    rm -f "${FILES[@]}" 2>/dev/null

    pkill -P "${FZF_PID}" 2>/dev/null || true
    pkill -P "${$}" 2>/dev/null || true
    wait 2>/dev/null || true
}

function arg_error() {
    declare TYPE="${1}"
    declare OPTION="${2}"
    declare ARGUMENT="${3}"
    declare COMMENT="${4}"

    case "${TYPE}" in
        option)
            printf "%s: invalid option -- '%s'\n%s\n" \
                "${PROGRAM_NAME}" \
                "${OPTION}" \
                "${COMMENT}" ;;

        argument)
            printf "%s: invalid argument for '%s' -- '%s'\n%s\n" \
                "${PROGRAM_NAME}" \
                "${OPTION}" \
                "${ARGUMENT}" \
                "${COMMENT}" ;;

        *) exit 1 ;;
    esac
}

function check_depends() {
    for COMMAND in "${DEPENDS[@]}"; do
        if ! command -v "${COMMAND}" >/dev/null; then
            echo "${COMMAND} is missing. Exiting."
            exit 1
        fi
    done
}

function populate_lists() {
    declare REPO PACKAGE VERSION INSTALLED || exit 1
    declare -a TARGETS FORMATS || exit 1
    exec 3>"${FILES[pipe]}" || exit 1

    while read -r REPO PACKAGE VERSION INSTALLED; do
        FORMATS[1]="${COLORS[gray]}${REPO} ${COLORS[white]}${PACKAGE} ${COLORS[gray]}${VERSION}"
        FORMATS[0]="${FORMATS[1]} ${INSTALLED}"

        [[ "${REPO}" == "aur" ]] && TARGETS[0]="${FILES[aur]}"       || TARGETS[0]="${FILES[repos]}"
        [[ -n "${INSTALLED}" ]]  && TARGETS[1]="${FILES[uninstall]}" || TARGETS[1]="/dev/null"
                                    TARGETS[2]="${FILES[pipe]}"

        [[ -z "${REINSTALL}" && -n "${INSTALLED}" ]] \
                                 && TARGETS[0]="/dev/null" \
                                 && TARGETS[2]="/dev/null"

        for i in "${!TARGETS[@]}"; do
            [[ "${TARGETS[i]}" == "${FILES["${START_MODE}"]}" ]] && FORMATS[2]="${FORMATS[i]}"
            printf "%b\n" "${FORMATS[i]}" >> "${TARGETS[i]}"
        done

        TARGETS=()
    done

    exec 3>&-
}

declare PKG_MANAGER="pacman" || exit 1
declare START_MODE="repos" || exit 1
declare PROGRAM_NAME="pacmenu" || exit 1
declare REINSTALL WRITER_PID || exit 1

declare -A FILES=(
    [uninstall]="/tmp/pac_uninstall.txt"
    [repos]="/tmp/pac_repos.txt"
    [aur]="/tmp/pac_aur.txt"
    [mode]="/tmp/pac_mode.txt"
    [pipe]="/tmp/pac_pipe"
    [selection]="/tmp/pac_selection.txt"
) || exit 1

declare -A ANSI=(
    [gray]="$(tput setaf 0)"
    [bold]="$(tput bold)"
    [italic]="$(tput sitm)"
    [reset]="$(tput sgr0)"
) || exit 1

declare -a PACKAGES || exit 1
declare -a DEPENDS=(fzf) || exit 1
declare -a FZF_ARGS=(
    --no-mouse
    --multi
    --ansi
    --reverse
    --prompt=": "
    --info="inline-right"
    --border="rounded"
    --border-label="⎸ pacman ⎹"
    --input-border="rounded"
    --input-label=""
    --list-border="rounded"
    --list-label=""
    --preview=""
    --preview-border="rounded"
    --preview-label=""
    --preview-window="right,60%"
    --footer-label="⎸ Selected packages ⎹"
    --footer-border="rounded"
    --bind="change:first"
    --bind="start:bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+bg-transform-input-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    repos) echo \"⎸ [core] and [extra] ⎹\" ;;
                    aur) echo \"⎸ AUR ⎹\" ;;
                    uninstall) echo \"⎸ Uninstall ⎹\" ;;
                esac
            )"
    --bind="load:bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$PKG_MANAGER -Qi {2} || \\
                    \$PKG_MANAGER -Si {2}
            )"
    --bind="ctrl-s:transform-input-label(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                case \$MODE in
                    repos)
                        if [[ \$PKG_MANAGER != \"pacman\" ]]; then
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
    --bind="result:bg-transform-list-label(
                [[ -n \$FZF_QUERY ]] && \\
                    echo \"⎸ \$FZF_MATCH_COUNT matches for '\$FZF_QUERY' ⎹\" || \\
                    echo \"\"
            )"
    --bind="multi:bg-transform-footer(
                if [[ \$FZF_SELECT_COUNT -ge 1 ]]; then
                    MODE=\$(<\"/tmp/pac_mode.txt\")
                    [[ \$MODE == \"uninstall\" ]] && COLOR=\$(tput setaf 1)
                    printf \"\$COLOR%s\n\" {+}
                fi
            )"
    --bind="focus:bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+preview(
                MODE=\$(<\"/tmp/pac_mode.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$PKG_MANAGER -Qi {2} || \\
                    \$PKG_MANAGER -Si {2}
            )"
    --color="prompt:#89B4FA,info:#4C4F69,spinner:#4C4F69,border:#FAB387,marker:#A6E3A1,
            label:#FAB387,input-label:#A6E3A1,list-label:#CDD6F4,preview-label:#89B4FA,footer-label:#4C4F69,
            input-border:#A6E3A1,list-border:#CDD6F4,preview-border:#89B4FA, footer-border:#4C4F69,
            hl:#A6E3A1,hl+:#A6E3A1,footer-fg:#89B4FA"
) || exit 1

function main() {
    declare -a SELECTION PACKAGES

    while [[ "${#}" -gt 0 ]]; do
        case "${1}" in
            -p|--package-manager)
                case "${2}" in
                    paru|yay)
                        PKG_MANAGER="${2}"
                        DEPENDS+=("${PKG_MANAGER}")
                        shift 2 ;;

                    *)
                        arg_error "argument" "${1}" "${2}"
                        usage >&2
                        exit 1 ;;
                esac ;;

            -s|--start-mode)
                case "${2}" in
                    aur)
                        if [[ "${PKG_MANAGER}" == "pacman" ]]; then
                            arg_error "argument" "${1}" "${2}" "(choose an aur-compatible package manager for aur mode)\n"
                            usage >&2
                            exit 1
                        fi ;&

                    repos|uninstall)
                        START_MODE="${2}"
                        shift 2 ;;

                    *)
                        arg_error "argument" "${1}" "${2}"
                        usage >&2
                        exit 1 ;;
                esac ;;

            -r|--reinstall)
                REINSTALL=1
                shift ;;

            -h|--help)
                usage
                exit 0 ;;

            *)
                arg_error "option" "${1}" "${2}"
                usage >&2
                exit 1 ;;
        esac
    done

    check_depends

    export PKG_MANAGER
    mkfifo "${FILES[pipe]}"
    echo "${START_MODE}" > "${FILES[mode]}"

    fzf "${FZF_ARGS[@]}" < "${FILES[pipe]}" > "${FILES[selection]}" &
    FZF_PID="${!}"

    populate_lists < <("${PKG_MANAGER}" -Sl)
    wait "${FZF_PID}" || true

    mapfile -t SELECTION < "${FILES[selection]}"
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
