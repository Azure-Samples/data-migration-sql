The following step-by-step instructions help you perform your first sku-recommendation for migrating from on-premises SQL Server to SQL Server running on an Azure VM, Azure SQL Managed Instance or Azure SQL Database by using Azure CLI. It consists of two steps:
- First step is to collect performance data of a given server.
- Second step is to run SKU-recommendation on collected performance data.

For this we will be using `az datamigration performance-data-collection` command for performance data collection and `az datamigration get-sku-recommendation` command for sku-recommendation.


## Prerequisites
- SQL Server with Windows authentication or SQL authentication access.
- [.Net Core 3.1](https://dotnet.microsoft.com/en-us/download/dotnet/3.1)
- Azure CLI installed. You can do it using `pip install azure-cli` or follow the instructions [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
- `az datamigtation`  CLI extension installed. You can do it using `az extension add --name datamigration`. 


## Performance data collection using connection string

We can run a SQL server performance data collection using the `az datamigration performance-data-collection` cmdlet. This cmdlet expects the following required parameters:

- *--connection-string*: Connection string of the SQL server you want to collect performance data of. You can also provide multiple connection strings to collect performance data from multiple SQL server.
- *--output-folder*: Output folder path where you want the data collection report to be stored. If this parameter is not provided default output folder depending on the OS platform is used.
- *--perf-query-interval*: Interval at which to query performance data, in seconds.  Default: 30.
- *--static-query-interval*: Interval at which to query and persist static configuration data, in seconds.  Default: 3600.
- *--number-of-interation*: Number of iterations of performance data collection to perform before persisting to file. For example, with default values, performance data will be persisted every 30 seconds * 20 iterations = 10 minutes. Minimum: 2.  Default: 20.

The following example runs performance data collection on a sample SQL server with the data collection report being saved in output folder in C drive with perf query interval, static query intervals and number of iteration as 10, 120 and 5 respectively. 

```
az datamigration performance-data-collection --connection-string "Data Source=LabServer.database.net;Initial Catalog=master;Integrated Security=True" --output-folder "C:\Output" --perf-query-interval 10 --number-of-interation 5 --static-query-interval 120
```

The command can be used as following for running assessment on multiple servers.
```
az datamigration performance-data-collection --connection-string "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True", "Data Source=LabServer2.database.net;Initial Catalog=master;Integrated Security=True" --output-folder C:\Output --perf-query-interval 10 --number-of-interation 5 --static-query-interval 120
```

## Performance Data Collection using config file

We can also pass a config file to the `az datamigration performance-data-collection` cmdlet as a parameter to run performance data collection on SQL servers.

The config file has the following structure:
```
{
    "action": "PerfDataCollection",
    "outputFolder": "C:\\Output",
    "perfQueryIntervalInSec": 20,
    "staticQueryIntervalInSec": 120,
    "numberOfIterations": 7,
    "sqlConnectionStrings": [
        "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True;"
    ]
}
```

Here we introduce a new parameter `action`, which should be `PerfDataCollection` to run performance data collection. 


The config file can be passed to the cmdlet in the following way
```
az datamigration performance-data-collection --config-file-path "C:\Users\user\document\config.json"
```

## Get SKU Recommendation though console parameters.

We can get SKU recommendation for given SQL Server using the `az datamigration get-sku-recommendation` cmdlet. This cmdlet expects the following required parameters:

- *--output-folder*: Output folder path perf data collection report is present.
- *--display-result*: Enable this to display result onto the console.
- *--overwrite*: Enable this to overwrite existing SKU recommendation report (if any).
- *--elastic-strategy*: Enable this to use the elastic strategy for SKU recommendations based on resource usage profiling
- *--scaling-factor*: Scaling (comfort) factor used during SKU recommendation. For example, if it is determined that there is a 4 vCore CPU requirement with a scaling factor of 150%, then the true CPU requirement will be 6 vCores. Default: 100.
- *--target-percentile*: Percentile of data points to be used during aggregation of the performance data. Only used for baseline (non-elastic) strategy. Default: 95.
- *--target-platform*: Target platform for SKU recommendation: either AzureSqlDatabase, AzureSqlManagedInstance, AzureSqlVirtualMachine, or Any. If Any is selected, then SKU recommendations for all three target platforms will be evaluated, and the best fit will be returned.  Default: Any.
- *--target-sql-instance*: Name of the SQL instance for which SKU should be recommendeded. Default: outputFolder will be scanned for files created by the PerfDataCollection action, and recommendations will be provided for every SQL instance for which collected performance data is found.
- *--start-time*: UTC start time of performance data points to consider during aggregation, in YYYY-MM-DD HH:MM format. Only used for baseline (non-elastic) strategy. Default: all data points collected will be considered.
- *--end-time*: UTC end time of performance data points to consider during aggregation, in YYYY-MM-DD HH:MM format. Only used for baseline (non-elastic) strategy. Default: all data points collected will be considered.
- *--database-allow-list*: Space separated list of names of databases to be allowed for SKU recommendation consideration while excluding all others. Only set one of the following or neither: databaseAllowList, databaseDenyList. Default: null.
- *--database-deny-list*: Space separated list of names of databases to not be considered for SKU recommendation. Only set one of the following or neither: databaseAllowList, databaseDenyList. Default: null.


The following example runs get sku recommendation on a sample SQL server whose data collection report is saved in output folder in C drive with displaying the result on console and overwrite existing reports if any. 

```
az datamigration get-sku-recommendation --output-folder "C:\Output" --display-result --overwrite 
```

##Assessment using config file

We can also pass a config file to the `az datamigration get-sku-recommendation` cmdlet as a parameter to get SKU recommendation on SQL servers.

The config file has the following structure:
```
{
    "action": "GetSKURecommendation",
    "outputFolder": "C:\\Output",
    "overwrite":  "True",
    "displayResult": "True",
    "targetPlatform": "any",
    "scalingFactor": 1000
}
```

Here we introduce a new parameter `action`, which should be `GetSKURecommendation` to get SKU recommendation. 


The config file can be passed to the cmdlet in the following way
```
az datamigration get-sku-recommendation --config-file-path "C:\Users\user\document\config.json"
```

You can look into the output folder to find a HTML file which also gives the details of SKU being recommended and a JSON file storing different system parameters calculated and used for recommending a particular SKU. 