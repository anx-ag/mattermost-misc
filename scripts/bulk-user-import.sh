#!/bin/bash
#
# bulk user creation based on a CSV input file
# Employee Name;Employee ID;Email ID;Designation

# set to "generate" in order to create a different password for every user
PASSWORD="test123test123"
CSVFILE="test.csv"
CSVDELIM=","

# override path to mmctl here (if installed outside $PATH)
MMCTLPATH="mmctl"

# leave empty if the script should try to autodetect it
MMURL=""

# teams the users should join (space separated list of team names, leave empty for no teams to join, set to _all_ to add the users to all available teams)
TEAMS="_all_"

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
zip -v >/dev/null 2>&1 || die "zip not found"
mktemp --version >/dev/null 2>&1 || die "mktemp not found"

JSONLFILE=$(mktemp --suffix .jsonl)
ZIPFILE="$JSONLFILE.zip"
ZIPNAME="$(basename $ZIPFILE)"

[ ! -f $JSONFILE ] && die "temp file could not be created"

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

# get a list of all teams on this server
[ "$TEAMS" = "_all_" ] && TEAMS="$($MMCTL team list 2>/dev/null | xargs echo)"

echo -n "Creating jsonl input file..."
FIRST=0;
# read the file line by line
while read line; do
  # skip first line (contains headers)
  if [ "$FIRST" = "0" ]; then
    FIRST=1

    # write jsonl header
    echo '{"type":"version","version":1}' > $JSONLFILE
    continue
  fi

  # read line into array
  IFS="$CSVDELIM" read -r -a COL <<< "$line"
  NAME="${COL[0]}"
  FIRSTNAME="$(echo "$NAME" | sed 's/^\(.*\) \([^ ]\+\)$/\1/')"
  LASTNAME="$(echo "$NAME" | sed 's/^\(.*\) \([^ ]\+\)$/\2/')"
  USERNAME="${FIRSTNAME// /_}"
  EMAIL="${COL[2]}"
  POSITION="${COL[3]}"
#  echo "$line split into ($NAME, $USERNAME, $EMAIL, $POSITION)"

  if [ "$PASSWORD" = "generate" ]; then
    PASS="$(makepasswd --chars=20)"
  else
    PASS="$PASSWORD"
  fi

  JSONLINE='{
    "type":"user",
    "user": {
      "username": "'"${USERNAME,,}"'",
      "email": "'"$EMAIL"'",
      "auth_service": "",
      "password": "'"$PASS"'",
      "first_name": "'"$FIRSTNAME"'",
      "last_name": "'"$LASTNAME"'",
      "position": "'"$POSITION"'",
      "roles": "system_user"'

  if [ "$TEAMS" != "" ]; then
    JSONLINE=$JSONLINE',
      "teams": ['
    for team in $TEAMS; do
      JSONLINE=$JSONLINE'{
        "name": "'"$team"'",
	"roles": "team_user"
      },'
    done
    # replace last comma with a closing bracket for the array
    JSONLINE="${JSONLINE%?}]"
  fi
  echo "$JSONLINE}}"  | jq -r tostring >> $JSONLFILE
done < $CSVFILE

# validate json file
jq . $JSONLFILE >/dev/null 2>&1 || die "Generated file $(JSONLFILE) is invalid."
echo "done."

echo -n "Zipping import file..."
zip -r $ZIPFILE $JSONLFILE >/dev/null 2>&1 || die "error"
echo "done."

echo -n "Uploading file..."
MMFILE="$($MMCTL import upload $ZIPFILE --json | jq -r '.[] | select (.filename=="'"$ZIPNAME"'") | .id')_$ZIPNAME"
$MMCTL import list available | grep -q $MMFILE || die "error."
echo "done."

echo -n "Processing file"
JOBID="$($MMCTL import process $MMFILE | sed -n 's/^.*Import process job successfully created, ID: \(.*\)$/\1/p')"

QUIT=0
ERROR=
LINENR=
while true; do 
  OUTPUT=$($MMCTL import job show $JOBID --json)
  case "$(jq -r .[].status <<< $OUTPUT)" in
    "pending"|"in_progress")
      echo -n "."
      sleep 1
      ;;

    "success")
      echo "done."
      QUIT=1
      ;;

    "error")
      echo "error."
      QUIT=1
      LINENR="$(jq -r .[].data.line_number <<< $OUTPUT)"
      ERROR="Line $LINENR: $(jq -r .[].data.error <<< $OUTPUT)"
      ;;
  esac

  [ "$QUIT" = "1" ] && break
done

if [ "$ERROR" != "" ]; then
  echo "$ERROR"
  sed -n ${LINENR}p $JSONLFILE | jq .
else
  # cleanup if everything went well
  rm -f $JSONLFILE $ZIPFILE
fi
