#!/bin/bash

# VARIABLES
FRAPPE_DOCKER_PATH=
APPS_PATH=
FRAPPE_REPO=
FRAPPE_BRANCH=
YAML_PATH=
IMAGE_TAG=
PROJECT_NAME=
SITE_NAME=

# FUNCTIONS
log() {
  echo -e "\033[0;34m$(date +'%Y-%m-%d %H:%M:%S') - $1\033[0m"
}

error_exit() {
  echo -e "\033[0;31m$(date +'%Y-%m-%d %H:%M:%S') - ERROR $1\033[0m"
  exit 1
}

warn() {
  echo -e "\033[0;31m$(date +'%Y-%m-%d %H:%M:%S') - WARNING $1\033[0m"
}

# OPERATIONS
log "cd $FRAPPE_DOCKER_PATH"
cd $FRAPPE_DOCKER_PATH || error_exit "Failed to cd $FRAPPE_DOCKER_PATH"

log "Generating base64 string from $APPS_PATH"
APPS_JSON_BASE64=$(base64 -w 0 $APPS_PATH) || error_exit "Failed to generate base64 string from $APPS_PATH"

log "Building an image"
docker build --no-cache\
  --build-arg=FRAPPE_PATH=$FRAPPE_REPO \
  --build-arg=FRAPPE_BRANCH=$FRAPPE_BRANCH \
  --build-arg=PYTHON_VERSION=3.10.12 \
  --build-arg=NODE_VERSION=20.11.0 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  -t=$IMAGE_TAG \
  -f=images/custom/Containerfile . || error_exit "Failed to build an image"

log "Stopping $PROJECT_NAME"
docker compose -p $PROJECT_NAME down || error_exit "Failed to stop $PROJECT_NAME"
log "Starting $PROJECT_NAME from new image"
docker compose -p $PROJECT_NAME -f $YAML_PATH up -d || error_exit "Failed to start $PROJECT_NAME from new image"
log "Migrating $SITE_NAME"
docker compose -p $PROJECT_NAME exec backend bench --site $SITE_NAME migrate || error_exit "Failed to migrate $SITE_NAME"

# CLEAR ALL THE DANGLING IMAGES
# log "Clearing dangling images"
# docker rmi $(docker images -f dangling=true -q) || warn "Failed to clear dangling images"

log "Clearing docker builder cache"
docker builder prune -f || warn "Failed to clear docker builder cache"

printf "\033[0;32m$SITE_NAME has been built and deployed\033[0m\n"
