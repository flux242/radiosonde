#!/bin/bash

# Due to the fact that not all frames sent by RS41 sondes contain info about
# the subtype the log filename would only contain '_RS41_' substring if the
# first frame isn't the frame with the subtype info. Later the subtype will
# be detected and stored within the json strings. So, sometimes I start this
# scrip with the log directory name as its input parameter to rename the log
# files for RS41 sondes

[ -n "$1" ] || exit 1

for name in "$1"/*.log; do
  [ -n "$(echo $name | sed -nr 's/.*(_RS41_).*/\1/p')" ] && {
    subtype=$(cat $name | head -n+100 | tail -n-1 | jq -r '.subtype')
    [ -n "subtype" ] && [ ! "RS41" = "$subtype" ] || {
      # slower search over all available json strings
      subtype=$(jq -r 'select(.subtype!="RS41")|.subtype' "$name" | head -n+1)
    }
    [ -n "$subtype" ] && {
      new_name=$(echo $name | sed -nr "s/(.*)_RS41_(.*)/\1_${subtype}_\2/p")
      [ -n "$new_name" ] && [ ! "$new_name" = "$name" ] && {
        echo "Renaming $name to $new_name"
        mv "$name" "$new_name"
      }
    }
  }
done

