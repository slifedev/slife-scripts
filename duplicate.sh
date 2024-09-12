#!/bin/bash

ACCESS_TOKEN_FROM=""
ACCESS_TOKEN_TO=""
FROMNAME=""
TONAME=""
#REPOS=$(curl https://api.github.com/orgs/<organisation-name>/repos | jq -r '.[].name')
#REPOS=$(cat repos)
REPOS=""

log_error() {
    echo "ERROR: $1"
    exit 1
}

duplicate() {
    local repo=$1

    git clone --bare "https://$ACCESS_TOKEN_FROM@github.com/$FROMNAME/$repo" || log_error "FAILED TO CLONE A REPO: $repo"
    curl -H "Authorization: token $ACCESS_TOKEN_TO" --data "{\"name\":\"$repo\",\"private\":false}" https://api.github.com/user/repos || log_error "FAILED TO CREATE A NEW REPO: $repo"
    cd "$repo".git || log_error "FAILED TO CD A REPO: $repo"
    git push --mirror "https://$ACCESS_TOKEN_TO@github.com/$TONAME/$repo" || log_error "FAILED TO PUSH A REPO: $repo"
    cd .. || log_error "FAILED TO CD .."
    rm -rf "$repo".git || log_error "FAILED TO RM A REPO: $repo"
}

if [[ -z $ACCESS_TOKEN_TO ]]
then
    echo "ACCESS_TOKEN_TO is empty"
    exit 1
fi

if [[ -z $FROMNAME || -z $TONAME  ]]
then
    echo "FROMNAME or TONAME is empty"
    exit 1
fi

if [[ -z $REPOS  ]]
then
    echo "REPOS is empty"
    exit 1
fi

for repo in $REPOS; do
    duplicate $repo;
done
