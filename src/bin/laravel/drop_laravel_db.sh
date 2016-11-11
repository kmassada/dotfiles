#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")" && source "utils.sh"

cd -

DB_DATABASE=$(grep DB_DATABASE .env | awk -F[=] '{print $2}')
DB_USERNAME=$(grep DB_USERNAME .env | awk -F[=] '{print $2}')
DB_PASSWORD=$(grep DB_PASSWORD .env | awk -F[=] '{print $2}')

TABLES=$(mysql -u $DB_USERNAME -p$DB_PASSWORD $DB_DATABASE -e 'show tables' | awk '{ print $1}' | grep -v '^Tables' )

for t in $TABLES
do
	echo "Deleting $t table from $DB_DATABASE database..."
	mysql -u $DB_USERNAME -p$DB_PASSWORD $DB_DATABASE -e "drop table $t"
done

# print_message "attempting to retrieve root passwords"
# mysql -u $DB_USERNAME -p$DB_PASSWORD  $DB_DATABASE<<-EOF
# SET FOREIGN_KEY_CHECKS = 0;
# SELECT GROUP_CONCAT(table_schema, '.', table_name) INTO @tables
# FROM information_schema.tables;
#
# SET @tables = CONCAT('DROP TABLE ', @tables);
# PREPARE stmt FROM @tables;
# EXECUTE stmt;
# DEALLOCATE PREPARE stmt;
# SET FOREIGN_KEY_CHECKS = 1;
# EOF
