#!/bin/bash

# --- رنگ‌های ترمینال ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- بررسی دسترسی روت ---
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}این اسکریپت باید با دسترسی روت اجرا شود${NC}" 1>&2
   exit 1
fi

# --- دریافت تنظیمات ---
echo -e "\n${CYAN}### تنظیمات سرور وردپرس ###${NC}"

WP_URL=$(read -p "دامنه یا آیپی سرور: " && echo $REPLY)
WEB_ROOT=$(read -p "مسیر نصب وردپرس: " && echo $REPLY)
WP_LANG=$(read -p "زبان وردپرس (fa/en): " && echo $REPLY)

# --- انتخاب نسخه PHP ---
echo -e "\n${CYAN}### انتخاب نسخه PHP ###${NC}"
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
apt update >/dev/null 2>&1
apt-cache search php | grep -Po 'php\d+\.\d+(?=-cli)' | sort -V | uniq
read -p "نسخه PHP مورد نظر را وارد کنید (مثال: php8.1): " selected_php

# --- تنظیمات مدیریتی ---
WP_ADMIN_USER="admin"
WP_ADMIN_EMAIL="admin@${WP_URL}"
DB_NAME="wordpress_$(openssl rand -hex 3)"
DB_USER="wp_user_$(openssl rand -hex 2)"
DB_PASS=$(openssl rand -base64 12 | tr -d '\n')
WP_ADMIN_PASS=$(openssl rand -base64 12 | tr -d '\n')
MYSQL_ROOT_PASS=$(openssl rand -base64 12 | tr -d '\n')

# --- نصب پیشنیازها ---
echo -e "\n${CYAN}### نصب پیشنیازها ###${NC}"
apt update && apt upgrade -y
apt install -y apache2 ${selected_php} ${selected_php}-mysql ${selected_php}-curl ${selected_php}-gd ${selected_php}-mbstring ${selected_php}-xml ${selected_php}-zip wget unzip curl ghostscript wp-cli

# --- نصب MariaDB ---
echo -e "\n${CYAN}### نصب MariaDB ###${NC}"
apt install -y mariadb-server

# --- تنظیمات MariaDB ---
echo -e "\n${CYAN}### تنظیمات دیتابیس ###${NC}"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE DATABASE ${DB_NAME};"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# --- نصب وردپرس ---
echo -e "\n${CYAN}### نصب وردپرس ###${NC}"
wget https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p "${WEB_ROOT}"
cp -a /tmp/wordpress/* "${WEB_ROOT}/"

# --- پیکربندی وردپرس ---
sudo -u www-data -- wp core config --path="${WEB_ROOT}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASS}" --extra-php <<PHP
define('FS_METHOD', 'direct');
define('WP_AUTO_UPDATE_CORE', true);
PHP

sudo -u www-data -- wp core install --path="${WEB_ROOT}" --url="http://${WP_URL}" --title="سایت جدید" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASS}" --admin_email="${WP_ADMIN_EMAIL}"

# --- تنظیمات امنیتی ---
echo -e "\n${CYAN}### تنظیمات امنیتی ###${NC}"
chown -R www-data:www-data "${WEB_ROOT}"
find "${WEB_ROOT}" -type d -exec chmod 755 {} \;
find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
chmod 600 "${WEB_ROOT}/wp-config.php"
rm -f "${WEB_ROOT}/readme.html" "${WEB_ROOT}/wp-config-sample.php"

# --- ذخیره اطلاعات ---
cat << EOF > /root/wp-credentials.txt
ورود به مدیریت: http://${WP_URL}/wp-admin
نام کاربری ادمین: ${WP_ADMIN_USER}
رمز عبور ادمین: ${WP_ADMIN_PASS}
ایمیل ادمین: ${WP_ADMIN_EMAIL}
زبان سایت: ${WP_LANG}
نسخه PHP: ${selected_php}

مشخصات دیتابیس:
نام دیتابیس: ${DB_NAME}
کاربر دیتابیس: ${DB_USER}
رمز دیتابیس: ${DB_PASS}

مشخصات ریشه ماریا دی بی:
نام کاربری: root
رمز عبور: ${MYSQL_ROOT_PASS}
EOF

# --- پایان نصب ---
systemctl restart apache2

echo -e "\n${GREEN}نصب با موفقیت انجام شد!${NC}"
echo -e "${YELLOW}اطلاعات ورود در فایل /root/wp-credentials.txt ذخیره شده است${NC}"
