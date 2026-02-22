#!/bin/bash

USER_DB="/etc/v2ray/utilisateurs.json"
CONFIG="/etc/v2ray/config.json"

TODAY=$(date +%Y-%m-%d)

if [[ ! -f "$USER_DB" ]]; then
    exit 0
fi

uuids_expire=$(jq -r --arg today "$TODAY" '.[] | select(.expire < $today) | .uuid' "$USER_DB")

if [[ -z "$(echo "$uuids_expire" | tr -d '[:space:]')" ]]; then
    exit 0
fi

tmpfile=$(mktemp)

jq --argjson uuids "$(echo "$uuids_expire" | jq -R -s -c 'split("\n")[:-1]')" '
.inbounds |= map(
    if .protocol=="vless" then
        .settings.clients |= map(select(.id as $id | $uuids | index($id) | not))
    else .
    end
)
' "$CONFIG" > "$tmpfile"

mv "$tmpfile" "$CONFIG"
systemctl restart v2ray

jq --arg today "$TODAY" '[.[] | select(.expire >= $today)]' "$USER_DB" > "$USER_DB"
