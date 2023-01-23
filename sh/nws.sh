#!/bin/bash

raw=0
if [[ "$1" == "--raw" ]]; then
    raw=1
fi

SHOW_ONLY_SAFE=1
MAX_SAFE_HEIGHT=5
FORCE_REFRESH=0
SHOW_OREGON_INLET=1
SHOW_TODAY=0
OUTPUT_FILE="$HOME/.nwscache"
SED=sed

if [[ "$1" == "-f" ]]; then
    FORCE_REFRESH=1
fi
if [[ "$1" == "-o" ]]; then
    SHOW_OREGON_INLET=1
fi
if [[ "$1" == "-S" ]]; then
    SHOW_ONLY_SAFE=0
fi
if [[ "$1" == "-s" ]]; then
    if [[ -n "$2" ]]; then
        height="$2"
        MAX_SAFE_HEIGHT=$((height + 0))
        FORCE_REFRESH=1
    fi
fi

if [[ "$1" == "--raw" ]]; then
    SHOW_ONLY_SAFE=0
    MAX_SAFE_HEIGHT=99
    SHOW_OREGON_INLET=1
    SHOW_TODAY=1
    FORCE_REFRESH=1
fi

NEARSHORE_BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/marine/coastal/am"
OFFSHORE_BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/marine/offshore/an"
ocracoke="154"
ocracoke20="833"
oregoninlet="152"
oregoninlet20="830"

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

    if [[ $safe_height -eq 1 ]] || [[ $SHOW_ONLY_SAFE -eq 0 ]]; then
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
    printf "NC Offshore Forecast\n\n"
    if [[ $SHOW_OREGON_INLET -eq 1 ]]; then
        echo "OREGON INLET to 20 NM"
        check_forecast "$(get-nearshore-url $oregoninlet)"
        echo
        echo "OREGON INLET to 100 NM"
        check_forecast "$(get-offshore-url $oregoninlet20)"
        echo
    fi
    echo "OCRACOKE to 20 NM"
    check_forecast "$(get-nearshore-url $ocracoke)"
    echo
    echo "OCRACOKE to 100 NM"
    check_forecast "$(get-offshore-url $ocracoke20)"
}

main() {
    if [[ -f "$OUTPUT_FILE" ]]; then
        local now modtime lastchecked
        now=$(date +%s)
        modtime=$(date -r "$OUTPUT_FILE" +%s)
        lastchecked=$(( now - modtime ))
        if [[ $lastchecked -gt $(( 30 * 60 )) ]] || [[ $FORCE_REFRESH -eq 1 ]]; then
            get-data > "$OUTPUT_FILE"
        fi
    else
        get-data > "$OUTPUT_FILE"
    fi
    if [[ $SHOW_TODAY -eq 1 ]]; then
        cat "$OUTPUT_FILE"
    else
        cat "$OUTPUT_FILE" | grep -Ev "TO|NIGHT"
    fi
}

main

