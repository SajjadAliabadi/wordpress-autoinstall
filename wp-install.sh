#!/bin/bash

# بررسی کاربر روت
if [[ $EUID -ne 0 ]]; then
   echo "این اسکریپت باید با دسترسی روت اجرا شود" 
   exit 1
fi

# به‌روز رسانی سیستم
echo "در حال به‌روز رسانی سیستم..."
apt update && apt upgrade -y

# نصب سرویس‌های مورد نیاز
echo "نصب Apache, MySQL, و PHP..."
apt install -y apache2 mysql-server php php-mysql libapache2-mod-php unzip

# نمایش نسخه‌های PHP نصب شده
PHP_VERSIONS=$(update-alternatives --list php | awk -F'/' '{print $NF}')
echo "نسخه‌های PHP موجود:"
echo "$PHP_VERSIONS"
read -p "لطفاً نسخه PHP موردنظر را وارد کنید: " PHP_VERSION
update-alternatives --set php "/usr/bin/php$PHP_VERSION"

# دریافت اطلاعات از کاربر
read -p "نام پایگاه داده: " DB_NAME
read -p "نام کاربری پایگاه داده: " DB_USER
read -s -p "رمز عبور پایگاه داده: " DB_PASS
read -p "نام کاربری مدیریت وردپرس: " WP_ADMIN
read -s -p "رمز عبور مدیریت وردپرس: " WP_PASS
read -p "ایمیل مدیریت وردپرس: " WP_EMAIL
read -p "زبان وردپرس (fa برای فارسی، en برای انگلیسی): " WP_LANG

# تنظیم زبان
if [[ "$WP_LANG" == "fa" ]]; then
    WP_URL="https://fa.wordpress.org/latest-fa_IR.zip"
else
    WP_URL="https://wordpress.org/latest.zip"
fi

# دانلود و نصب وردپرس
echo "دانلود وردپرس..."
wget $WP_URL -O wordpress.zip
unzip wordpress.zip
rm wordpress.zip
mv wordpress /var/www/html/
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress

# ایجاد پایگاه داده
echo "ایجاد پایگاه داده..."
mysql -e "CREATE DATABASE $DB_NAME;"
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# پیکربندی وردپرس
cp /var/www/html/wordpress/wp-config-sample.php /var/www/html/wordpress/wp-config.php
sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wordpress/wp-config.php
sed -i "s/username_here/$DB_USER/" /var/www/html/wordpress/wp-config.php
sed -i "s/password_here/$DB_PASS/" /var/www/html/wordpress/wp-config.php

# راه‌اندازی وردپرس با WP-CLI
echo "نصب وردپرس..."
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

wp core install --path=/var/www/html/wordpress \
    --url="http://localhost" \
    --title="سایت من" \
    --admin_user="$WP_ADMIN" \
    --admin_password="$WP_PASS" \
    --admin_email="$WP_EMAIL" \
    --locale="$WP_LANG" \
    --allow-root

# راه‌اندازی مجدد Apache
systemctl restart apache2
echo "نصب وردپرس با موفقیت انجام شد!"
