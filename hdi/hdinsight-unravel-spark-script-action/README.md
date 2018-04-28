### Unravel_hdi_spark_bootstrap_3.0.sh

2018-04-28 [8be4c10](https://github.com/unravel-data/public/commit/8be4c10c4dbeb4c94bd2fda7abb73aabba3c389b)
* version v 1.1.1
* Add spark-defaults config exception handler in line 2784 to 2806 (Now compatable with hadoop and hive cluster)
* Move final_check.py log to foreground (stdout in ambari task)

2018-04-24 [65996e0](https://github.com/unravel-data/public/commit/65996e0cfb8414131b20f04ea16bc35ee7046564#diff-c51bcbd7156924c9c5a9a5191536b10a)
* version v 1.1.0
* Embedded HDInsightUtilities-v01.sh from line 1767 ~ 1878
* Add Condition and echo error message when `wget lzo-core-1.0.5.jar` fail twice in 30 seconds line 862 ~ 873
