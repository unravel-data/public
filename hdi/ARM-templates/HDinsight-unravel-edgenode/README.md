The ARM template "azuredeploy.json" file will deploy the unravel edge node, and this template only requires one parameter  and that is the clusterName of the HDinsight cluster.

The created edge node will run three custom action scripts, the source of this scripts are below

https://raw.githubusercontent.com/unravel-data/public/master/hdi/unravel-azure/scripts/unravel-edgenode.sh

https://raw.githubusercontent.com/unravel-data/public/master/hdi/unravel-azure/scripts/hdi_premises_sensor_deploy.sh

https://raw.githubusercontent.com/unravel-data/public/master/hdi/unravel-azure/scripts/unravel-instrumentation.sh

The first script will install unravel and start unravel daemons; and the 2nd script will do unravel sensors deployment to head,worker and edge nodes in the cluster; then the 3rd script will do unravel configuration that applies to HDinsight cluster configuration.

The unravel-edgenode.sh will download the unravel application from blob container in below path

https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-package.tar.gz

The unravel app will extracted on the edge node's /usr/local/unravel folder

and starting unravel daemons is done by 

/usr/local/unravel/init_scripts/unravel_all.sh start

The unravel sensors tar ball is also stored on Azure blob container in below path

https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-sensor.tar.gz

The hdi_premises_sensor_deploy.sh will deploy unravel sensor jar files into head, worker and edge nodes.

Sensor deployment persistence is kept for future head and worker nodes; but not for future new edge nodes.
For future new edge nodes; user requires to run this hdi_premises_sensor_deploy.sh script while deploying the future edge node.


The unravel-instrumentation script will run a python script /usr/local/unravel/hdi_onpremises_setup.py  and this will do the followings:

1. Make configuration changes on spark and hive
2. Restart required services on the HDinsight cluster

When the unravel edge node is successfully created; you can login to unravel UI portal
-- need to create ssh tunnel to access to the unravel node's port 3000
-- http://unravel_ip:3000
-- default unravel UI admin credential: admin / unraveldata

Jobs information should be displayed on Unravel UI -- Dashboard and Application tab



