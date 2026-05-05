#!/bin/bash

comment=$1
if [ -z "$1" ]; then
    comment=$(date +'%Y.%m.%d-%H:%M:%S')
fi

git pull
git add .
git commit -m "$comment"
git push origin main
