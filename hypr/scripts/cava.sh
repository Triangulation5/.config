#!/bin/bash

bars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")

timeout 0.2s cava -p ~/.config/cava/config | {
    read -r line

    output=""
    IFS=';' read -ra values <<< "$line"

    for value in "${values[@]}"; do
        [[ -z "$value" ]] && continue
        output+="${bars[$value]}"
    done

    echo "$output"
}
