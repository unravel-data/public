#!/bin/bash

apt-get install --assume-yes  wget

## Download and extract the tar ball

wget https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel4530.tar.gz  -O /usr/local/unravel-package.tar.gz
cd  /usr/local
tar -zxvf unravel-package.tar.gz

## prepare srv folder

adduser --disabled-password --gecos ""  unravel

mkdir -p /srv/unravel
#cd /srv/unravel
mkdir -p /srv/unravel/k_data
mkdir -p /srv/unravel/log_hdfs
mkdir -p /srv/unravel/s_1_data
mkdir -p /srv/unravel/tmp
mkdir -p /srv/unravel/tmp_hdfs
mkdir -p /srv/unravel/zk_1_data
mkdir -p /srv/unravel/zk_2_data
mkdir -p /srv/unravel/zk_3_data
HDP_VER=$(apt list|grep hdp-select| awk '{ print $2 }')
cp /usr/local/unravel/stax-1.2.0.jar /usr/hdp/$HDP_VER/hadoop/lib/

#sudo mkdir k_data  log_hdfs  s_1_data  tmp  tmp_hdfs  zk_1_data  zk_2_data  zk_3_data

#sudo chown unravel:unravel k_data s_1_data zk_1_data zk_2_data zk_3_data tmp

ES_CLUSTER_NAME=$(grep -Po '(?!com.unraveldata.es.cluster=)unravel[0-9]+' /usr/local/unravel/etc/unravel.properties)
mkdir -p /srv/unravel/s_1_data/${ES_CLUSTER_NAME}
chown -R unravel:unravel  /srv/unravel/s_1_data/${ES_CLUSTER_NAME}

/usr/local/unravel/install_bin/switch_to_user.sh hdfs hdfs
# /usr/local/unravel/install_bin/switch_to_hdp.sh
sysctl -w vm.max_map_count=262144


# Create MySQL root password for unravel install
cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c10 > /usr/local/unravel/mysqlrootpass
MYSQLROOTPASS=`cat /usr/local/unravel/mysqlrootpass`
echo "MySQL root password = $MYSQLROOTPASS"

cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c10 > /usr/local/unravel/mysqlunravelpass
MYSQLUNRAVELPASS=`cat /usr/local/unravel/mysqlunravelpass`
echo "MySQL unravel password = $MYSQLUNRAVELPASS"

sed -i -e "s/unravel.jdbc.password=.*/unravel.jdbc.password=${MYSQLUNRAVELPASS}/g" /usr/local/unravel/etc/unravel.properties
sed -i -e "s/unravel.jdbc.url=.*/unravel.jdbc.url=jdbc:mariadb:\/\/127.0.0.1:3306\/unravel_mysql_prod/g" /usr/local/unravel/etc/unravel.properties
sed -i -e "s/^deb/#deb/g" /etc/apt/sources.list.d/hdp-utils-gpl.list

## Install mysql
apt-get update
dpkg --configure -a
echo "mysql-server mysql-server/root_password password $MYSQLROOTPASS" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQLROOTPASS" | debconf-set-selections
apt-get install --assume-yes mysql-server-5.7

service mysql start

echo "create database unravel_mysql_prod DEFAULT CHARACTER SET utf8; grant all on unravel_mysql_prod.* TO 'unravel'@'%' IDENTIFIED BY '$MYSQLUNRAVELPASS'; use unravel_mysql_prod; source /usr/local/unravel/mysql_scripts/20170920015500.sql; source /usr/local/unravel/mysql_scripts/20171008153000.sql; source /usr/local/unravel/mysql_scripts/20171202224307.sql; source /usr/local/unravel/mysql_scripts/20180118103500.sql;" | mysql -u root -p$MYSQLROOTPASS

echo "use unravel_mysql_prod; INSERT  IGNORE INTO \`users\` (\`id\`, \`email\`, \`encrypted_password\`, \`reset_password_token\`, \`reset_password_sent_at\`, \`remember_created_at\`, \`sign_in_count\`, \`current_sign_in_at\`, \`last_sign_in_at\`, \`current_sign_in_ip\`, \`last_sign_in_ip\`, \`created_at\`, \`updated_at\`, \`login\`, \`uid\`, \`authentication_token\`) VALUES (1,'','\$2a\$10\$.8bk4e/5UgD.A5ok13lKvOiVdzh.IMRbwrN0pJbvFZvXZHTitl5Di',NULL,NULL,NULL,1,now(),now(),'127.0.0.1','127.0.0.1',now(),now(),'admin',NULL,NULL); COMMIT;" | mysql -u root -p$MYSQLROOTPASS

sed -i -e "s/^#deb/deb/g" /etc/apt/sources.list.d/hdp-utils-gpl.list

sudo /usr/local/unravel/dbin/db_schema_upgrade.sh

/usr/local/unravel/install_bin/db_initial_inserts.sh | /usr/local/unravel/install_bin/db_access.sh

sudo /usr/local/unravel/install_bin/kafka_reset.sh

## change permission on unravel daemon scripts
chmod -R 755 /usr/local/unravel/init_scripts

## Starting unravel daemons
# /usr/local/unravel/init_scripts/unravel_all.sh stop
# sleep 10

## Checking unravel daemons' status
/usr/local/unravel/init_scripts/unravel_all.sh status

## Completed the phase1 setup
echo "All phase 1 processes are completed"
