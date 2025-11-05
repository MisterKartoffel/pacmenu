#!/usr/bin/env bash

trap 'exit_handler' INT TERM
trap 'cleanup' EXIT

declare AUTH MANAGER REINSTALL WRITER_PID
declare TMP_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID}}/pac" || exit 1
declare START_MODE="repos" || exit 1

declare -A FILES=(
    [uninstall]="${TMP_DIR}/uninstall.txt"
    [repos]="${TMP_DIR}/repos.txt"
    [aur]="${TMP_DIR}/aur.txt"
    [mode]="${TMP_DIR}/mode.txt"
) || exit 1

declare -A ANSI=(
    [gray]="$(tput setaf 0)"
    [bold]="$(tput bold)"
    [italic]="$(tput sitm)"
    [underline]="$(tput smul)"
    [reset]="$(tput sgr0)"
) || exit 1

declare -A FLAGS=(
    [sync]="-S"
    [remove]="-Rns"
) || exit 1

declare -a DEPENDS=(fzf tail tput pkill) || exit 1
declare -a SETUID=(sudo doas run0) || exit 1
declare -a MANAGERS=(paru yay pacman) || exit 1
declare -a FZF_ARGS=(
    --multi
    --ansi
    --reverse
    --info="inline-right"
    --border="rounded"
    --border-label="⎸ pacman ⎹"
    --input-border="rounded"
    --list-border="rounded"
    --preview-border="rounded"
    --preview-window="right,60%"
    --footer-label="⎸ selected packages ⎹"
    --footer-border="rounded"
    --bind="change:first"
    --bind="start:bg-transform-prompt(
                echo \"loading : \"
            )+bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+bg-transform-input-label(
                case \$START_MODE in
                    repos) echo \"⎸ [core] and [extra] ⎹\" ;;
                    aur) echo \"⎸ aur ⎹\" ;;
                    uninstall) echo \"⎸ uninstall ⎹\" ;;
                esac
            )+reload(
                case \$START_MODE in
                    repos) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/repos.txt ;;
                    aur) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/aur.txt ;;
                    uninstall) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/uninstall.txt ;;
                esac
            )"
    --bind="load:bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+bg-transform-prompt(
                echo \": \"
            )+preview(
                MODE=\$(<\"\$TMP_DIR/mode.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$MANAGER -Qi {2} || \\
                    \$MANAGER -Si {2}
            )"
    --bind="ctrl-s:transform-input-label(
                MODE=\$(<\"\$TMP_DIR/mode.txt\")
                case \$MODE in
                    repos)
                        if [[ \$MANAGER != \"pacman\" ]]; then
                            MODE=\"aur\"
                            echo \"⎸ aur ⎹\"
                        else
                            MODE=\"uninstall\"
                            echo \"⎸ uninstall ⎹\"
                        fi
                    ;;

                    aur)
                        MODE=\"uninstall\"
                        echo \"⎸ uninstall ⎹\"
                    ;;

                    uninstall)
                        MODE=\"repos\"
                        echo \"⎸ [core] and [extra] ⎹\"
                    ;;
                esac
                echo \$MODE > \$TMP_DIR/mode.txt
            )+reload(
                MODE=\$(<\"\$TMP_DIR/mode.txt\")
                case \$MODE in
                    repos) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/repos.txt ;;
                    aur) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/aur.txt ;;
                    uninstall) tail -F --lines=+0 --pid=\$WRITER_PID \$TMP_DIR/uninstall.txt ;;
                esac
            )"
    --bind="result:bg-transform-list-label(
                [[ -n \$FZF_QUERY ]] && \\
                    echo \"⎸ \$FZF_MATCH_COUNT matches for '\$FZF_QUERY' ⎹\" || \\
                    echo \"\"
            )"
    --bind="multi:bg-transform-footer(
                if [[ \$FZF_SELECT_COUNT -ge 1 ]]; then
                    MODE=\$(<\"\$TMP_DIR/mode.txt\")
                    [[ \$MODE == \"uninstall\" ]] && COLOR=\$(tput setaf 1)
                    printf \"\$COLOR%s\n\" {+}
                fi
            )"
    --bind="focus:bg-transform-preview-label(
                echo \"⎸ {2} ⎹\"
            )+preview(
                MODE=\$(<\"\$TMP_DIR/mode.txt\")
                [[ \$MODE == \"uninstall\" ]] && \\
                    \$MANAGER -Qi {2} || \\
                    \$MANAGER -Si {2}
            )"
    --color="prompt:#89B4FA,info:#4C4F69,spinner:#4C4F69,border:#FAB387,marker:#A6E3A1,
            label:#FAB387,input-label:#A6E3A1,list-label:#CDD6F4,preview-label:#89B4FA,footer-label:#4C4F69,
            input-border:#A6E3A1,list-border:#CDD6F4,preview-border:#89B4FA,footer-border:#4C4F69,
            hl:#A6E3A1,hl+:#A6E3A1,footer-fg:#89B4FA"
) || exit 1

function usage() {
echo "pacmenu - An opinionated fzf-powered menu for Pacman

    ${ANSI[bold]}Project URL:${ANSI[reset]} ${ANSI[italic]}https://github.com/MisterKartoffel/pacmenu${ANSI[reset]}
    ${ANSI[bold]}Author:${ANSI[reset]} Felipe Duarte ${ANSI[italic]}<felipesdrs@hotmail.com>${ANSI[reset]}

    ${ANSI[bold]}Usage: pacmenu.sh${ANSI[reset]} [OPTIONS]

    ${ANSI[bold]}Options:${ANSI[reset]}

        ${ANSI[bold]}-a, --auth${ANSI[reset]} [sudo|doas|run0]
                choose which privilege escalation program to run when running the operation.

        ${ANSI[bold]}-p, --package-manager${ANSI[reset]} [paru|yay]
                select alternative package manager to use, enabling the aur menu if applicable.

        ${ANSI[bold]}-s, --start-mode${ANSI[reset]} [repos|aur|uninstall]
                allows starting from any of the three available menus.

        ${ANSI[bold]}-i, --install-flags${ANSI[reset]} ${ANSI[italic]}<default: -S>${ANSI[reset]}
                set additional flags for pacman's sync operation.

        ${ANSI[bold]}-u, --uninstall-flags${ANSI[reset]} ${ANSI[italic]}<default: -Rns>${ANSI[reset]}
                set additional flags for pacman's remove operation.

        ${ANSI[bold]}-r, --reinstall${ANSI[reset]}
                shows installed packages in the install menus with the [installed] tag.

        ${ANSI[bold]}-h, --help${ANSI[reset]}
                show this help message.

    ${ANSI[bold]}Menu actions:${ANSI[reset]}
        ${ANSI[bold]}Ctrl-s${ANSI[reset]}      Cycle between menus.
        ${ANSI[bold]}Tab${ANSI[reset]}         Select current item.
        ${ANSI[bold]}Enter${ANSI[reset]}       Submit selection."
}

function exit_handler() {
    trap - INT TERM
    cleanup
    exit 1
}

function cleanup() {
    rm -f "${FILES[@]}" 2>/dev/null
    rmdir "${TMP_DIR}" 2>/dev/null

    pkill -P "${$}" 2>/dev/null || true
    wait 2>/dev/null || true
}

function print_error() {
    declare PROGRAM_NAME="pacmenu"
    declare TYPE="${1}"
    declare CAUSE="${2}"
    declare ARGUMENT="${3}"

    case "${TYPE}" in
        option)
            printf "%s: invalid option -- '%s'\n" \
                "${PROGRAM_NAME}" \
                "${CAUSE}" ;;

        argument)
            printf "%s: invalid argument for '%s' -- '%s'\n" \
                "${PROGRAM_NAME}" \
                "${CAUSE}" \
                "${ARGUMENT}" ;;

        dependency)
            printf "%s: dependency '%s' not satisfied\n" \
                "${PROGRAM_NAME}" \
                "${CAUSE}" ;;

        *) exit 1 ;;
    esac

    usage >&2
    exit 1
}

function check_opt_depends() {
    declare COMMAND
    declare -n OPT_DEPENDS="${1}" || exit 1

    for COMMAND in "${OPT_DEPENDS[@]}"; do
        if command -v "${COMMAND}" >/dev/null; then
            echo "${COMMAND}"
            return 0
        fi
    done

    print_error "dependency" "${1}"
}

function check_depends() {
    declare COMMAND

    for COMMAND in "${DEPENDS[@]}"; do
        if ! command -v "${COMMAND}" >/dev/null; then
            print_error "dependency" "${COMMAND}"
        fi
    done
}

function source_packages() {
    declare REPO PACKAGE VERSION INSTALLED
    declare -a TARGETS FORMATS || exit 1

    while read -r REPO PACKAGE VERSION INSTALLED; do
        FORMATS[1]="${ANSI[gray]}${REPO}${ANSI[reset]} ${PACKAGE} ${ANSI[gray]}${VERSION}"
        FORMATS[0]="${FORMATS[1]} ${INSTALLED}"

        [[ "${REPO}" == "aur" ]] && TARGETS[0]="${FILES[aur]}"       || TARGETS[0]="${FILES[repos]}"
        [[ -n "${INSTALLED}" ]]  && TARGETS[1]="${FILES[uninstall]}" || TARGETS[1]="/dev/null"
        [[ -z "${REINSTALL}" && -n "${INSTALLED}" ]] && TARGETS[0]="/dev/null"

        for i in "${!TARGETS[@]}"; do
            printf "%b\n" "${FORMATS[i]}" >> "${TARGETS[i]}"
        done
    done < <("${MANAGER}" -Sl)
}

function parse_arguments() {
    while [[ "${#}" -gt 0 ]]; do
        case "${1}" in
            -a|--auth)
                case "${2}" in
                    sudo|doas|run0)
                        AUTH="${2}"
                        DEPENDS+=("${AUTH}")
                        shift 2 ;;

                    *) print_error "argument" "${1}" "${2}" ;;
                esac ;;

            -p|--package-manager)
                case "${2}" in
                    paru|yay)
                        MANAGER="${2}"
                        DEPENDS+=("${MANAGER}")
                        shift 2 ;;

                    *) print_error "argument" "${1}" "${2}" ;;
                esac ;;

            -s|--start-mode)
                case "${2}" in
                    aur) [[ "${MANAGER}" == "pacman" ]] && print_error "argument" "${1}" "${2}" ;&

                    repos|uninstall)
                        START_MODE="${2}"
                        shift 2 ;;

                    *) print_error "argument" "${1}" "${2}" ;;
                esac ;;

            -i|--install-flags)
                FLAGS[sync]="-S${2}"
                shift 2 ;;

            -u|--uninstall-flags)
                FLAGS[remove]="-R${2}"
                shift 2 ;;

            -r|--reinstall)
                REINSTALL=1
                shift ;;

            -h|--help)
                usage
                exit 0 ;;

            *) print_error "option" "${1}" "${2}" ;;
        esac
    done
}

function main() {
    declare PROCESS
    declare -a SELECTION PACKAGES || exit 1


    check_depends

    [[ -z "${MANAGER}" ]]                          && MANAGER="$(check_opt_depends MANAGERS)"
    [[ -z "${AUTH}" && "${MANAGER}" == "pacman" ]] && AUTH="$(check_opt_depends SETUID)"

    export MANAGER START_MODE TMP_DIR
    [[ -d "${TMP_DIR}" ]] || mkdir "${TMP_DIR}"
    echo "${START_MODE}" > "${FILES[mode]}"

    source_packages &
    WRITER_PID="${!}"
    export WRITER_PID

    while [[ ! -f "${FILES["${START_MODE}"]}" ]]; do true; done
    mapfile -t SELECTION < <(fzf "${FZF_ARGS[@]}")

    [[ -z "${SELECTION[*]}" ]] && echo "No packages selected." && exit 0
    PACKAGES=("${SELECTION[@]#* }")
    PACKAGES=("${PACKAGES[@]%% *}")

    case "$(<"${FILES[mode]}")" in
        aur) unset "${AUTH}" ;&
        repos) PROCESS="sync" ;;
        uninstall) PROCESS="remove" ;;

        *)
            printf "pacmenu: Unknown mode -- '%s'\n" "${MODE}"
            exit 1 ;;
    esac

    "${AUTH}" "${MANAGER}" "${FLAGS["${PROCESS}"]}" "${PACKAGES[@]}"
}

main "${@}"
