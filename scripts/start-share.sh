#!/bin/bash

docker \
  run -it \
  --rm \
  --name private_share \
  -p 139:139 \
  -p 445:445 \
  -v /media/zloeber/Datastore/Backups/Downloads/ToSort:/tosort \
  -v /media/zloeber/Datastore/Backups/Downloads/Media/Other:/hentai \
  -v /media/zloeber/Datastore/Backups/Downloads/Media/Favorites:/favorites \
  -d dperson/samba \
    -p \
    -u "user1;pass1" \
    -s "tosort;/tosort;yes;yes;no;user1" \
    -s "hentai;/hentai;yes;yes;no;user1" \
    -s "favorites;/favorites;yes;yes;no;user1"


