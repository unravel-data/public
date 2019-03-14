The bash script U42_cleanup_and_U443_install.sh is intended for upgrade of unravel 4.2 to unravel 4.4.3.0 in Azure VM

This script will do the followings:

1. Uninstall unravel 4.2
2. Clean up unravel 4.2 
3. Install unravel 4.4.3.0
4. Add new user "hdfs" and new group "hadoop" if unravel VM doesn't have it
5. Switch unravel running user to hdfs
6. Update unravel.properties and unravel.ext.sh files
7. Start the unravel 4.4.3.0
