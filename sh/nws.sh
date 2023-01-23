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

coastal_location="amz154"
offshore_location="anz833"
coastal_adjacent="amz152"
offshore_adjacent="anz830"
NWS_BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/marine"

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
 -O [amz code]  AMZ code for an adjacent coastal location
 -o [amz code]  AMZ code for the target coastal location
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
            N) coastal_adjacent="$OPTARG"; FORCE_REFRESH=true ;;
            n) coastal_location="$OPTARG"; FORCE_REFRESH=true ;;
            O) offshore_adjacent="$OPTARG"; FORCE_REFRESH=true ;;
            o) offshore_location="$OPTARG"; FORCE_REFRESH=true ;;
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

print-title()
{
    local location text
    location="$1"
    text="$2"
    case "$location" in 
        amz152) text="OREGON INLET COASTAL to 20 nm" ;;
        amz154) text="OCRACOKE COASTAL to 20 nm" ;;
        anz833) text="OCRACOKE OFFSHORE to 100 nm" ;;
        anz830) text="OREGON INLET OFFSHORE to 100 nm" ;;
    esac    
    echo "$text" | $SED 's/-$//'

}

make-url()
{
    local location_id prefix base_url suffix=".txt"
    location_id="$(echo "$1" | awk '{print tolower($0)}')"
    if [[ "$location_id" =~ ^amz ]]; then
        prefix="coastal/am"
        base_url="$COASTAL_BASE_URL"
    elif [[ "$location_id" =~ ^anz ]]; then
        prefix="offshore/an"
        base_url="$OFFSHORE_BASE_URL"
    fi
    printf "%s/%s/%s%s" "$NWS_BASE_URL" "$prefix" "$location_id" "$suffix"
}

check_forecast() {
    local loc url istitle=false
    loc="$1"
    url="$(make-url "$loc")"

    while read -r line; do
        if [[ "$line" =~ ^A[MN]Z[0-9]+\- ]]; then
            istitle=true
        elif [ "$istitle" = true ]; then
            print-title "$loc" "$line"
            istitle=false
        fi
        seg=$(echo "$line" | $SED -nE 's/^\.([A-Z ]+).*/\1/p')
        if [[ -n "$seg" ]] && [[ "$seg" != "$prev" ]] || [[ "$line" =~ ^\$\$$ ]]; then
            waves "$prev" "$last"
            section="$seg: $line"
            prev="$seg"
        else
            section="$section $line"
        fi
        last="$section"
        if [[ "$line" =~ ^\$\$$ ]]; then echo; fi
    done <<< "$(curl -s "$url")"
}

get-data() {
    printf "NWS Offshore Forecast\n\n"
    if [ "$SHOW_ADJACENT" = true ]; then
        check_forecast "$coastal_adjacent"
        check_forecast "$offshore_adjacent"
    fi
    check_forecast "$coastal_location"
    check_forecast "$offshore_location"
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
