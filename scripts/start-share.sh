#!/bin/bash

docker \
  run -it \
  --rm \
  --name private_share \
  -p 139:139 \
  -p 445:445 \
  -v /media/zloeber/Datastore4/Backups/Downloads/ToSort:/tosort \
  -v /media/zloeber/Datastore4/Backups/Downloads/Media/Other:/toons \
  -v /media/zloeber/Datastore4/Backups/Downloads/Media/Favorites:/favorites \
  -v /media/zloeber/Datastore4/Backups/Downloads/New:/new \
  -d dperson/samba \
    -p \
    -u "user1;pass1" \
    -s "tosort;/tosort;yes;yes;no;user1" \
    -s "toons;/toons;yes;yes;no;user1" \
    -s "new;/new;yes;yes;no;user1" \
    -s "favorites;/favorites;yes;yes;no;user1"


