#!/bin/bash

# VARIABLES
read -p "Enter new project name: " PROJECT_NAME
read -p "Enter domain: " DOMAIN
read -p "Enter site name: " SITE_NAME

#TRAEF_SUBD=""
#TRAEF_EMAIL=""
#TRAEF_PASS=""
LOG_FILE=""
FRAPPE_REPO=""
FRAPPE_BRANCH=""
ERPNEXT_REPO=""
ERPNEXT_BRANCH=""
IMAGE_TAG=""

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
log "Cloning frappe_docker repository"
git clone --depth=1 https://github.com/frappe/frappe_docker.git || error_exit "Failed to clone "
log "Renaming frappe_docker to frappe_docker_$PROJECT_NAME"
mv frappe_docker ./frappe_docker_$PROJECT_NAME || error_exit "Failed to rename frappe_docker"
log "Creating gitops-$PROJECT_NAME"
mkdir gitops-$PROJECT_NAME || error_exit "Failed to create gitops-$PROJECT_NAME"
log "Creating apps.json in gitops-$PROJECT_NAME"
touch gitops-$PROJECT_NAME/apps.json || error_exit "Failed to create apps.json in gitops-$PROJECT_NAME"
log "Writing apps into apps.json"
echo "[{\"url\":\"$ERPNEXT_REPO\",\"branch\":\"$ERPNEXT_BRANCH\"}]" > gitops-$PROJECT_NAME/apps.json || error_exit "Failed to write apps to apps.json"
log "cd to frappe_docker_$PROJECT_NAME"
cd frappe_docker_$PROJECT_NAME || error_exit "Failed to exit frappe_docker_$PROJECT_NAME"

log "Generating base64 string from apps.json"
APPS_JSON_BASE64=$(base64 -w 0 ../gitops-$PROJECT_NAME/apps.json) || error_exit "Failed to generate base64 string from apps.json"

log "Building an image"
docker build --no-cache\
  --build-arg=FRAPPE_PATH=$FRAPPE_REPO \
  --build-arg=FRAPPE_BRANCH=$FRAPPE_BRANCH \
  --build-arg=PYTHON_VERSION=3.10.12 \
  --build-arg=NODE_VERSION=20.11.0 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  -t=$IMAGE_TAG \
  -f=images/custom/Containerfile . || error_exit "Failed to build an image"

#Install Traefik
if [[ ! $(docker compose ls -a | grep traefik) ]]; then
  mkdir ../gitops-traefik || error_exit "Faield to create gitops-traefik" 

  echo "TRAEFIK_DOMAIN=$TRAEF_SUBD.$DOMAIN" > ../gitops-traefik/traefik.env || error_exit "Failed to write TRAEFIK_DOMAIN to traefik.env"
  echo "EMAIL=$TRAEF_EMAIL" >> ../gitops-traefik/traefik.env || error_exit "Failed to write EMAIL to traefik.env"
  echo 'HASHED_PASSWORD='$(openssl passwd -apr1 $TRAEF_PASS | sed -e s/\\$/\\$\\$/g) >> ../gitops-traefik/traefik.env || error_exit "Failed to write HASHED_PASSWORD to traefik.env"

  docker compose --project-name traefik \
    --env-file ../gitops-traefik/traefik.env \
    -f overrides/compose.traefik.yaml \
    -f overrides/compose.traefik-ssl.yaml up -d || error_exit "Failed to up Traefik"
fi

# Install MariaDB
log "Changing MariaDB container name in overrides/compose.mariadb-shared.yaml"
sed -i "s/container_name: mariadb-database/container_name: mariadb-$PROJECT_NAME/g" overrides/compose.mariadb-shared.yaml || error_exit "Failed to change mariadb container name in overrides/compose.mariadb-shared.yaml"
read -s -p "Enter MariaDB password: " DB_PASS
log "Writing MariaDB password to mariadb.env"
echo "DB_PASSWORD=$DB_PASS" > ../gitops-$PROJECT_NAME/mariadb.env || error_exit "Failed to write MariaDB password to mariadb.env"
log "Starting mariadb-$PROJECT_NAME"
docker compose --project-name mariadb-$PROJECT_NAME --env-file ../gitops-$PROJECT_NAME/mariadb.env -f overrides/compose.mariadb-shared.yaml up -d || error_exit "Failed to start mariadb-$PROJECT_NAME"

# Install ERPNext
log "Writing erpnext-$PROJECT_NAME.env"
cp example.env ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to cp example.env to erpnext-$PROJECT_NAME.env"
sed -i "s/DB_PASSWORD=123/DB_PASSWORD=$DB_PASS/g" ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set DB_PASSWORD"
sed -i "s/DB_HOST=/DB_HOST=mariadb-$PROJECT_NAME/g" ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set DB_HOST"
sed -i 's/DB_PORT=/DB_PORT=3306/g' ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set DB_PORT"
sed -i "s/SITES\=\`erp.example.com\`/SITES\=\`$SITE_NAME.$DOMAIN\`/g" ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set SITES"
echo "ROUTER=erpnext-$PROJECT_NAME" >> ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set ROUTER"
echo "BENCH_NETWORK=erpnext-$PROJECT_NAME" >> ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env || error_exit "Failed to set BENCH_NETWORK"

log "Setting an image tag"
sed -i "s/.*  image:.*/  image: $IMAGE_TAG/g" compose.yaml || error_exit "Failed to set an image tag"
sed -i "s/.*pull_policy.*//g" compose.yaml || error_exit "Failed to clear pull_policy string"

log "Writing erpnext-$PROJECT_NAME.yaml"
docker compose --project-name erpnext-$PROJECT_NAME \
  --env-file ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.env \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml \
  -f overrides/compose.multi-bench-ssl.yaml config > ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.yaml || error_exit "Failed to write erpnext-$PROJECT_NAME.yaml"

log "Starting erpnext-$PROJECT_NAME"
docker compose --project-name erpnext-$PROJECT_NAME -f ../gitops-$PROJECT_NAME/erpnext-$PROJECT_NAME.yaml up -d || error_exit "Failed to start erpnext-$PROJECT_NAME"

log "Setting Administrator password"
read -s -p "Enter Administrator password: " ADMIN_PASS || error_exit "Failed to set Administrator password"

log "Installing $SITE_NAME.$DOMAIN"
docker compose --project-name erpnext-$PROJECT_NAME exec backend \
  bench new-site $SITE_NAME.$DOMAIN --no-mariadb-socket --mariadb-root-password $DB_PASS --install-app erpnext --admin-password $ADMIN_PASS || error_exit "Failed to install $SITE_NAME.$DOMAIN"
log "Migrating $SITE_NAME.$DOMAIN"
docker compose --project-name erpnext-$PROJECT_NAME exec backend \
  bench --site $SITE_NAME.$DOMAIN migrate || error_exit "Failed to migrate $SITE_NAME.$DOMAIN"

printf "\033[0;32m$SITE_NAME.$DOMAIN has been created and deployed\033[0m\n"
