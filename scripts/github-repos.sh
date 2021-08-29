#!/bin/bash
GHUSER=zloeber
curl -q "https://api.github.com/users/$GHUSER/repos?per_page=300" | grep -o 'git@[^"]*'
