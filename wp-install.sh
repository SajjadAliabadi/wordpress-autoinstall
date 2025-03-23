#!/bin/bash

# --- رنگ‌ها ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- بررسی دسترسی روت ---
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}این اسکریپت باید با دسترسی روت اجرا شود.${NC}"
   exit 1
fi

# --- دریافت اطلاعات از کاربر ---
read -p "دامنه یا آیپی سرور: " WP_URL
read -p "مسیر نصب وردپرس [/var/www/html]: " WEB_ROOT
WEB_ROOT=${WEB_ROOT:-/var/www/html}
read -p "زبان وردپرس (fa/en) [fa]: " WP_LANG
WP_LANG=${WP_LANG:-fa}
read -p "نام کاربری ادمین وردپرس [admin]: " WP_ADMIN_USER
WP_ADMIN_USER=${WP_ADMIN_USER:-admin}
read -p "ایمیل ادمین وردپرس [admin@$WP_URL]: " WP_ADMIN_EMAIL
WP_ADMIN_EMAIL=${WP_ADMIN_EMAIL:-admin@$WP_URL}

# --- نمایش نسخه‌های PHP و انتخاب یکی ---
PHP_VERSIONS=($(apt-cache search php | grep -Po 'php\d+\.\d+(?=-cli)' | sort -V | uniq))
echo -e "${CYAN}نسخه‌های موجود PHP:${NC}"
for i in "${!PHP_VERSIONS[@]}"; do echo "$((i+1))) ${PHP_VERSIONS[$i]}"; done
while true; do
    read -p "شماره نسخه PHP را انتخاب کنید (1-${#PHP_VERSIONS[@]}): " CHOICE
    if [[ $CHOICE =~ ^[0-9]+$ ]] && [ $CHOICE -ge 1 ] && [ $CHOICE -le ${#PHP_VERSIONS[@]} ]; then
        PHP_VER=${PHP_VERSIONS[$((CHOICE-1))]}
        break
    else
        echo -e "${RED}انتخاب نامعتبر!${NC}"
    fi
done

# --- نصب پیشنیازها ---
echo -e "${CYAN}نصب پیشنیازها...${NC}"
apt update && apt install -y apache2 mariadb-server php libapache2-mod-$PHP_VER $PHP_VER-mysql wget unzip curl certbot python3-certbot-apache

# --- تنظیمات دیتابیس ---
DB_NAME="wordpress_$(openssl rand -hex 3)"
DB_USER="wp_user_$(openssl rand -hex 2)"
DB_PASS=$(openssl rand -base64 12)
MYSQL_ROOT_PASS=$(openssl rand -base64 12)

mysql -e "CREATE DATABASE $DB_NAME;"
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# --- دانلود و نصب وردپرس ---
wget -q https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p "$WEB_ROOT"
cp -a /tmp/wordpress/. "$WEB_ROOT"
chown -R www-data:www-data "$WEB_ROOT"

# --- تنظیمات وردپرس ---
wp config create --path="$WEB_ROOT" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --extra-php <<PHP
define('FS_METHOD', 'direct');
define('WP_AUTO_UPDATE_CORE', true);
PHP
wp core install --path="$WEB_ROOT" --url="http://$WP_URL" --title="سایت جدید" --admin_user="$WP_ADMIN_USER" --admin_password="$(openssl rand -base64 12)" --admin_email="$WP_ADMIN_EMAIL"

# --- فعال‌سازی زبان فارسی ---
if [ "$WP_LANG" = "fa" ]; then
    wp core language install fa --activate --path="$WEB_ROOT"
fi

# --- فعال‌سازی HTTPS (در صورت استفاده از دامنه) ---
if [[ "$WP_URL" != "" && "$WP_URL" != *"."* ]]; then
    echo -e "${YELLOW}⚠️ دامنه معتبر نیست. از تنظیم SSL صرف‌نظر شد.${NC}"
else
    certbot --apache -d "$WP_URL" --non-interactive --agree-tos -m "$WP_ADMIN_EMAIL"
fi

# --- پایان نصب ---
echo -e "${GREEN}✅ وردپرس با موفقیت نصب شد!${NC}"
