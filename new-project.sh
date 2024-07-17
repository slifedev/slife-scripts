#!/bin/bash

# VARIABLES
read -p "Enter new project name: " project_name
read -p "Enter domain: " domain
read -p "Enter site name: " site_name

frappe_repo=
frappe_branch=
erpnext_repo=
erpnext_branch=
image_tag=

# FUNCTIONS
log() {
  echo "$(date +'%Y-%m-$d %H:%M:%S') - $1"
}

error_exit() {
  echo "$(date +'%Y-%m-$d %H:%M:%S') - ERROR $1"
  exit 1
}

# OPERATIONS
log "Cloning frappe_docker repository"
git clone --depth=1 https://github.com/frappe/frappe_docker.git || error_exit "Failed to clone "
log "Renaming frappe_docker to frappe_docker_$project_name"
mv frappe_docker ./frappe_docker_$project_name || error_exit "Failed to rename frappe_docker"
log "Creating gitops-$project_name"
mkdir gitops-$project_name || error_exit "Failed to create gitops-$project_name"
log "Creating apps.json in gitops-$project_name"
touch gitops-$project_name/apps.json || error_exit "Failed to create apps.json in gitops-$project_name"
log "Writing apps into apps.json"
echo "[{\"url\":\"$erpnext_repo\",\"branch\":\"$erpnext_branch\"}]" > gitops-$project_name/apps.json || error_exit "Failed to write apps to apps.json"
log "cd to frappe_docker_$project_name"
cd frappe_docker_$project_name || error_exit "Failed to exit frappe_docker_$project_name"

log "Generating base64 string from apps.json"
APPS_JSON_BASE64=$(base64 -w 0 ../gitops-$project_name/apps.json) || error_exit "Failed to generate base64 string from apps.json"

log "Building an image"
docker build --no-cache\
  --build-arg=FRAPPE_PATH=$frappe_repo \
  --build-arg=FRAPPE_BRANCH=$frappe_branch \
  --build-arg=PYTHON_VERSION=3.10.12 \
  --build-arg=NODE_VERSION=20.11.0 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  -t=$image_tag \
  -f=images/custom/Containerfile . || error_exit "Failed to build an image"

# Install Traefik
# read -p "Enter subdomain for Traefik: " tr_sub
# echo "TRAEFIK_DOMAIN=$tr_sub.$domain" > ../gitops-$project_name/traefik.env
# read -p "Enter Traefik email: " tr_email
# echo "EMAIL=$tr_email" >> ../gitops-$project_name/traefik.env
# read -p "Enter Traefik password: " tr_pass
# echo 'HASHED_PASSWORD='$(openssl passwd -apr1 $tr_pass | sed 's/\$/\\\$/g') >> ../gitops-$project_name/traefik.env

# docker compose --project-name traefik \
#   --env-file ../gitops-$project_name/traefik.env \
#   -f overrides/compose.traefik.yaml \
#   -f overrides/compose.traefik-ssl.yaml up -d

# Install MariaDB
log "Changing MariaDB container name in overrides/compose.mariadb-shared.yaml"
sed -i "s/container_name: mariadb-database/container_name: mariadb-$project_name/g" overrides/compose.mariadb-shared.yaml || error_exit "Failed to change mariadb container name in overrides/compose.mariadb-shared.yaml"
read -s -p "Enter MariaDB password: " db_pass
log "Writing MariaDB password to mariadb.env"
echo "DB_PASSWORD=$db_pass" > ../gitops-$project_name/mariadb.env || error_exit "Failed to write MariaDB password to mariadb.env"
read -p "Enter MariaDB compose project name: " comp_db_name
log "Starting mariadb-$project_name"
docker compose --project-name mariadb-$project_name --env-file ../gitops-$project_name/mariadb.env -f overrides/compose.mariadb-shared.yaml up -d || error_exit "Failed to start mariadb-$project_name"

# Install ERPNext
log "Writing erpnext-$project_name.env"
cp example.env ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to cp example.env to erpnext-$project_name.env"
sed -i "s/DB_PASSWORD=123/DB_PASSWORD=$db_pass/g" ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set DB_PASSWORD"
sed -i "s/DB_HOST=/DB_HOST=mariadb-$project_name/g" ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set DB_HOST"
sed -i 's/DB_PORT=/DB_PORT=3306/g' ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set DB_PORT"
sed -i "s/SITES\=\`erp.example.com\`/SITES\=\`$site_name.$domain\`/g" ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set SITES"
echo "ROUTER=erpnext-$project_name" >> ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set ROUTER"
echo "BENCH_NETWORK=erpnext-$project_name" >> ../gitops-$project_name/erpnext-$project_name.env || error_exit "Failed to set BENCH_NETWORK"

log "Setting an image tag"
sed -i "s/.*  image:.*/  image: $image_tag/g" compose.yaml || error_exit "Failed to set an image tag"
sed -i "s/.*pull_policy.*//g" compose.yaml || error_exit "Failed to clear pull_policy string"

log "Writing erpnext-$project_name.yaml"
docker compose --project-name erpnext-$project_name \
  --env-file ../gitops-$project_name/erpnext-$project_name.env \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml \
  -f overrides/compose.multi-bench-ssl.yaml config > ../gitops-$project_name/erpnext-$project_name.yaml || error_exit "Failed to write erpnext-$project_name.yaml"

log "Starting erpnext-$project_name"
docker compose --project-name erpnext-$project_name -f ../gitops-$project_name/erpnext-$project_name.yaml up -d || error_exit "Failed to start erpnext-$project_name"

log "Setting Administrator password"
read -s -p "Enter Administrator password: " admin_pass || error_exit "Failed to set Administrator password"

log "Installing $site_name.$domain"
docker compose --project-name erpnext-$project_name exec backend \
  bench new-site $site_name.$domain --no-mariadb-socket --mariadb-root-password $db_pass --install-app erpnext --admin-password $admin_pass || error_exit "Failed to install $site_name.$domain"
log "Migrating $site_name.$domain"
docker compose --project-name erpnext-$project_name exec backend \
  bench --site $site_name.$domain migrate || error_exit "Failed to migrate $site_name.$domain"


