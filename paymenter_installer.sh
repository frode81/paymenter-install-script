#!/usr/bin/env bash
#
# ============================================================
#  Paymenter Automated Installer
# ============================================================
#  Version: v1.1.0
#
#  Description:
#  Installs and configures Paymenter on Ubuntu/Debian with:
#   - Nginx
#   - MariaDB
#   - PHP + required extensions
#   - Redis
#   - Composer
#   - Paymenter app setup
#   - Queue worker (systemd)
#   - Cron
#   - Optional Let's Encrypt SSL
#
#  Manual post-install step:
#    sudo -u www-data php /var/www/paymenter/artisan app:user:create
#
#  Examples:
#    sudo bash paymenter-installer.sh --domain panel.example.com --ssl --email admin@example.com
#    sudo bash paymenter-installer.sh --domain panel.example.com --db-password 'secret' --non-interactive
#    sudo bash paymenter-installer.sh --update-self
#
# ============================================================

set -Eeuo pipefail

VERSION="v1.1.0"
SCRIPT_NAME="$(basename "$0")"

APP_DIR="/var/www/paymenter"
APP_USER="www-data"
APP_GROUP="www-data"
PHP_VERSION="8.3"
DB_NAME="paymenter"
DB_USER="paymenter"
NGINX_CONF="/etc/nginx/sites-available/paymenter.conf"
SERVICE_NAME="paymenter.service"

DOMAIN=""
SSL_EMAIL=""
DB_PASSWORD=""
INSTALL_SSL="false"
NON_INTERACTIVE="false"

# Set this to your raw script URL if you want self-update
SELF_UPDATE_URL="https://raw.githubusercontent.com/frode81/paymenter-install-script/refs/heads/main/payment_installer.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_line() {
  printf "${BLUE}%s${NC}\n" "------------------------------------------------------------"
}

print_header() {
  echo
  print_line
  printf "${BOLD}${CYAN}%s${NC}\n" "$1"
  print_line
}

print_step() {
  printf "${YELLOW}▶ %s${NC}\n" "$1"
}

print_ok() {
  printf "${GREEN}✔ %s${NC}\n" "$1"
}

print_warn() {
  printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

print_error() {
  printf "${RED}✘ %s${NC}\n" "$1"
}

show_help() {
  cat <<EOF
Paymenter Automated Installer ${VERSION}

Usage:
  sudo bash ${SCRIPT_NAME} [options]

Options:
  --domain <domain>          Domain name, e.g. panel.example.com
  --ssl                      Enable Let's Encrypt SSL
  --email <email>            Email for SSL notifications
  --db-password <password>   Database password
  --php-version <version>    PHP version (default: ${PHP_VERSION})
  --non-interactive          Run without prompts
  --update-self              Download latest script from SELF_UPDATE_URL
  --help, -h                 Show this help

Examples:
  sudo bash ${SCRIPT_NAME} --domain panel.example.com --ssl --email admin@example.com
  sudo bash ${SCRIPT_NAME} --domain panel.example.com --db-password 'secret' --non-interactive
  sudo bash ${SCRIPT_NAME} --update-self
EOF
}

error_handler() {
  local exit_code=$?
  local line_no=${1:-unknown}
  echo
  print_error "Installation failed on line ${line_no} (exit code: ${exit_code})"
  exit "${exit_code}"
}
trap 'error_handler $LINENO' ERR

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    print_error "This script must be run as root or with sudo."
    exit 1
  fi
}

random_password() {
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9@#%^_+=-' | head -c 32
}

update_self() {
  print_header "Updating installer"
  if [[ "${SELF_UPDATE_URL}" == "https://example.com/paymenter-installer.sh" ]]; then
    print_error "SELF_UPDATE_URL is not configured."
    exit 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  curl -fsSL "${SELF_UPDATE_URL}" -o "${tmp_file}"
  chmod +x "${tmp_file}"

  print_step "Replacing current script"
  cp "${tmp_file}" "$0"
  chmod +x "$0"
  rm -f "${tmp_file}"

  print_ok "Installer updated successfully"
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --ssl)
        INSTALL_SSL="true"
        shift
        ;;
      --email)
        SSL_EMAIL="${2:-}"
        shift 2
        ;;
      --db-password)
        DB_PASSWORD="${2:-}"
        shift 2
        ;;
      --php-version)
        PHP_VERSION="${2:-}"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE="true"
        shift
        ;;
      --update-self)
        update_self
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        print_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

prompt_values() {
  print_header "Paymenter Installer ${VERSION}"

  if [ -z "${DOMAIN}" ]; then
    read -rp "Enter domain (example: panel.example.com): " DOMAIN
  fi

  if [ -z "${DOMAIN}" ]; then
    print_error "Domain cannot be empty."
    exit 1
  fi

  if [ -z "${SSL_EMAIL}" ] && [ "${NON_INTERACTIVE}" != "true" ]; then
    read -rp "Email for SSL notifications (optional): " SSL_EMAIL
  fi

  if [ -z "${DB_PASSWORD}" ] && [ "${NON_INTERACTIVE}" != "true" ]; then
    read -rsp "Database password (leave empty to auto-generate): " DB_PASSWORD
    echo
  fi

  if [ -z "${DB_PASSWORD}" ]; then
    DB_PASSWORD="$(random_password)"
    print_ok "Generated database password automatically."
  fi

  if [ "${NON_INTERACTIVE}" != "true" ] && [ "${INSTALL_SSL}" != "true" ]; then
    read -rp "Install Let's Encrypt SSL now? (y/N): " ssl_choice
    if [[ "${ssl_choice:-N}" =~ ^[Yy]$ ]]; then
      INSTALL_SSL="true"
    fi
  fi
}

install_packages() {
  print_header "Installing system packages"

  export DEBIAN_FRONTEND=noninteractive

  print_step "Updating apt repositories"
  apt-get update >/dev/null

  print_step "Installing base dependencies"
  apt-get install -y \
    software-properties-common \
    curl \
    gnupg \
    lsb-release \
    unzip \
    tar \
    git \
    nginx \
    redis-server \
    openssl \
    ca-certificates \
    apt-transport-https >/dev/null

  if ! grep -Rq "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    print_step "Adding PHP repository"
    add-apt-repository -y ppa:ondrej/php >/dev/null
  else
    print_ok "PHP repository already present"
  fi

  if [ ! -f /etc/apt/sources.list.d/mariadb.list ] && [ ! -f /etc/apt/sources.list.d/mariadb.sources ]; then
    print_step "Adding MariaDB repository"
    curl -sSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11" >/dev/null
  else
    print_ok "MariaDB repository already present"
  fi

  print_step "Installing PHP ${PHP_VERSION}, MariaDB and related packages"
  apt-get update >/dev/null
  apt-get install -y \
    "php${PHP_VERSION}" \
    "php${PHP_VERSION}-cli" \
    "php${PHP_VERSION}-common" \
    "php${PHP_VERSION}-fpm" \
    "php${PHP_VERSION}-mysql" \
    "php${PHP_VERSION}-gd" \
    "php${PHP_VERSION}-mbstring" \
    "php${PHP_VERSION}-bcmath" \
    "php${PHP_VERSION}-xml" \
    "php${PHP_VERSION}-curl" \
    "php${PHP_VERSION}-zip" \
    "php${PHP_VERSION}-intl" \
    "php${PHP_VERSION}-redis" \
    mariadb-server >/dev/null

  print_step "Enabling services"
  systemctl enable --now mariadb >/dev/null
  systemctl enable --now "php${PHP_VERSION}-fpm" >/dev/null
  systemctl enable --now nginx >/dev/null
  systemctl enable --now redis-server >/dev/null

  print_ok "System packages installed"
}

install_composer() {
  print_header "Installing Composer"

  if ! command -v composer >/dev/null 2>&1; then
    print_step "Downloading Composer"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null
    print_ok "Composer installed"
  else
    print_ok "Composer already installed"
  fi
}

setup_database() {
  print_header "Configuring database"

  print_step "Creating database"
  mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  print_step "Creating or updating database users"
  mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
  mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
  mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';"
  mysql -e "FLUSH PRIVILEGES;"

  print_ok "Database configured"
}

download_paymenter() {
  print_header "Downloading Paymenter"

  mkdir -p "${APP_DIR}"
  cd "${APP_DIR}"

  if [ ! -f "${APP_DIR}/artisan" ]; then
    print_step "Downloading latest Paymenter release"
    curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
    tar -xzf paymenter.tar.gz
    rm -f paymenter.tar.gz
    print_ok "Paymenter extracted"
  else
    print_ok "Paymenter files already present"
  fi

  if [ ! -f "${APP_DIR}/artisan" ]; then
    print_error "artisan file not found after extraction"
    exit 1
  fi

  mkdir -p "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
  chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"

  print_ok "Application files ready"
}

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

configure_env() {
  print_header "Configuring environment"

  cd "${APP_DIR}"

  if [ ! -f .env.example ]; then
    print_error ".env.example not found in ${APP_DIR}"
    exit 1
  fi

  if [ ! -f .env ]; then
    cp .env.example .env
    print_ok "Created .env from .env.example"
  else
    print_ok ".env already exists, updating values"
  fi

  set_env "APP_ENV" "production"
  set_env "APP_DEBUG" "false"
  set_env "APP_URL" "http://${DOMAIN}"
  set_env "DB_CONNECTION" "mariadb"
  set_env "DB_HOST" "127.0.0.1"
  set_env "DB_PORT" "3306"
  set_env "DB_DATABASE" "${DB_NAME}"
  set_env "DB_USERNAME" "${DB_USER}"
  set_env "DB_PASSWORD" "${DB_PASSWORD}"

  chown "${APP_USER}:${APP_GROUP}" .env
  chmod 640 .env

  print_ok "Environment configured"
}

install_php_dependencies() {
  print_header "Installing PHP dependencies"

  cd "${APP_DIR}"

  print_step "Running composer install as ${APP_USER}"
  sudo -u "${APP_USER}" composer install --no-dev --optimize-autoloader --working-dir="${APP_DIR}"

  print_step "Generating application key"
  sudo -u "${APP_USER}" php artisan key:generate --force

  if [ ! -L "${APP_DIR}/public/storage" ]; then
    print_step "Creating storage symlink"
    sudo -u "${APP_USER}" php artisan storage:link
  else
    print_warn "Storage symlink already exists, skipping"
  fi

  print_step "Running migrations and seeders"
  sudo -u "${APP_USER}" php artisan migrate --force --seed
  sudo -u "${APP_USER}" php artisan db:seed --class=CustomPropertySeeder

  print_step "Running initial Paymenter setup"
  sudo -u "${APP_USER}" php artisan app:init

  print_step "Clearing caches"
  sudo -u "${APP_USER}" php artisan optimize:clear

  print_ok "PHP dependencies and app setup completed"
}

configure_nginx() {
  print_header "Configuring Nginx"

  cat > "${NGINX_CONF}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${APP_DIR}/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

  ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/paymenter.conf
  rm -f /etc/nginx/sites-enabled/default

  nginx -t >/dev/null
  systemctl reload nginx

  print_ok "Nginx configured"
}

configure_ssl() {
  if [ "${INSTALL_SSL}" = "true" ]; then
    print_header "Configuring SSL"

    apt-get install -y certbot python3-certbot-nginx >/dev/null

    if [ -n "${SSL_EMAIL}" ]; then
      certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${SSL_EMAIL}" --redirect
    else
      certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --register-unsafely-without-email --redirect
    fi

    cd "${APP_DIR}"
    set_env "APP_URL" "https://${DOMAIN}"

    print_ok "SSL configured"
  else
    print_warn "Skipping SSL setup"
  fi
}

configure_cron() {
  print_header "Configuring cron"

  local cron_line="* * * * * php ${APP_DIR}/artisan app:cron-job >> /dev/null 2>&1"
  (
    crontab -u "${APP_USER}" -l 2>/dev/null | grep -Fv "artisan app:cron-job" || true
    echo "${cron_line}"
  ) | crontab -u "${APP_USER}" -

  print_ok "Cron job configured"
}

configure_worker() {
  print_header "Configuring queue worker"

  cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=Paymenter Queue Worker
After=network.target mariadb.service redis-server.service

[Service]
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/php ${APP_DIR}/artisan queue:work --sleep=3 --tries=3 --timeout=90
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}" >/dev/null

  print_ok "Queue worker service configured"
}

configure_permissions() {
  print_header "Setting file permissions"

  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"
  find "${APP_DIR}" -type f -exec chmod 644 {} \;
  find "${APP_DIR}" -type d -exec chmod 755 {} \;
  chmod -R 775 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
  chmod 640 "${APP_DIR}/.env"

  print_ok "Permissions updated"
}

print_summary() {
  print_header "Installation complete"

  echo -e "${GREEN}Paymenter has been installed successfully.${NC}"
  echo
  echo -e "${BOLD}Installer version:${NC} ${VERSION}"
  echo -e "${BOLD}URL:${NC} http://${DOMAIN}"
  echo -e "${BOLD}App directory:${NC} ${APP_DIR}"
  echo -e "${BOLD}Database name:${NC} ${DB_NAME}"
  echo -e "${BOLD}Database user:${NC} ${DB_USER}"
  echo -e "${BOLD}Database password:${NC} ${DB_PASSWORD}"
  echo
  echo -e "${YELLOW}Next step:${NC}"
  echo "sudo -u ${APP_USER} php ${APP_DIR}/artisan app:user:create"
  echo
  echo -e "${YELLOW}Important:${NC} Save your APP_KEY from ${APP_DIR}/.env securely."
}

main() {
  require_root
  parse_args "$@"
  prompt_values
  install_packages
  install_composer
  setup_database
  download_paymenter
  configure_env
  install_php_dependencies
  configure_nginx
  configure_ssl
  configure_cron
  configure_worker
  configure_permissions
  print_summary
}

main "$@"
