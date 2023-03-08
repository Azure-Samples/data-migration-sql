The following step-by-step instructions help you perform your first sku-recommendation for migrating from on-premises SQL Server to SQL Server running on an Azure VM, Azure SQL Managed Instance or Azure SQL Database by using Azure PowerShell. It consists of two steps:
- First step is to collect performance data of a given server.
- Second step is to run SKU-recommendation on collected performance data.

For this we will be using `Get-AzDataMigrationPerformanceDataCollection` command for performance data collection and `Get-AzDataMigrationSkuRecommendation` command for SKU recommendation.


## Prerequisites
- SQL Server with Windows authentication or SQL authentication access.
- [.Net Core 3.1](https://dotnet.microsoft.com/en-us/download/dotnet/3.1)
- Az.DataMigration Version 0.9.0 installed from [here](https://www.powershellgallery.com/packages/Az.DataMigration/0.9.0).


## Performance data collection using connection string

We can run a SQL server performance data collection using the `Get-AzDataMigrationPerformanceDataCollection` cmdlet. This cmdlet expects the following required parameters:

- *SqlConnectionStrings*: Connection string of the SQL server you want to collect performance data of. You can also provide multiple connection strings to collect performance data from multiple SQL server.
- *OutputFolder*: Output folder path where you want the data collection report to be stored. If this parameter is not provided default output folder depending on the OS platform is used.
- *PerfQueryInterval*: Interval at which to query performance data, in seconds.  Default: 30.
- *StaticQueryInterval*: Interval at which to query and persist static configuration data, in seconds.  Default: 3600.
- *NumberOfIterations*: Number of iterations of performance data collection to perform before persisting to file. For example, with default values, performance data will be persisted every 30 seconds * 20 iterations = 10 minutes. Minimum: 2.  Default: 20.

The following example runs performance data collection on a sample SQL server with the data collection report being saved in output folder in C drive with perf query interval, static query intervals and number of iteration as 10, 120 and 5 respectively. 

```
Get-AzDataMigrationPerformanceDataCollection -SqlConnectionStrings "Data Source=LabServer.database.net;Initial Catalog=master;Integrated Security=True" -OutputFolder "C:\Output" -PerfQueryInterval 10 -NumberOfIterations 5 -StaticQueryInterval 120
```

The command can be used as following for running assessment on multiple servers.
```
Get-AzDataMigrationPerformanceDataCollection -SqlConnectionStrings "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True", "Data Source=LabServer2.database.net;Initial Catalog=master;Integrated Security=True" -OutputFolder C:\Output -PerfQueryInterval 10 -NumberOfIterations 5 -StaticQueryInterval 120
```

## Performance Data Collection using config file

We can also pass a config file to the `Get-AzDataMigrationPerformanceDataCollection` cmdlet as a parameter to run performance data collection on SQL servers.

The config file has the following structure:
```
{
    "action": "PerfDataCollection",
    "outputFolder": "C:\\Output",
    "perfQueryIntervalInSec": 20,
    "staticQueryIntervalInSec": 120,
    "numberOfIterations": 7,
    "sqlConnectionStrings": [
        "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True;",
        "Data Source=LabServer2.database.net;Initial Catalog=master;Integrated Security=True;"
    ]
}
```

Here we introduce a new parameter `action`, which should be `PerfDataCollection` to run performance data collection. 


The config file can be passed to the cmdlet in the following way
```
Get-AzDataMigrationPerformanceDataCollection -ConfigFilePath "C:\Users\user\document\config.json"
```

## Get SKU Recommendation though console parameters.

We can get SKU recommendation for given SQL Server using the `Get-AzDataMigrationSkuRecommendation` cmdlet. This cmdlet expects the following required parameters:

- *OutputFolder*: Output folder path perf data collection report is present.
- *DisplayResult*: Enable this to display result onto the console.
- *Overwrite*: Enable this to overwrite existing SKU recommendation report (if any).
- *ElasticStrategy*: Enable this to use the elastic strategy for SKU recommendations based on resource usage profiling
- *ScalingFactor*: Scaling (comfort) factor used during SKU recommendation. For example, if it is determined that there is a 4 vCore CPU requirement with a scaling factor of 150%, then the true CPU requirement will be 6 vCores. Default: 100.
- *TargetPercentile*: Percentile of data points to be used during aggregation of the performance data. Only used for baseline (non-elastic) strategy. Default: 95.
- *TargetPlatform*: Target platform for SKU recommendation: either AzureSqlDatabase, AzureSqlManagedInstance, AzureSqlVirtualMachine, or Any. If Any is selected, then SKU recommendations for all three target platforms will be evaluated, and the best fit will be returned.  Default: Any.
- *TargetSqlInstance*: Name of the SQL instance for which SKU should be recommendeded. Default: outputFolder will be scanned for files created by the PerfDataCollection action, and recommendations will be provided for every SQL instance for which collected performance data is found.
- *StartTime*: UTC start time of performance data points to consider during aggregation, in YYYY-MM-DD HH:MM format. Only used for baseline (non-elastic) strategy. Default: all data points collected will be considered.
- *EndTime*: UTC end time of performance data points to consider during aggregation, in YYYY-MM-DD HH:MM format. Only used for baseline (non-elastic) strategy. Default: all data points collected will be considered.
- *DatabaseAllowList*: Space separated list of names of databases to be allowed for SKU recommendation consideration while excluding all others. Only set one of the following or neither: databaseAllowList, databaseDenyList. Default: null. Should be provided like this "Database1 Database2".
- *DatabaseDenyList*: Space separated list of names of databases to not be considered for SKU recommendation. Only set one of the following or neither: databaseAllowList, databaseDenyList. Default: null. Should be provided like this "Database1 Database2".


The following example runs get sku recommendation on a sample SQL server whose data collection report is saved in output folder in C drive with displaying the result on console and overwrite existing reports if any. 

```
Get-AzDataMigrationSkuRecommendation -OutputFolder "C:\Output" -DisplayResult -Overwrite 
```

##Assessment using config file

We can also pass a config file to the `Get-AzDataMigrationSkuRecommendation` cmdlet as a parameter to get SKU recommendation on SQL servers.

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
Get-AzDataMigrationSkuRecommendation -ConfigFilePath "C:\Users\user\document\config.json"
```

You can look into the output folder to find a HTML file which also gives the details of SKU being recommended and a JSON file storing different system parameters calculated and used for recommending a particular SKU. 
