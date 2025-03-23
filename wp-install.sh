#!/bin/bash

# --- رنگ‌های ترمینال ---
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

# --- دریافت تنظیمات وردپرس از کاربر ---
echo -e "\n${CYAN}### تنظیمات سرور وردپرس ###${NC}"

read -p "دامنه یا آیپی سرور (مثال: example.com): " WP_URL
read -p "مسیر نصب وردپرس (مثال: /var/www/html): " WEB_ROOT
WEB_ROOT=${WEB_ROOT:-/var/www/html}

read -p "زبان وردپرس (fa برای فارسی، en برای انگلیسی) [fa]: " WP_LANG
WP_LANG=${WP_LANG:-fa}

echo -e "\n${CYAN}### تنظیمات مدیریتی وردپرس ###${NC}"
read -p "نام کاربری ادمین وردپرس (مثال: admin): " WP_ADMIN_USER
WP_ADMIN_USER=${WP_ADMIN_USER:-admin}
read -p "ایمیل ادمین وردپرس (مثال: admin@${WP_URL}): " WP_ADMIN_EMAIL
WP_ADMIN_EMAIL=${WP_ADMIN_EMAIL:-admin@${WP_URL}}
read -p "رمز عبور ادمین وردپرس: " WP_ADMIN_PASS

# --- انتخاب نسخه PHP ---
echo -e "\n${CYAN}### انتخاب نسخه PHP ###${NC}"
# افزودن مخزن ondrej/php برای دریافت نسخه‌های جدید PHP
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
apt update >/dev/null 2>&1

# گرفتن لیست نسخه‌های PHP موجود (به صورت phpX.Y)
PHP_VERSIONS=($(apt-cache search php | grep -Po 'php[0-9]+\.[0-9]+(?=-cli)' | sort -V | uniq))
if [ ${#PHP_VERSIONS[@]} -eq 0 ]; then
    echo -e "${RED}هیچ نسخه PHP‌ای پیدا نشد!${NC}"
    exit 1
fi

echo "نسخه‌های موجود PHP:"
for i in "${!PHP_VERSIONS[@]}"; do
    echo "$((i+1))) ${PHP_VERSIONS[$i]}"
done
while true; do
    read -p "شماره نسخه PHP مورد نظر را انتخاب کنید (1-${#PHP_VERSIONS[@]}): " CHOICE
    if [[ $CHOICE =~ ^[0-9]+$ ]] && [ $CHOICE -ge 1 ] && [ $CHOICE -le ${#PHP_VERSIONS[@]} ]; then
        selected_php="${PHP_VERSIONS[$((CHOICE-1))]}"
        break
    else
        echo -e "${RED}انتخاب نامعتبر! لطفاً شماره صحیح وارد کنید.${NC}"
    fi
done

# --- تولید اطلاعات دیتابیس ---
DB_NAME="wordpress_$(openssl rand -hex 3)"
DB_USER="wp_user_$(openssl rand -hex 2)"
DB_PASS=$(openssl rand -base64 12 | tr -d '\n')

# --- نصب پیشنیازها ---
echo -e "\n${CYAN}### نصب پیشنیازها ###${NC}"
apt update && apt upgrade -y

# نصب Apache، MariaDB، PHP و افزونه‌های PHP مورد نیاز
apt install -y apache2 mariadb-server wget unzip curl ghostscript \
    ${selected_php} ${selected_php}-mysql ${selected_php}-curl ${selected_php}-gd ${selected_php}-mbstring ${selected_php}-xml ${selected_php}-zip wp-cli

# --- شروع و فعالسازی سرویس‌ها ---
systemctl restart apache2
systemctl enable apache2
systemctl restart mariadb
systemctl enable mariadb

# --- تنظیمات دیتابیس در MariaDB ---
echo -e "\n${CYAN}### تنظیمات دیتابیس ###${NC}"
mysql -u root <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# --- نصب وردپرس ---
echo -e "\n${CYAN}### نصب وردپرس ###${NC}"
wget https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p "${WEB_ROOT}"
cp -a /tmp/wordpress/. "${WEB_ROOT}/"

# تنظیم دسترسی به پوشه نصب وردپرس
chown -R www-data:www-data "${WEB_ROOT}"

# --- پیکربندی وردپرس با WP-CLI ---
echo -e "\n${CYAN}### پیکربندی وردپرس ###${NC}"
sudo -u www-data wp core config --path="${WEB_ROOT}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASS}" --extra-php <<PHP
define('FS_METHOD', 'direct');
define('WP_AUTO_UPDATE_CORE', true);
PHP

sudo -u www-data wp core install --path="${WEB_ROOT}" --url="http://${WP_URL}" --title="سایت جدید" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASS}" --admin_email="${WP_ADMIN_EMAIL}"

# --- تنظیم زبان وردپرس ---
if [ "$WP_LANG" = "fa" ]; then
    echo -e "\n${CYAN}### نصب و فعالسازی زبان فارسی ###${NC}"
    sudo -u www-data wp core language install fa --path="${WEB_ROOT}"
    sudo -u www-data wp core language activate fa --path="${WEB_ROOT}"
fi

# --- تنظیمات امنیتی نهایی ---
echo -e "\n${CYAN}### تنظیمات امنیتی ###${NC}"
find "${WEB_ROOT}" -type d -exec chmod 755 {} \;
find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
chmod 600 "${WEB_ROOT}/wp-config.php"
rm -f "${WEB_ROOT}/readme.html" "${WEB_ROOT}/wp-config-sample.php"

# --- ذخیره اطلاعات ورود به سیستم ---
cat << EOF > /root/wp-credentials.txt
ورود به مدیریت وردپرس: http://${WP_URL}/wp-admin
نام کاربری ادمین: ${WP_ADMIN_USER}
رمز عبور ادمین: ${WP_ADMIN_PASS}
ایمیل ادمین: ${WP_ADMIN_EMAIL}
نسخه PHP انتخاب شده: ${selected_php}

مشخصات دیتابیس:
نام دیتابیس: ${DB_NAME}
کاربر دیتابیس: ${DB_USER}
رمز دیتابیس: ${DB_PASS}
EOF

echo -e "\n${GREEN}✅ نصب وردپرس با موفقیت انجام شد!${NC}"
echo -e "${YELLOW}اطلاعات ورود در فایل /root/wp-credentials.txt ذخیره شده است${NC}"
