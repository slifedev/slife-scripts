#!/bin/bash

# VARIABLES
LOG_FILE=
FRAPPE_DOCKER_PATH=
APPS_PATH=
FRAPPE_REPO=
FRAPPE_BRANCH=
IMAGE_TAG=

# FUNCTIONS
log() {
  echo -e "\033[0;34m$(date +'%Y-%m-%d %H:%M:%S') - $1\033[0m" | tee -a $LOG_FILE
}

error_exit() {
  echo -e "\033[0;31m$(date +'%Y-%m-%d %H:%M:%S') - ERROR $1\033[0m" | tee -a $LOG_FILE
  exit 1
}

warn() {
  echo -e "\033[0;31m$(date +'%Y-%m-%d %H:%M:%S') - WARNING $1\033[0m" | tee -a $LOG_FILE
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

printf "\033[0;32m$SITE_NAME has been built successfully\033[0m\n"
