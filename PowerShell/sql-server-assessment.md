The following step-by-step instructions help you perform your first assessment for migrating to on-premises SQL Server, SQL Server running on an Azure VM, or Azure SQL Database by using PowerShell.

For this we will be using `Get-AzDataMigrationAssessment` command of Az.DataMigration module.


## Prerequisites

- SQL Server with Windows authentication or SQL authentication access.
- [.Net Core 3.1](https://dotnet.microsoft.com/en-us/download/dotnet/3.1)
- Az.DataMigration Version 0.8.0 installed from [here](https://www.powershellgallery.com/packages/Az.DataMigration/0.8.0).

## Assessment using connection string

We can run a SQL server assessment using the `Get-AzDataMigrationAssessment` cmdlet. This cmdlet expects the following required parameters:

- *ConnectionString*: Connection string of the SQL server you want to run assessment on. You can also provide multiple connection strings to run assessment on multiple SQL server.
- *OutputFolder*: Output folder path where you want the assessment report to be stored. If this parameter is not provided default output folder depending on the OS platform is used.
- *Overwrite*: This is a switch parameter which can be enabled to overwrite the existing report in that output folder. Currently enabling this parameter is the only way to save the assessment report. 

The following example runs the assessment on a sample SQL server with the assessment report being saved in output folder in C drive.

```
Get-AzDataMigrationAssessment -ConnectionString "Data Source=LabServer.database.net;Initial Catalog=master;Integrated Security=True" -OutputFolder "C:\Output" -Overwrite
```
The command can be used as following for running assessment on multiple servers.
```
Get-AzDataMigrationAssessment -ConnectionString "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True", "Data Source=LabServer2.database.net;Initial Catalog=master;Integrated Security=True" -OutputFolder C:\Output -Overwrite
```

## Assessment using config file

We can also pass a config file to the `Get-AzDataMigrationAssessment` cmdlet as a parameter to run assessment on SQL servers.

The config file has the following structure:
```
{
    "action": "Assess",
    "outputFolder": "C:\\Output",
    "overwrite":  "True",
    "sqlConnectionStrings": [
        "Data Source=LabServer1.database.net;Initial Catalog=master;Integrated Security=True;"
    ]
}
```
Here we introduce a new parameter `action`, which should be `Assess` to run assessments. 

The config file can be passed to the cmdlet in the following way
```
Get-AzDataMigrationAssessment -ConfigFilePath "C:\Users\user\document\config.json"
```
Futher details on `Get-AzDataMigrationAssessment` cmdlet can be found [here](https://docs.microsoft.com/en-us/powershell/module/az.datamigration/get-azdatamigrationassessment?view=azps-7.2.0).

## Understanding the Assessment report

The following gives a simple sample of the Assessment report structure. 

```
{
  "Status": "",
  "AssessmentId": "",
  "Servers": [
    {
      "ServerAssessments": [],
      "TargetReadinesses": {
        "AzureSqlDatabase": {},
        "AzureSqlManagedInstance": {}
      },
      "Properties": {},
      "Errors": [],
      "Status": "Completed",
      "Databases": [
        {
          "DatabaseAssessments": [
            {
              "ServerName": "",
              "DatabaseName": "",
              "DatabaseRestoreFails": false,
              "FeatureId": "",
              "IssueCategory": "Warning",
              "ImpactedObjects": [],
              "MoreInformation": "",
              "RuleMetadata": {},
              "RuleScope": "Database",
              "AppliesToMigrationTargetPlatform": "AzureSqlManagedInstance",
              "Timestamp": ""
            }
          ],
          "TargetReadinesses": {
            "AzureSqlDatabase": {},
            "AzureSqlManagedInstance": {}
          },
          "Properties": {},
          "Errors": [],
          "Status": "Completed",
          "FeatureDiscoveryTimeElapse": ""
        }
      ]
    }
  ],
  "Errors": [],
  "StartedOn": "",
  "EndedOn": ""
}
```
Few Important Properties in the Json report:
- *$.ServerAssessment*: Contains the server level assessment report.
- *$.TargetReadiness.AzureSqlManagedInstance*: Contains the list of databases that are ready for migration to SQL Managed Instance. 
- *$.TargetReadiness.AzureSqlDatabase*: Contains the list of databases that are ready for migration to SQL Database.
- *$.Database*: Contains database level assessment report.
- *$.Database.DatabaseAssessment*: Stores the list of different issues that are were found during the assessment of the database.
- *$.Database.DatabaseAssessment.IssueCategory*: Tells to which category does the given issue belong to. It can take values like Warning and Error.  
- *$.Database.DatabaseAssessment.DatabaseRestoreFails*: Tells whether the restore backup operation of will fail or not. In many cases databases having issues with IssueCategory "Error" can also be migrated to SQL targets, given the issue doesn't causes the restore to fail.  
- *$.Database.DatabaseAssessment.RuleMetadata*: Contains additional information on the issue.
- *$.Database.TargetReadinesses*: Contains the details whether the given database is ready for migration to different SQL targets like Managed Instance and Database.
- *$.Errors*:If the assessment fails due to any error, the error property stores the error details. 
