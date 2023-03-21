# List only active users
 mmctl --local user list --all --json 2>/dev/null | jq -r '.[] | select (.delete_at ==0) | .username'
