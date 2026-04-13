# 🚀 Paymenter Installer

Production-ready automated installer for Paymenter.

This script installs and configures a complete Paymenter environment on a fresh Ubuntu/Debian server with best practices for security and reliability.

## ✨ Features

- One-command installation
- Installs PHP with required extensions (incl. intl)
- Sets up MariaDB database and user
- Configures Nginx web server
- Installs Redis
- Installs Composer (non-root)
- Secure `.env` configuration
- Runs migrations and initialization
- Configures cron jobs
- Sets up queue worker (systemd)
- Optional Let's Encrypt SSL
- CLI flags support
- Self-update support
- Safe to re-run (idempotent)

## 📦 Requirements

- Ubuntu 20.04+ or Debian 11+
- Root or sudo access
- Clean or minimally configured server

## 🚀 Quick Start

```bash
curl -O https://raw.githubusercontent.com/frode81/paymenter-install-script/refs/heads/main/paymenter-installer.sh
chmod +x paymenter-installer.sh
sudo ./paymenter-installer.sh --domain panel.example.com --ssl --email admin@example.com
```

Or with options
```bash
sudo ./paymenter-installer.sh [options]
Options
--domain Domain name (required)
--ssl Enable Let's Encrypt SSL
--email Email for SSL notifications
--db-password Set database password
--php-version PHP version (default: 8.3)
--non-interactive Run without prompts
--update-self Update script to latest version
--help Show help
```

🔐 After Installation

Create your first admin user:

sudo -u www-data php /var/www/paymenter/artisan app:user:create
## ⚠️ Important
Save your .env file and APP_KEY
Run on a fresh server for best results
Make sure your domain points to the server before enabling SSL
## 🛡️ Security Notes
Database password can be auto-generated
.env is secured with correct permissions
Composer is never run as root
APP_KEY is generated automatically

## 🔄 Updating the Installer
sudo ./paymenter-installer.sh --update-self

## 👨‍💻 Author
Frode Røste
Røste Consulting

## 📄 License
MIT
