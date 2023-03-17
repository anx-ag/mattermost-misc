#!/bin/bash
#
# bulk user creation based on a CSV input file
# Employee Name;Employee ID;Email ID;Designation

# set to "generate" in order to create a different password for every user
PASSWORD="test123test123"
CSVFILE="test.csv"
CSVDELIM=","

# specify the name of your sysadmin account, if left blank, the script will try to find an admin
SYSADMIN=""

# specify a user access token for $SYSADMIN here, if left blank, the script will try to create a token
TOKEN=""

# override path to mmctl here (if installed outside $PATH)
MMCTLPATH="mmctl"

# leave empty if the script should try to autodetect it
MMURL=""

# do not change anything below this line

die()
{
  echo $*
  exit 1
}

# some sanity checks
jq --version >/dev/null 2>&1 || die "jq not found"
curl --version >/dev/null 2>&1 || die "curl not found"
makepasswd -v >/dev/null 2>&1 || die "makepasswd not found"
if $MMCTLPATH --local system version >/dev/null 2>&1; then
  MMCTL="$MMCTLPATH --local"
else
  if $MMCTLPATH system version >/dev/null 2>&1; then
    MMCTL="$MMCTLPATH"
  else
    die "Cannot establish connection with mmctl"
  fi
fi
MMCTL="$MMCTL --suppress-warnings"

# if the URL is empty, read it out of the system configuration
[ "$MMURL" = "" ] && MMURL="$($MMCTL config show | jq -r .ServiceSettings.SiteURL)"

# find one sysadmin account if not specified in the config
[ "$SYSADMIN" = "" ] && SYSADMIN="$($MMCTL user list --all --json 2>/dev/null | jq -r '.[] | select (.roles == "system_admin system_user") | .username' | head -1)"

# create a temporary token for this account if not specified in the config
if [ "$TOKEN" = "" ]; then
  UATSETTING=$($MMCTL config get ServiceSettings.EnableUserAccessTokens)

  # if tokens are not enabled, we need to enable them temporarily
  [ "$UATSETTING" = "false" ] && $MMCTL config set ServiceSettings.EnableUserAccessTokens true > /dev/null 2>&1

  # verify and die if not set properly
  [ "$($MMCTL config get ServiceSettings.EnableUserAccessTokens)" = "false" ] && die "Could not activate user tokens"

  TOKEN="$($MMCTL token generate "$SYSADMIN" bulkcreatetemp 2>/dev/null | awk "-F:" '{ print $1 }')"
  [ "$TOKEN" = "" ] && die "Error creating token"
fi

[ "$(curl -sX GET -H "Authorization: Token $TOKEN" "$MMURL/api/v4/users/me")" = "api.context.session_expired.app_error" ] && die "user access token is not working."


FIRST=0;
# read the file line by line
while read line; do
  # skip first line (contains headers)
  [ "$FIRST" = "0" ] && FIRST=1 && continue

  # read line into array
  IFS="$CSVDELIM" read -r -a COL <<< "$line"
  NAME="${COL[0]}"
  FIRSTNAME="$(echo "$NAME" | sed 's/^\(.*\) \([^ ]\+\)$/\1/')"
  LASTNAME="$(echo "$NAME" | sed 's/^\(.*\) \([^ ]\+\)$/\2/')"
  USERNAME="${FIRSTNAME// /_}"
  EMAIL="${COL[2]}"
  POSITION="${COL[3]}"
#  echo "$line split into ($NAME, $USERNAME, $EMAIL, $POSITION)"

  echo -n "Creating user $USERNAME..."

  if [ "$PASSWORD" = "generate" ]; then
    PASS="$(makepasswd --chars=20)"
  else
    PASS="$PASSWORD"
  fi

  CREATEPAYLOAD='{
    "email": "'"$EMAIL"'",
    "username": "'"$USERNAME"'",
    "first_name": "'"$FIRSTNAME"'",
    "last_name": "'"$LASTNAME"'",
    "password": "'"$PASS"'"
  }'

  PATCHPAYLOAD='{
    "position": "'"$POSITION"'"
  }'

  # create the user
  ID=$(curl -sX POST -H "Authorization: Token $TOKEN" -H "Content-typoe: application/json" -d "$CREATEPAYLOAD" "$MMURL/api/v4/users" | jq -r .id)
  if [ "$(echo -n "$ID" | wc -c)"  != "26" ]; then
    echo "Error."
    continue
  fi
  echo "Done."

  echo -n "Patching user $USERNAME..."
  # patch the user and add the position field
  NEWID=$(curl -sX PUT -H "Authorization: Token $TOKEN" -H "Content-type: application/json" -d "$PATCHPAYLOAD" "$MMURL/api/v4/users/$ID/patch" | jq -r .id)
  if [ "$NEWID" != "$ID" ]; then
    echo "Error."
  else
    echo "Done."
  fi
done < $CSVFILE

# Revoke the previously created token
$MMCTL token list $SYSADMIN --all --json 2>/dev/null | jq -r '.[] | select (.description == "bulkcreatetemp") | .id' | xargs $MMCTL token revoke

# restore old UAT Setting
$MMCTL config set ServiceSettings.EnableUserAccessTokens $UATSETTING > /dev/null 2>&1
