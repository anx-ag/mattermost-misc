#!/bin/bash
#
# bulk user creation based on a CSV input file
# Employee Name;Employee ID;Email ID;Designation

CSVFILE="test.csv"
CSVDELIM=","

# override path to mmctl here (if installed outside $PATH)
MMCTLPATH="mmctl"

# do not change anything below this line

die()
{
  echo $*
  exit 1
}

# some sanity checks
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

# we need to allow user deletion via API
USERDELSETTING=$($MMCTL config get ServiceSettings.EnableAPIUserDeletion)
[ "$USERDELSETTING" = "false" ] && $MMCTL config set ServiceSettings.EnableAPIUserDeletion true > /dev/null 2>&1

FIRST=0
# read the file line by line
while read line; do
  # skip first line (contains headers)
  [ "$FIRST" = "0" ] && FIRST=1 && continue

  # read line into array
  IFS="$CSVDELIM" read -r -a COL <<< "$line"
  NAME="${COL[0]}"
  FIRSTNAME="$(echo "$NAME" | sed 's/^\(.*\) \([^ ]\+\)$/\1/')"
  USERNAME="${FIRSTNAME// /_}"
  # usernames need to be lower case
  USERNAME="${USERNAME,,}"

  echo -n "Deleting user $USERNAME..."
  OUTPUT=$($MMCTL user delete $USERNAME --confirm 2>&1)

  # return code is always 0, no matter what happens, so we need to parse the output
  if grep -q "error" <<< "$OUTPUT"; then
    echo "error ($(sed -n 's/^.*\* \(.*\)$/\1/p' <<< "$OUTPUT"))."
  else
    echo "done."
  fi

done < $CSVFILE

# restore old UAT Setting
$MMCTL config set ServiceSettings.EnableAPIUserDeletion $USERDELSETTING > /dev/null 2>&1
