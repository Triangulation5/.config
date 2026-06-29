#!/bin/bash

bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")

cava -p ~/.config/cava/config | while read -r line; do
    output=""
    IFS=';' read -ra values <<< "$line"

    for value in "${values[@]}"; do
        [[ -z "$value" ]] && continue
        output+="${bars[$value]}"
    done

    echo "$output"
done
