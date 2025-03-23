#!/bin/bash

# بررسی دسترسی روت
if [ "$(id -u)" != "0" ]; then
   echo "این اسکریپت باید با دسترسی روت اجرا شود" 1>&2
   exit 1
fi

# توابع کمکی
function ask_with_default() {
    local prompt="$1"
    local default="$2"
    read -e -i "$default" -p "$prompt" input
    echo "${input:-$default}"
}

function generate_random_pass() {
    openssl rand -base64 12 | tr -d '\n'
}

# دریافت تنظیمات از کاربر
echo "
##############################################
### تنظیمات سرور وردپرس ###
##############################################
"

WP_URL=$(ask_with_default "دامین یا آیپی سرور: " "example.com")
WEB_ROOT=$(ask_with_default "مسیر نصب وردپرس: " "/var/www/html")
WP_ADMIN_USER=$(ask_with_default "نام کاربری ادمین وردپرس: " "admin")
WP_ADMIN_EMAIL=$(ask_with_default "ایمیل ادمین وردپرس: " "admin@${WP_URL}")

echo "
##############################################
### تنظیمات دیتابیس ###
##############################################
"

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

echo "
##############################################
### تنظیمات امنیتی ###
##############################################
"

echo -n "رمز عبور ادمین وردپرس (خالی بگذارید برای تولید تصادفی): "
read -s WP_ADMIN_PASS
if [ -z "$WP_ADMIN_PASS" ]; then
    WP_ADMIN_PASS=$(generate_random_pass)
    echo -e "\nرمز ادمین تولید شد: $WP_ADMIN_PASS"
else
    echo ""
fi

# تولید رمز ریشه ماریا دی بی
MYSQL_ROOT_PASS=$(generate_random_pass)

# آپدیت سیستم
echo -e "\n\nآپدیت سیستم و نصب پیشنیازها..."
apt update && apt upgrade -y
apt install -y apache2 \
    php \
    php-mysql \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-xmlrpc \
    php-soap \
    php-intl \
    php-zip \
    mariadb-server \
    wget \
    unzip

# تنظیمات ماریا دی بی
echo -e "\nتنظیم امنیت ماریا دی بی..."
mysql_secure_installation <<EOF

y
${MYSQL_ROOT_PASS}
${MYSQL_ROOT_PASS}
y
y
y
y
EOF

# ایجاد دیتابیس و کاربر
echo -e "\nایجاد دیتابیس و کاربر..."
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE DATABASE ${DB_NAME};"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql --user=root --password="${MYSQL_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# نصب وردپرس
echo -e "\nدانلود و نصب وردپرس..."
wget https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p ${WEB_ROOT}
cp -a /tmp/wordpress/* ${WEB_ROOT}/

# تنظیم فایل پیکربندی
cp ${WEB_ROOT}/wp-config-sample.php ${WEB_ROOT}/wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" ${WEB_ROOT}/wp-config.php
sed -i "s/username_here/${DB_USER}/" ${WEB_ROOT}/wp-config.php
sed -i "s/password_here/${DB_PASS}/" ${WEB_ROOT}/wp-config.php

# تولید کلیدهای امنیتی
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
printf '%s\n' "g/put your unique phrase here/d" a "$SALT" . w | ed -s ${WEB_ROOT}/wp-config.php

# تنظیم مجوزها
chown -R www-data:www-data ${WEB_ROOT}
find ${WEB_ROOT} -type d -exec chmod 755 {} \;
find ${WEB_ROOT} -type f -exec chmod 644 {} \;

# ایجاد کاربر ادمین از طریق CLI
echo -e "\nایجاد کاربر ادمین در وردپرس..."
sudo -u www-data -- wp core install --path=${WEB_ROOT} --url="http://${WP_URL}" \
    --title="سایت جدید" --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" --admin_email="${WP_ADMIN_EMAIL}"

# راه اندازی مجدد آپاچی
systemctl restart apache2

# ذخیره اطلاعات
cat << EOF > /root/wp-credentials.txt
ورود به مدیریت: http://${WP_URL}/wp-admin
نام کاربری ادمین: ${WP_ADMIN_USER}
رمز عبور ادمین: ${WP_ADMIN_PASS}
ایمیل ادمین: ${WP_ADMIN_EMAIL}

مشخصات دیتابیس:
نام دیتابیس: ${DB_NAME}
کاربر دیتابیس: ${DB_USER}
رمز دیتابیس: ${DB_PASS}

مشخصات ریشه ماریا دی بی:
نام کاربری: root
رمز عبور: ${MYSQL_ROOT_PASS}
EOF

echo -e "\n\nنصب با موفقیت انجام شد!"
echo "اطلاعات ورود در فایل /root/wp-credentials.txt ذخیره شده است"
echo "کلیدهای امنیتی ماریا دی بی: ${MYSQL_ROOT_PASS}"
