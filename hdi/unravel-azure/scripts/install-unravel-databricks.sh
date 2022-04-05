MYSQL_HOST=$1
MYSQL_USER=$2
MYSQL_PASS=$3

PACKAGE_LOC="/unravel"
UN_ROOT_PATH="/opt/unravel"
UNRAVEL_USER="unravel"

if [ ! -d $UN_ROOT_PATH ]; then
    mkdir -p $UN_ROOT_PATH
fi

# check user exists
id -u $UNRAVEL_USER > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Creating user $UNRAVEL_USER"
    useradd -m "$UNRAVEL_USER"
fi

# Prepare the VM for unravel rpm install
/usr/bin/systemctl enable ntpd
/usr/bin/systemctl start ntpd
/usr/bin/systemctl disable firewalld
/usr/bin/systemctl stop firewalld

/usr/sbin/iptables -F

/usr/sbin/setenforce 0
/usr/bin/sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config

#sleep 30

grep ${UN_ROOT_PATH} /etc/fstab
# Prepare disk for unravel
if [[ $? -eq 1 ]] && [[ -e "/dev/sdc" ]]; then

    DATADISK=`/usr/bin/lsblk |grep sdc | awk '{print $1}'`
    echo $DATADISK > /tmp/datadisk
    echo "/dev/${DATADISK}1" > /tmp/dataprap

    echo "Partitioning Disk ${DATADISK}"
    echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/${DATADISK}

    DATAPRAP=`cat /tmp/dataprap`
    DDISK=`cat /tmp/datadisk`
    /usr/sbin/mkfs -t ext4 ${DATAPRAP}

    DISKUUID=`/usr/sbin/blkid |grep ext4 |grep $DDISK  | awk '{ print $2}' |sed -e 's/"//g'`
    echo "${DISKUUID}    ${UN_ROOT_PATH}   ext4 defaults  0 0" >> /etc/fstab

    /usr/bin/mount -a
fi

# install unravel tarball
tar -xf ${PACKAGE_LOC}/unravel-*.tar.gz -C "$(dirname $UN_ROOT_PATH)"
chown -R "$UNRAVEL_USER":"$UNRAVEL_USER" ${UN_ROOT_PATH}

sudo -u "$UNRAVEL_USER" ${UN_ROOT_PATH}/versions/*/setup --extra ${PACKAGE_LOC}  --external-database mysql "$MYSQL_HOST" 3306 "unravel_mysql_prod" "$MYSQL_USER" "$MYSQL_PASS" --enable-databricks --skip-precheck




# Starting Unravel daemons
sudo -u "$UNRAVEL_USER" ${UN_ROOT_PATH}/manager start
exit 0
