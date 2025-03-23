#!/bin/bash

# --- توابع کمکی ---
function ask_with_default() {
    local prompt="$1"
    local default="$2"
    read -e -i "$default" -p "$prompt" input
    echo "${input:-$default}"
}

function generate_random_pass() {
    openssl rand -base64 12 | tr -d '\n'
}

function install_mariadb_alt() {
    # راهکار جایگزین برای نصب MariaDB
    echo "نصب MariaDB با استفاده از مخازن جایگزین..."
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version=10.6 --skip-maxscale
    apt update
    apt install -y mariadb-server
}

# --- بررسی دسترسی روت ---
if [ "$(id -u)" != "0" ]; then
   echo "این اسکریپت باید با دسترسی روت اجرا شود" 1>&2
   exit 1
fi

# --- دریافت تنظیمات ---
echo "
##############################################
### تنظیمات سرور وردپرس ###
##############################################
"

WP_URL=$(ask_with_default "دامنه یا آیپی سرور: " "example.com")
WEB_ROOT=$(ask_with_default "مسیر نصب وردپرس: " "/var/www/html")
WP_LANG=$(ask_with_default "زبان وردپرس (fa/en): " "fa")
PHP_VER=$(ask_with_default "نسخه PHP (مثال: 8.1): " "8.1")

echo "
##############################################
### تنظیمات مدیریتی ###
##############################################
"

WP_ADMIN_USER=$(ask_with_default "نام کاربری ادمین وردپرس: " "admin")
WP_ADMIN_EMAIL=$(ask_with_default "ایمیل ادمین وردپرس: " "admin@${WP_URL}")

# --- نصب پیشنیازها با راهکار جایگزین ---
echo -e "\nآپدیت سیستم و نصب پیشنیازها..."
apt update && apt upgrade -y

# اضافه کردن مخازن PHP
add-apt-repository -y ppa:ondrej/php
apt update

# نصب بسته‌ها
apt install -y \
    apache2 \
    php${PHP_VER} \
    php${PHP_VER}-mysql \
    php${PHP_VER}-curl \
    php${PHP_VER}-gd \
    php${PHP_VER}-mbstring \
    php${PHP_VER}-xml \
    php${PHP_VER}-zip \
    wget \
    unzip \
    curl

# --- نصب MariaDB با راهکار جایگزین ---
install_mariadb_alt

# --- تنظیمات دیتابیس ---
DB_NAME=$(ask_with_default "نام دیتابیس: " "wordpress_db")
DB_USER=$(ask_with_default "نام کاربری دیتابیس: " "wp_user")

echo -n "رمز عبور دیتابیس (خالی بگذارید برای تولید تصادفی): "
read -s DB_PASS
if [ -z "$DB_PASS" ]; then
    DB_PASS=$(generate_random_pass)
    echo -e "\nرمز دیتابیس تولید شد: $DB_PASS"
else
    echo ""
fi

# --- تنظیمات امنیتی ---
echo -n "رمز عبور ادمین وردپرس (خالی بگذارید برای تولید تصادفی): "
read -s WP_ADMIN_PASS
if [ -z "$WP_ADMIN_PASS" ]; then
    WP_ADMIN_PASS=$(generate_random_pass)
    echo -e "\nرمز ادمین تولید شد: $WP_ADMIN_PASS"
else
    echo ""
fi

# --- پیکربندی MariaDB ---
MYSQL_ROOT_PASS=$(generate_random_pass)
mysql_secure_installation <<EOF

y
${MYSQL_ROOT_PASS}
${MYSQL_ROOT_PASS}
y
y
y
y
EOF

mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE DATABASE ${DB_NAME};"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# --- نصب وردپرس ---
echo -e "\nدانلود و نصب وردپرس..."
wget https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p ${WEB_ROOT}
cp -a /tmp/wordpress/* ${WEB_ROOT}/

# --- تنظیمات زبان ---
if [ "$WP_LANG" = "fa" ]; then
    echo "تنظیم زبان فارسی..."
    wget https://github.com/wp-plugins/persian-fonts/archive/refs/heads/master.zip -O /tmp/persian.zip
    unzip /tmp/persian.zip -d /tmp
    cp -r /tmp/persian-fonts-master/* ${WEB_ROOT}/wp-content/plugins/
fi

# --- پیکربندی وردپرس ---
sudo -u www-data -- wp core config --path=${WEB_ROOT} --dbname=${DB_NAME} --dbuser=${DB_USER} --dbpass=${DB_PASS}
sudo -u www-data -- wp core install --path=${WEB_ROOT} --url="http://${WP_URL}" \
    --title="سایت جدید" --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" --admin_email="${WP_ADMIN_EMAIL}"

# --- تنظیمات نهایی ---
chown -R www-data:www-data ${WEB_ROOT}
systemctl restart apache2

# --- ذخیره اطلاعات ---
cat << EOF > /root/wp-credentials.txt
ورود به مدیریت: http://${WP_URL}/wp-admin
نام کاربری ادمین: ${WP_ADMIN_USER}
رمز عبور ادمین: ${WP_ADMIN_PASS}
زبان سایت: ${WP_LANG}
نسخه PHP: ${PHP_VER}

مشخصات دیتابیس:
نام دیتابیس: ${DB_NAME}
کاربر دیتابیس: ${DB_USER}
رمز دیتابیس: ${DB_PASS}
رمز ریشه ماریا دی بی: ${MYSQL_ROOT_PASS}
EOF

echo -e "\n\nنصب با موفقیت انجام شد!"
