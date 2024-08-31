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
PURPOSE="Summarize coastal wave height forecasts from the national weather service"
VERSION="0.9"
UPDATED="25 Jan 2023"
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
 -A, --all      Show forecast wave heights for all locations
 -a             Show forecast wave heights for adjacent area(s)
 -f             Force refresh from nws data feed
 -H, --html      Output in html format
 -h, --help     Show usage and options
 --license      Print license info to the screen
 -N [anz code]  ANZ code for an adjacent offshore location
 -n [anz code]  ANZ code for the target offshore location
 -O [amz code]  AMZ code for an adjacent coastal location
 -o [amz code]  AMZ code for the target coastal location
 -r, --raw      Show raw NWS data for target coastal location
 -s [integer]   Assign maximum safe wave height
 -S             Toggle filter for days with specific wave heights
 -v, --version  Print version info
 -x, --offline  Use local files instead of nws data feed"

main()
{
    while getopts ":-:AafHhN:n:O:o:rSs:vx" opt; do
        case "$opt" in
            -) check_long_opts "${OPTARG}"; shift ;;
            A) SHOW_ONLY_SAFE=true MAX_SAFE_HEIGHT=99 SHOW_TODAY=true FORCE_REFRESH=true SHOW_ADJACENT=true ;;
            a) SHOW_ADJACENT=true ;;
            f) FORCE_REFRESH=true ;;
            H) output_html=true ;;
            h) show_help ;;
            N) coastal_adjacent="$OPTARG" FORCE_REFRESH=true ;;
            n) coastal_location="$OPTARG" FORCE_REFRESH=true ;;
            O) offshore_adjacent="$OPTARG" FORCE_REFRESH=true ;;
            o) offshore_location="$OPTARG" FORCE_REFRESH=true ;;
            r) get-raw-data "$coastal_location"; exit ;;
            s) MAX_SAFE_HEIGHT=$((OPTARG + 0)) FORCE_REFRESH=true ;;
            S) SHOW_ONLY_SAFE=true ;;
            v) show_version ;;
            x) is_offline=true FORCE_REFRESH=true ;;
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
        all) SHOW_ONLY_SAFE=true MAX_SAFE_HEIGHT=99 SHOW_TODAY=true FORCE_REFRESH=true SHOW_ADJACENT=true ;;
        html) output_html=true ;;
        license) show_license ;;
        offline) is_offline=true FORCE_REFRESH=true ;;
        raw) get-raw-data "$coastal_location"; exit ;;
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
    local period textin first second trend max
    period="$1"
    textin="$2"
    first="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft),.*/\1/p')"
    trend="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft), ([a-z ]+) to.*/\2/p')"
    second="$(echo -n "$textin" | $SED -nE 's/.* ([0-9]+ to [0-9]+ ft).*/\1/p')"
    around="$(echo -n "$textin" | $SED -nE 's/.*around ([0-9]+) ft.*/\1/p')"
    max="$(echo -n "$second" | $SED -nE 's/.*to ([0-9]+) ft.*/\1/p')"

    if [[ "$max" -le "$MAX_SAFE_HEIGHT" ]] || [ "$SHOW_ONLY_SAFE" = false ]; then
        if [[ -n "$first" ]]; then
            echo "$period: $first $trend to $second"
        elif [[ -n "$second" ]]; then
            echo "$period: $second"
        elif [[ -n "$around" ]]; then
            echo "$period: $around ft"
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
    local location_id prefix suffix=".txt"
    location_id="$(echo "$1" | awk '{print tolower($0)}')"
    if [[ "$location_id" =~ ^amz ]]; then
        prefix="coastal/am"
    elif [[ "$location_id" =~ ^anz ]]; then
        prefix="offshore/an"
    fi
    printf "%s/%s/%s%s" "$NWS_BASE_URL" "$prefix" "$location_id" "$suffix"
}

get-raw-data()
{
    local loc="$1"
    if [[ "$is_offline" = true ]]; then
        cat "$loc.txt"
    else
        curl -s "$(make-url "$loc")"
    fi
}

check-forecast() {
    local loc url istitle=false
    loc="$1"
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
    done <<< "$(get-raw-data "$loc")"
}

get-data() {
    printf "NWS Offshore Forecast\n\n"
    if [ "$SHOW_ADJACENT" = true ]; then
        check-forecast "$coastal_adjacent"
        check-forecast "$offshore_adjacent"
    fi
    check-forecast "$coastal_location"
    check-forecast "$offshore_location"
}

print_output() {
    local header footer of in file="$1"
    of="$(make-url "$offshore_location")"
    in="$(make-url "$coastal_location")"
    if [ "$output_html" = true ]; then
        header="<html><head><title>NWS Coastal/Offshore Forecast</title></head><body bgcolor='#333333' text='#D3D3D3'><pre>"
        footer="<a style='color:#D3D3D3' href=\"$in\">raw coastal text</a> - <a style='color:#D3D3D3' href=\"$of\">raw offshore text</a><pre></body></html>"
        echo "$header"
    fi
    if [ "$SHOW_TODAY" = true ]; then
        cat "$OUTPUT_FILE"
    else
        grep -Ev "TO|NIGHT" "$OUTPUT_FILE"
    fi
    echo
    echo "$footer"
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
    print_output "$OUTPUT_FILE"
}

main "$@"
