#!/bin/bash

FILES=("main.cpp" "mtpool.hpp" "run.sh")
PORT=2222

DEPS=(mktemp socat inotifywait stty sha1sum sleep stat base64 ip rm echo)
if ! which "${DEPS[@]}" > /dev/null 2>&1; then
    echo "-- Please install: ${DEPS[@]}" >&2
    exit 1
fi

ADDR=$(ip route get 1 | awk '{print $7;exit}')
echo -e "\033[32m-- Execute the following command on your mobile (under same WLAN):\033[0m\n\033[33;1m"
if [ "x${#FILES}" != "x0" ]; then
    FILE_PORT=$[PORT+1]
    echo "socat SHELL:bash,stderr,pty,setsid TCP:$ADDR:$PORT&socat SHELL:sh TCP:$ADDR:$FILE_PORT&wait"
else
    echo "socat SHELL:bash,stderr,pty,setsid TCP:$ADDR:$PORT"
fi
echo -e "\033[0m"

if [ "x${#FILES}" != "x0" ]; then
    TMP="$(mktemp -d)"
    TMPLOCK="$(mktemp)"
    dt=1
    waitable=false
    ((while [ -f "$TMPLOCK" ]; do
        if [ $dt -lt 30 ]; then
            dt=$[dt+1]
        fi
        if $waitable; then
            inotifywait -t$dt -qq "${FILES[@]}" -e create -e move_self -e close_write > /dev/null 2>&1 || continue
        fi
        dt=2
        waitable=true
        for file in "${FILES[@]}"; do
            while ! test -f "$file"; do
                sleep 0.01
                test -f "$file" && break
                sleep 0.02
                test -f "$file" && break
                sleep 0.04
                test -f "$file" && break
                sleep 0.08
                test -f "$file" && break
                inotifywait -t1 -qq . -e create -e move_self -e close_write > /dev/null 2>&1
            done
            sleep 0.02
            shafile="$TMP/$(echo "$file" | sha1sum | cut -d' ' -f1).sha1"
            sha="$(sha1sum "$file" | cut -d' ' -f1)"
            same=false
            [ -f "$shafile" ] && [ "x$sha" == "x$(cat "$shafile")" ] && same=true
            echo "$sha" > "$shafile"
            if $same; then
                continue
            fi
            echo -n -e "\033[32m[$file]\033[0m\r\n" >&2
            echo "base64 -d>'$file'<<@EOF@"
            base64 < "$file"
            echo "@EOF@"
            echo "chmod $(stat -c "%a" "$file") '$file'"
        done
    done; echo exit) | socat STDIO TCP-LISTEN:$FILE_PORT) &
fi
stty -icanon -echo raw
socat STDIO TCP-LISTEN:$PORT
stty icanon echo -raw
if [ "x${#FILES}" != "x0" ]; then
    rm -f "$TMPLOCK"
    wait
fi
