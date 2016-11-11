#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")" && source "utils.sh"

cd - 

DB_DATABASE=$(grep DB_DATABASE .env | awk -F[=] '{print $2}')
DB_USERNAME=$(grep DB_USERNAME .env | awk -F[=] '{print $2}')
DB_PASSWORD=$(grep DB_PASSWORD .env | awk -F[=] '{print $2}')


cat >>   $DB_DATABASE-setup.sql << EOF
CREATE DATABASE ${DB_DATABASE};
GRANT ALL PRIVILEGES ON ${DB_DATABASE}.* TO '${DB_USERNAME}'@'localhost' identified by '${DB_PASSWORD}';
FLUSH PRIVILEGES;
EOF

print_message "attempting to retrieve root passwords"
mysql -u root -p <  $DB_DATABASE-setup.sql
