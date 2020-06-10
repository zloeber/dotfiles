#!/bin/bash
GHUSER=zloeber
curl "https://api.github.com/users/$GHUSER/repos?per_page=300" | grep -o 'git@[^"]*'
