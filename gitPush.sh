#!/bin/bash

localgit=/media/nas/git/files
comment=$1
if [ -z "$1" ]; then
    comment=$(date +'%Y.%m.%d-%H:%M:%S')
fi

cd $localgit || exit
git pull
git add .
git commit -m "$comment"
git push origin main
