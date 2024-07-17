#!/bin/bash

# VARIABLES
frappe_docker_path=
apps_path=
frappe_repo=
frappe_branch=
yaml_path=
image_tag=
project_name=
site_name=

# FUNCTIONS
log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

error_exit() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR $1"
  exit 1
}

# OPERATIONS
log "cd $frappe_docker_path"
cd $frappe_docker_path || error_exit "Failed to cd $frappe_docker_path"

log "Generating base64 string from $apps_path"
APPS_JSON_BASE64=$(base64 -w 0 $apps_path) || error_exit "Failed to generate base64 string from $apps_path"

log "Building an image"
docker build --no-cache\
  --build-arg=FRAPPE_PATH=$frappe_repo \
  --build-arg=FRAPPE_BRANCH=$frappe_branch \
  --build-arg=PYTHON_VERSION=3.10.12 \
  --build-arg=NODE_VERSION=20.11.0 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  -t=$image_tag \
  -f=images/custom/Containerfile . || error_exit "Failed to build an image"

log "Stopping $project_name"
docker compose -p $project_name down || error_exit "Failed to stop $project_name"
log "Starting $project_name from new image"
docker compose -p $project_name -f $yaml_path up -d || error_exit "Failed to start $project_name from new image"
log "Migrating $site_name"
docker compose -p $project_name exec backend bench --site $site_name migrate || error_exit "Failed to migrate $site_name"

log "Clearing docker builder cache"
echo y | docker builder prune || error_exit "Failed to clear docker builder cache"

printf "\033[0;32m$site_name has been built and deployed\033[0m\n"
