#!/bin/bash
#
# nws - summarize coastal waters forecasts from the national weather service
#
# author - Jed Record <jed.record@gmail.com>

SHOW_ONLY_SAFE=true
MAX_SAFE_HEIGHT=5
FORCE_REFRESH=false
SHOW_ADJACENT=false
SHOW_TODAY=false
OUTPUT_FILE="$HOME/.nwscache"
SED=sed

NEARSHORE_BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/marine/coastal/am"
OFFSHORE_BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/marine/offshore/an"
nearshore_location="154"
offshore_location="833"
nearshore_adjacent="152"
offshore_adjacent="830"
target_area="OCRACOKE"
adjacent_area="OREGON INLET"

NAME="nws"
PURPOSE="summarize coastal waters forecasts from the national weather service"
VERSION="0.9"
UPDATED="23 Jan 2023"
AUTHOR="Jed Record"
EMAIL="jed.record@gmail.com"
WEB="https://github.com/jedrecord/nws"
COPYRIGHT="Copyright (C) 2023 Jed Record
License: GNU General Public License, version 2
         <https://gnu.org/licenses/gpl-2.0.html>
This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
To see the full license text use the --license option."
USAGE="Usage: ${NAME} [OPTIONS]
Option          Meaning
 -a             Show data for adjacent area(s)
 -f             Force refresh from nws data feed
 -h, --help     Show usage and options
 --license      Print full program license to the screen
 -N [anz code]  ANZ code for an adjacent offshore location
 -n [anz code]  ANZ code for the target offshore location
 -O [amz code]  AMZ code for an adjacent nearshore location
 -o [amz code]  AMZ code for the target nearshore location
 -s [integer]   Assign maximum safe wave height
 -S             Toggle filter for days with specific wave heights
 -v, --version  Print version info"

main()
{
    while getopts ":-:afhN:n:O:o:rSs:v" opt; do
        case "$opt" in
            -) check_long_opts "${OPTARG}"; shift ;;
            a) SHOW_ADJACENT=true ;;
            f) FORCE_REFRESH=true ;;
            h) show_help ;;
            N) nearshore_adjacent=$((OPTARG + 0)); FORCE_REFRESH=true ;;
            n) nearshore_location=$((OPTARG + 0)); FORCE_REFRESH=true ;;
            O) offshore_adjacent=$((OPTARG + 0)); FORCE_REFRESH=true ;;
            o) offshore_location=$((OPTARG + 0)); FORCE_REFRESH=true ;;
            r) SHOW_ONLY_SAFE=true;MAX_SAFE_HEIGHT=99;SHOW_TODAY=true;FORCE_REFRESH=true;SHOW_ADJACENT=true ;;
            s) MAX_SAFE_HEIGHT=$((OPTARG + 0)); FORCE_REFRESH=true ;;
            S) SHOW_ONLY_SAFE=true ;;
            v) show_version ;;
           \?) show_error "\"-${OPTARG}\" is an invalid option" ;;
            :) show_error "The option \"-${OPTARG}\" requires an argumemt." ;;
        esac
    done
    shift $((OPTIND -1))

    # Run program
    forecast
}

check_long_opts(){
    local long_option="$1"
    case ${long_option} in
        license) show_license ;;
        version) show_version ;;
        help) show_help ;;
        *) show_error "\"--${long_option}\" is an invalid option" ;;
    esac
}
show_version(){
	echo "${NAME} version ${VERSION} (updated ${UPDATED})"
	echo "${COPYRIGHT}"
    echo
	echo "Contact: ${AUTHOR} <${EMAIL}>"
    echo "Website: ${WEB}"
	exit 0
}
show_help(){
	echo "${NAME} version ${VERSION} (updated ${UPDATED})"
    echo "${PURPOSE}"
	echo "${USAGE}"
    exit 0
}
show_error(){
    echo "$1" 1>&2
	echo "${NAME} version ${VERSION} (updated ${UPDATED})"
    echo "${PURPOSE}"
	echo "${USAGE}"
    exit 1
}
show_license(){
	echo "${NAME} version ${VERSION} (updated ${UPDATED})"
	echo "${COPYRIGHT}"
    echo
	echo "Contact: ${AUTHOR} <${EMAIL}>"
    echo "Website: ${WEB}"
	exit 0
}

get-nearshore-url() {
    local location_id="$1"
    local prefix="amz"
    local suffix=".txt"
    printf "%s/%s%s%s" $NEARSHORE_BASE_URL $prefix "$location_id" $suffix
}

get-offshore-url() {
    local location_id="$1"
    local prefix="anz"
    local suffix=".txt"
    printf "%s/%s%s%s" $OFFSHORE_BASE_URL $prefix "$location_id" $suffix
}

waves() {
    local period textin first second trend safe_height max
    period="$1"
    textin="$2"
    first="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft),.*/\1/p')"
    trend="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft), ([a-z ]+) to.*/\2/p')"
    second="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft).*/\1/p')"
    max="$(echo -n "$second" | $SED -nE 's/.*to ([0-9]+) ft.*/\1/p')"

    if [[ "$max" -le "$MAX_SAFE_HEIGHT" ]]; then
        safe_height=1
    fi

    if [[ $safe_height -eq 1 ]] || [ "$SHOW_ONLY_SAFE" = false ]; then
        if [[ -n "$first" ]]; then
            echo "$period: $first $trend to $second"
        elif [[ -n "$second" ]]; then
            echo "$period: $second"
        fi
    fi
}

check_forecast() {
local url="$1"
while read -r line; do
    seg=$(echo $line | $SED -nE 's/^\.([A-Z ]+).*/\1/p')
    if [[ -n "$seg" ]] && [[ "$seg" != "$prev" ]] || [[ "$line" =~ ^\$\$$ ]]; then
        waves "$prev" "$last"
        section="$seg: $line"
        prev="$seg"
    else
        section="$section $line"
    fi
    last="$section"
done <<< "$(curl -s "$url")"
}

get-data() {
    printf "NWS Offshore Forecast\n\n"
    if [ "$SHOW_ADJACENT" = true ]; then
        echo "$adjacent_area to 20 NM"
        check_forecast "$(get-nearshore-url $nearshore_adjacent)"
        echo
        echo "$adjacent_area to 100 NM"
        check_forecast "$(get-offshore-url $offshore_adjacent)"
        echo
    fi
    echo "$target_area to 20 NM"
    check_forecast "$(get-nearshore-url $nearshore_location)"
    echo
    echo "$target_area to 100 NM"
    check_forecast "$(get-offshore-url $offshore_location)"
}

forecast() {
    if [[ -f "$OUTPUT_FILE" ]]; then
        local now modtime lastchecked
        now=$(date +%s)
        modtime=$(date -r "$OUTPUT_FILE" +%s)
        lastchecked=$(( now - modtime ))
        if [[ $lastchecked -gt $(( 30 * 60 )) ]] || [ "$FORCE_REFRESH" = true ]; then
            get-data > "$OUTPUT_FILE"
        fi
    else
        get-data > "$OUTPUT_FILE"
    fi
    if [ "$SHOW_TODAY" = true ]; then
        cat "$OUTPUT_FILE"
    else
        cat "$OUTPUT_FILE" | grep -Ev "TO|NIGHT"
    fi
}

main "$@"
