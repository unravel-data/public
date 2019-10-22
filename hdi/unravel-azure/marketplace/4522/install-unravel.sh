MYSQL_HOST=$1
MYSQL_USER=$2
MYSQL_PASS=$3

RPM_URL="https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-4.5.2.2-Azure-latest.rpm"
PACKAGE_LOC="/unravel"

function WGET() {
    /usr/bin/wget $1 -O ${PACKAGE_LOC}/$(basename $1) -T 90
}

if [ ! -d $PACKAGE_LOC ]; then
    mkdir -p $PACKAGE_LOC
fi

#WGET ${RPM_URL}
# Prepare the VM for unravel rpm install
for package in "libaio" "lzop" "yum-utils"; do
    rpm -qa | grep $package
    if [ $? -eq 0 ]; then
        echo "$package already installed"
    else
        /usr/bin/yum install -y $package
    fi
done
 /usr/bin/yum install -y ntp
/usr/bin/systemctl enable ntpd
/usr/bin/systemctl start ntpd
/usr/bin/systemctl disable firewalld
/usr/bin/systemctl stop firewalld

/usr/sbin/iptables -F

/usr/sbin/setenforce 0
/usr/bin/sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config

#sleep 30

grep srv /etc/fstab
# Prepare disk for unravel
if [[ $? -eq 1 ]] && [[ -e "/dev/sdc" ]]; then
    mkdir -p /srv

    DATADISK=`/usr/bin/lsblk |grep sdc | awk '{print $1}'`
    echo $DATADISK > /tmp/datadisk
    echo "/dev/${DATADISK}1" > /tmp/dataprap

    echo "Partitioning Disk ${DATADISK}"
    echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${DATADISK}

    DATAPRAP=`cat /tmp/dataprap`
    DDISK=`cat /tmp/datadisk`
    /usr/sbin/mkfs -t ext4 ${DATAPRAP}

    DISKUUID=`/usr/sbin/blkid |grep ext4 |grep $DDISK  | awk '{ print $2}' |sed -e 's/"//g'`
    echo "${DISKUUID}    /srv   ext4 defaults  0 0" >> /etc/fstab

    /usr/bin/mount -a
fi

# install unravel rpm
/usr/bin/rpm  -U $PACKAGE_LOC/$(basename $RPM_URL)

/usr/bin/sleep 5

sudo chkconfig unravel_pg off
sudo chkconfig unravel_cw off

UN_ROOT_PATH="/usr/local/unravel"
WGET https://dev.mysql.com/get/mysql80-community-release-el7-1.noarch.rpm
WGET https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.47.tar.gz
cd $PACKAGE_LOC
tar xvzf $PACKAGE_LOC/mysql-connector-java-5.1.47.tar.gz
sudo rpm -ivh $PACKAGE_LOC/mysql80-community-release-el7-1.noarch.rpm
sudo yum-config-manager --disable mysql80-community
sudo yum-config-manager --enable mysql57-community
sudo yum install -y mysql-community-client
JDBC_JAR="$PACKAGE_LOC/mysql-connector-java-5.1.47/mysql-connector-java-5.1.47.jar"
JDBC_URL="jdbc:mariadb:\/\/${MYSQL_HOST}:3306\/unravel_mysql_prod"
if [ -f $JDBC_JAR ];then
    sudo mkdir -p $UN_ROOT_PATH/share/java
    sudo cp $JDBC_JAR $UN_ROOT_PATH/share/java/
     JDBC_URL="jdbc:mysql:\/\/${MYSQL_HOST}:3306\/unravel_mysql_prod"
fi

sudo -u unravel python $UN_ROOT_PATH/install_bin/properties_tracker.py

# Update Unravel Lic Key into the unravel.properties file
# Obtain a valid unravel Lic Key file ; the following is just non working one
UN_PROP_PATH='/usr/local/unravel/etc/unravel.properties'
echo "com.unraveldata.lic=1p6ed4s492012j5rb242rq3x3w702z1l455g501z2z4o2o4lo675555u3h" >> ${UN_PROP_PATH}

# Adding unravel properties for Azure Databricks Cloud
echo "com.unraveldata.onprem=false" >> ${UN_PROP_PATH}
echo "com.unraveldata.cluster.type=DB" >> ${UN_PROP_PATH}
echo "com.unraveldata.python.enabled=false" >> ${UN_PROP_PATH}
echo "com.unraveldata.tagging.enabled=true" >> ${UN_PROP_PATH}

sed -i -e "s/unravel.jdbc.password=.*/unravel.jdbc.password=${MYSQL_PASS}/g" ${UN_PROP_PATH}
sed -i -e "s/unravel.jdbc.url=.*/unravel.jdbc.url=${JDBC_URL}/g" ${UN_PROP_PATH}
sed -i -e "s/unravel.jdbc.username=.*/unravel.jdbc.username=${MYSQL_USER}/g" ${UN_PROP_PATH}

/usr/local/unravel/dbin/db_schema_upgrade.sh
/usr/local/unravel/install_bin/db_initial_inserts.sh | /usr/local/unravel/install_bin/db_access.sh

# Starting Unravel daemons
/etc/init.d/unravel_all.sh start
exit 0
