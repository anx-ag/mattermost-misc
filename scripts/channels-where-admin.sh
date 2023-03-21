#!/bin/bash

TOKEN="<yourtoken>"
USER="<the_user_to_check>"
TEAM="<yourteam>"
URL="https://<yourdomain>"

for channel in $(curl -sX GET -H "Authorization: Token $TOKEN" "$URL/api/v4/users/$USER/teams/$TEAM/channels/members" | jq -r '.[] | select (.roles == "channel_user channel_admin") | .channel_id'); do curl -sX GET -H "Authorization: Token $TOKEN" "$URL/api/v4/channels/$channel" | jq -r .name; done
