#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/tmp/edgenode_log.out 2>&1


apt-get install --assume-yes  wget

## Download and extract the tar ball

wget https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-package.tar.gz  -O /usr/local/unravel-package.tar.gz
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

#sudo mkdir k_data  log_hdfs  s_1_data  tmp  tmp_hdfs  zk_1_data  zk_2_data  zk_3_data

chown hdfs:hdfs /srv/unravel/log_hdfs
chown hdfs:hdfs /srv/unravel/tmp_hdfs

chown unravel:unravel /srv/unravel/k_data
chown unravel:unravel /srv/unravel/tmp
chown unravel:unravel /srv/unravel/s_1_data
chown unravel:unravel /srv/unravel/zk_1_data
chown unravel:unravel /srv/unravel/zk_2_data
chown unravel:unravel /srv/unravel/zk_3_data

chown -R unravel:unravel /usr/local/unravel

#sudo chown unravel:unravel k_data s_1_data zk_1_data zk_2_data zk_3_data tmp
mkdir -p /srv/unravel/s_1_data/unravel14810
chown -R unravel:unravel  /srv/unravel/s_1_data/unravel14810

sudo -u unravel sh -c 'echo "1" > /srv/unravel/zk_1_data/myid'
sudo -u unravel sh -c 'echo "2" > /srv/unravel/zk_2_data/myid'
sudo -u unravel sh -c 'echo "3" > /srv/unravel/zk_3_data/myid'

# Create MySQL root password for unravel install
cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c10 > /usr/local/unravel/mysqlrootpass
MYSQLROOTPASS=`cat /usr/local/unravel/mysqlrootpass`
echo "MySQL root password = $MYSQLROOTPASS"

cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c10 > /usr/local/unravel/mysqlunravelpass
MYSQLUNRAVELPASS=`cat /usr/local/unravel/mysqlunravelpass`
echo "MySQL unravel password = $MYSQLUNRAVELPASS"

sed -i -e "s/UMYSQLP/$MYSQLUNRAVELPASS/g" /usr/local/unravel/etc/unravel.properties

## Setup mysql root password on debconf
dpkg --configure -a
echo "mysql-server mysql-server/root_password password $MYSQLROOTPASS" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQLROOTPASS" | debconf-set-selections

## apt-get update
sudo apt-get update
sleep 10
echo "done with apt-get update"
echo "start installing mysql-server"
apt-get install --assume-yes mysql-server

# Changing mysql configuration for unravel
echo "stop mysql daemon and update configuration"
sudo systemctl stop mysql
sudo mv /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.org
sudo cp /usr/local/unravel/mysqld.cnf /etc/mysql/mysql.conf.d/

# Set LimitNOFILE for mysql to 128000
echo "set limit of open files for mysql to 128000"
sudo sh -c 'echo "LimitNOFILE=128000" >> /lib/systemd/system/mysql.service'
sudo cp /lib/systemd/system/mysql.service /etc/systemd/system/
sudo systemctl daemon-reload

# Starting mysql server with updated configuration file
echo "starting mysql server"
sudo systemctl start mysql
ps -ef |grep mysqld |head -1

### update mysql database 
echo "creating  unravel mysql database and user"

echo "create database unravel_mysql_prod DEFAULT CHARACTER SET utf8; grant all on unravel_mysql_prod.* TO 'unravel'@'%' IDENTIFIED BY '$MYSQLUNRAVELPASS'; use unravel_mysql_prod; source /usr/local/unravel/mysql_scripts/20170920015500.sql; source /usr/local/unravel/mysql_scripts/20171008153000.sql; source /usr/local/unravel/mysql_scripts/20171202224307.sql; source /usr/local/unravel/mysql_scripts/20180118103500.sql;" | mysql -u root -p$MYSQLROOTPASS

echo "use unravel_mysql_prod; INSERT  IGNORE INTO \`users\` (\`id\`, \`email\`, \`encrypted_password\`, \`reset_password_token\`, \`reset_password_sent_at\`, \`remember_created_at\`, \`sign_in_count\`, \`current_sign_in_at\`, \`last_sign_in_at\`, \`current_sign_in_ip\`, \`last_sign_in_ip\`, \`created_at\`, \`updated_at\`, \`login\`, \`uid\`, \`authentication_token\`) VALUES (1,'','\$2a\$10\$.8bk4e/5UgD.A5ok13lKvOiVdzh.IMRbwrN0pJbvFZvXZHTitl5Di',NULL,NULL,NULL,1,now(),now(),'127.0.0.1','127.0.0.1',now(),now(),'admin',NULL,NULL); COMMIT;" | mysql -u root -p$MYSQLROOTPASS

## Check cluster storage adl or wasb
LNUM=`awk '/fs.defaultFS/{ print NR; exit }' /etc/hadoop/*/0/core-site.xml`
NNUM=`expr $LNUM + 1`
SPROP=`sed "${NNUM}q;d" /etc/hadoop/*/0/core-site.xml |sed 's/<[^>]*>//g' |sed 's/^[ \t]*//' |cut -d: -f1`

echo "LNUM = $LNUM"
echo "NNUM = $NNUM"
echo "SPROP = $SPROP"

if [ "$SPROP" == "adl" ]; then echo "Storage is $SPROP" ; sed -i "s/wasb/$SPROP/g" /usr/local/unravel/etc/unravel.properties ; fi

cat /usr/local/unravel/etc/unravel.properties |grep spark-events

## change permission on unravel daemon scripts
chmod -R 755 /usr/local/unravel/init_scripts

sleep 30
## Starting unravel daemons
/usr/local/unravel/init_scripts/unravel_all.sh stop > /tmp/unravel_stop_output 2>&1
sleep 30
/usr/local/unravel/init_scripts/unravel_all.sh start > /tmp/unravel_start_output 2>&1

sleep 10
## Checking unravel daemons' status
/usr/local/unravel/init_scripts/unravel_all.sh status

# checking unravel kafka is running or not
KSTATUS=`/usr/local/unravel/init_scripts/unravel_k status |awk '{print $2}'`
echo "unravel kafak is in $KSTATUS mode"

if [ "$KSTATUS" == "Running" ]; then
   echo "unravel_k is in running status"
else
   echo "unravel_k is not in running status"
   /usr/local/unravel/init_scripts/unravel_all.sh restart > /tmp/unravel_restart_output 2>&1
fi

## Completed the phase1 setup
echo "All phase 1 processes are completed"
