#!/bin/bash

# VARIABLES
LOG_FILE=
YAML_PATH=
IMAGE_TAG=
NAMESPACE=
PROJECT_NAME=
SITE_NAME=
DOCKER_USERNAME=
DOCKER_PASSWORD=

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

log "Docker login"
echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin || error_exit "Failed to docker login"

log "Pulling $NAMESPACE/IMAGE_TAG"
docker pull "$NAMESPACE/$IMAGE_TAG" || error_exit "Failed to pull $NAMESPACE/$IMAGE_TAG"

log "Stopping $PROJECT_NAME"
docker compose -p $PROJECT_NAME down || error_exit "Failed to stop $PROJECT_NAME"
log "Starting $PROJECT_NAME from new image"
docker compose -p $PROJECT_NAME -f $YAML_PATH up -d || error_exit "Failed to start $PROJECT_NAME from new image"
log "Migrating $SITE_NAME"
docker compose -p $PROJECT_NAME exec backend bench --site $SITE_NAME migrate || error_exit "Failed to migrate $SITE_NAME"

# CLEAR ALL THE DANGLING IMAGES
# log "Clearing dangling images"
# docker rmi $(docker images -f dangling=true -q) || warn "Failed to clear dangling images"

printf "\033[0;32m$SITE_NAME has been built and deployed\033[0m\n"
