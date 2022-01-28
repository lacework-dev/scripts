#!/bin/bash

STAR=*
FILEENDING=".enable"

mkdir -p /tmp/lacework
gcloud config set accessibility/screen_reader false

var=$(gcloud projects list --filter='lifecycleState:ACTIVE' | sed "1 d" | cut -d ' ' -f 1)
number_projects=$(echo "$var" | wc -l)

echo "==> Project list:"
echo $var | tr " " "\n"
echo "==> Total number of projects = $number_projects"

read -p "Continue to enable on all projects? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

for val in $var; do
    echo "=> Enabling for Project $val"
    if gcloud --project $val services enable cloudasset.googleapis.com > /tmp/lacework/$val$FILEENDING
    then
       echo "==> Done."
    else
       echo "==> Error enabling."
    fi
    echo "***************************************"
done
