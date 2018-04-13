The ARM template "azuredeploy.json" file will deploy the unravel edge node, and this template only requires one parameter  and that is the clusterName of the HDinsight cluster.

The created edge node will run two custom action scripts, the source of this scripts are below

https://raw.githubusercontent.com/unravel-data/public/master/hdi/unravel-azure/scripts/unravel-edgenode.sh

https://raw.githubusercontent.com/unravel-data/public/master/hdi/unravel-azure/scripts/unravel-instrumentation.sh

The first script will install unravel and start unravel daemons; and the 2nd script will do unravel configuration that applies to HDinsight cluster configuration.

The unravel-edgenode.sh will download the unravel application from blob container in below path

https://unravelstorage01.blob.core.windows.net/unravel-app-blob-2018-04-13/unravel-package.tar.gz

The unravel app will extracted on the edge node's /usr/local/unravel folder

and starting unravel daemons is done by 

/usr/local/unravel/init_scripts/unravel_all.sh start


The unravel-instrumentation script will run a python script /usr/local/unravel/hdi_onpremises_setup.py  and this will do the followings:

1. Deploy unravel sensors jar files into head, worker, and edge nodes
2. Make configuration changes on spark and hive
3. Restart required services on the HDinsight cluster

When the unravel edge node is successfully created; you can login to unravel UI portal
-- need to create ssh tunnel to access to the unravel node's port 3000
-- http://unravel_ip:3000
-- default unravel UI admin credential: admin / unraveldata

Jobs information should be displayed on Unravel UI -- Dashboard and Application tab



