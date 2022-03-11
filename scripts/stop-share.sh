#!/bin/bash

docker stop private_share 2>/dev/null

sudo chown -R zloeber:zloeber /media/zloeber/Datastore*/Backups/Downloads/ToSort
sudo chown -R zloeber:zloeber /media/zloeber/Datastore*/Backups/Downloads/Media/Other
sudo chown -R zloeber:zloeber /media/zloeber/Datastore*/Backups/Downloads/Media/Favorites
sudo chown -R zloeber:zloeber /media/zloeber/Datastore*/Backups/Downloads/Media/New
