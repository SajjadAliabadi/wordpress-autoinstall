#!/bin/bash

# --- رنگ‌های ترمینال ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- توابع کمکی ---
show_php_versions() {
    echo -e "\n${CYAN}نسخه‌های موجود PHP:${NC}"
    apt-cache search php | grep -Po 'php\d+\.\d+(?=-cli)' | sort -V | uniq | awk '{print NR ") " $0}'
}

select_php_version() {
    local versions=($(apt-cache search php | grep -Po 'php\d+\.\d+(?=-cli)' | sort -V | uniq))
    while true; do
        show_php_versions
        read -p "شماره نسخه مورد نظر را انتخاب کنید (1-${#versions[@]}): " choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#versions[@]} ]; then
            selected_php="${versions[$((choice-1))]}"
            PHP_VER="${selected_php#php}"
            break
        else
            echo -e "${RED}انتخاب نامعتبر! لطفا شماره صحیح وارد کنید.${NC}"
        fi
    done
}

ask_with_default() {
    local prompt="$1"
    local default="$2"
    read -e -i "$default" -p "$prompt" input
    echo "${input:-$default}"
}

generate_random_pass() {
    openssl rand -base64 12 | tr -d '\n'
}

install_mariadb() {
    echo -e "\n${CYAN}نصب MariaDB...${NC}"
    if ! curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --skip-maxscale --skip-tools --os-type=debian --os-version=bookworm; then
        echo -e "${YELLOW}خطا در دسترسی به مخازن - استفاده از مخازن جایگزین...${NC}"
        apt install -y mariadb-server --allow-unauthenticated || {
            echo -e "${RED}خطای بحرانی: نصب MariaDB ناموفق بود!${NC}"
            exit 1
        }
    fi
    apt update
    apt install -y mariadb-server
}

# --- بررسی دسترسی روت ---
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}این اسکریپت باید با دسترسی روت اجرا شود${NC}" 1>&2
   exit 1
fi

# --- دریافت تنظیمات ---
echo -e "\n${CYAN}### تنظیمات سرور وردپرس ###${NC}"

WP_URL=$(ask_with_default "دامنه یا آیپی سرور: " "example.com")
WEB_ROOT=$(ask_with_default "مسیر نصب وردپرس: " "/var/www/html")
WP_LANG=$(ask_with_default "زبان وردپرس (fa/en): " "fa")

echo -e "\n${CYAN}### انتخاب نسخه PHP ###${NC}"
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
apt update >/dev/null 2>&1
select_php_version

echo -e "\n${CYAN}### تنظیمات مدیریتی ###${NC}"
WP_ADMIN_USER=$(ask_with_default "نام کاربری ادمین وردپرس: " "admin")
WP_ADMIN_EMAIL=$(ask_with_default "ایمیل ادمین وردپرس: " "admin@${WP_URL}")

# --- تولید رمزهای عبور ---
DB_NAME="wordpress_$(openssl rand -hex 3)"
DB_USER="wp_user_$(openssl rand -hex 2)"
DB_PASS=$(generate_random_pass)
WP_ADMIN_PASS=$(generate_random_pass)
MYSQL_ROOT_PASS=$(generate_random_pass)

# --- نصب پیشنیازها ---
echo -e "\n${CYAN}### نصب پیشنیازها ###${NC}"
apt update && apt upgrade -y
apt install -y \
    apache2 \
    ${selected_php} \
    ${selected_php}-mysql \
    ${selected_php}-curl \
    ${selected_php}-gd \
    ${selected_php}-mbstring \
    ${selected_php}-xml \
    ${selected_php}-zip \
    wget \
    unzip \
    curl \
    ghostscript \
    wp-cli

# --- نصب و تنظیم MariaDB ---
install_mariadb

# --- تنظیمات MariaDB ---
echo -e "\n${CYAN}### تنظیمات دیتابیس ###${NC}"
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
echo -e "\n${CYAN}### نصب وردپرس ###${NC}"
wget https://wordpress.org/latest.zip -O /tmp/latest.zip
unzip -o /tmp/latest.zip -d /tmp
mkdir -p "${WEB_ROOT}"
cp -a /tmp/wordpress/* "${WEB_ROOT}/"

# --- تنظیمات زبان ---
if [ "$WP_LANG" = "fa" ]; then
    echo -e "\n${CYAN}### تنظیم زبان فارسی ###${NC}"
    sudo -u www-data -- wp core language install fa --path="${WEB_ROOT}"
    sudo -u www-data -- wp core language activate fa --path="${WEB_ROOT}"
    sudo -u www-data -- wp plugin install persian-fonts --activate --path="${WEB_ROOT}"
fi

# --- پیکربندی وردپرس ---
sudo -u www-data -- wp core config --path="${WEB_ROOT}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASS}" --extra-php <<PHP
define('FS_METHOD', 'direct');
define('WP_AUTO_UPDATE_CORE', true);
PHP

sudo -u www-data -- wp core install --path="${WEB_ROOT}" --url="http://${WP_URL}" \
    --title="سایت جدید" --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" --admin_email="${WP_ADMIN_EMAIL}"

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
نسخه PHP: ${PHP_VER}

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
