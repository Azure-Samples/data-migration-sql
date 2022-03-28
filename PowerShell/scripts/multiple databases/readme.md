There are 3 configuration files involved :-
# user-config.json
This files contains some user decisions. The parameters in user-config.json are explained below:-
"NewDMS" : set to true if a new sql dms is reuired
"NewDMSLocation", "NewDMSRG", "NewDMSName" are the parameters required to create a new dms (will be used only if "NewDMS" is set to true)
"DMSName" and "DMSRG" are the name and resource group of an existing DMS that you'd like to register to SHIR
"InstallIR" : set to true if SHIR needs installation
"IRPath" : path where SHIR is downloaded (will be used only if InstallIR is set to true)
"BlobFileshare" : (blob/fileshare)
"Cutover" : if set to true, the script waits till the database is ready for cutover and then initiates cutover
"WaitTillCompletion" : if set to true, the script waits till the migration status becomes "Suceeded" or "Failed"
"LogFailedDbs" : If set to true, failed migrations are recorded in logs.json
Sample user-config.json file :-

```
{
    "NewDMS": false,
    "NewDMSLocation": "eastus2",
    "NewDMSRG": "tsum38RG",
    "NewDMSName": "scriptdms32",
    "DMSName": "dms20211030",
    "DMSRG": "tsum38RG",
    "InstallIR": false,
    "IRPath": "",
    "BlobFileshare": "fileshare",
    "Cutover": true,
    "LogFailedDbs": true
}

```
# migration-db-config.json 
This file contains the parameters specific to a  new database migration.
Sample migration-db-config.json file :-

```
{
    "ResourceGroupName": null,
    
    "Scope": null,
    "MigrationService": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/tsum38RG/providers/Microsoft.DataMigration/SqlMigrationServices/dms20211030",

    "StorageAccountResourceId": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/aaskhan/providers/Microsoft.Storage/storageAccounts/aasimmigrationtest",
    "StorageAccountKey": "oEqjDHjf1N8SM4gPTVbMPlnN9u6PPHjzpsYvFIcpYYw98ux2CAdfM/5ePeuMa4PbAYBQv+4RApQ5Wz+VQV3dXA==",

    "SourceSqlConnectionAuthentication": null,
    "SourceSqlConnectionDataSource": null,
    "SourceSqlConnectionUserName": null,
    "SourceSqlConnectionPassword": null,

    "SourceDatabaseName": null,
    "TargetDbName": null,
    
    "Kind": null,
    "ManagedInstanceName": "migrationtestmi",
    "SqlVirtualMachineName": "DMSCmdletTest-SqlVM",

    "FileSharePath": "\\\\aalab03-2k8.redmond.corp.microsoft.com\\SharedBackup\\vmanhas",
    "FileShareUsername": "AALAB03-2K8\\hijavatestlocaluser",
    "FileSharePassword": "testAdmin123",

    "AzureBlobAccountKey": "kmJRR2wIwl8NMbTK/tRih7oueYNxKL0hTnonMjR4o2BiY1FDN4yof95GVJL3jBZaZEq1GuL3q1WMIDGCAizngQ==",
    "AzureBlobContainerName": "tsum38-adventureworks",
    "AzureBlobStorageAccountResourceId": "/subscriptions/fc04246f-04c5-437e-ac5e-206a19e7193f/resourceGroups/tzppesignoff1211/providers/Microsoft.Storage/storageAccounts/hijavateststorage",
    "OfflineConfigurationLastBackupName": "",

    "Offline": null
}

```
# migration-server-config.json 
This file contains an array of server related information (like authentication, data source, username, poassword and databases within a server to migrate)
If "DatabasesFromSourceSql" is set to true, the databases are retrieved from source server based on the sql query: "SqlQueryToGetDbs"
Set "Kind" to either "SqlMi" or "SqlVm" to choose Managed instance or Virtual Machine respectively.
Set "BlobFileshare" to either "blob" or "fileshare"
Set Offline to true for an offline migration
Set Cutover to true if u want to perform cutover
Sample migration-server-config.json :-

```
    {
    "Servers" : [
                {
                    "SourceSqlConnectionAuthentication": "SqlAuthentication",
                    "SourceSqlConnectionDataSource": "AALAB03-2K8.REDMOND.CORP.MICROSOFT.COM",
                    "SourceSqlConnectionUserName": "hijavatestuser1",
                    "SourceSqlConnectionPassword": "testAdmin123",
                    "Kind": "SqlMi",
                    "ResourceGroupName": "MigrationTesting",   
                    "Scope": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/MigrationTesting/providers/Microsoft.Sql/managedInstances/migrationtestmi",
                    "BlobFileshare" : "fileshare",
                    "Offline" : false,
                    "DatabasesFromSourceSql" : false,                  
                    "SqlQueryToGetDbs" : "select name from sys.databases where name not in ('master', 'tempdb', 'model', 'msdb') and is_distributor <> 1 and name like 'trgt'",
                    "databases" : [
                        "trgt",
                        "AdventureWorks"                     
                    ],
                    "Cutover" : true
                },
                {
                    "SourceSqlConnectionAuthentication": "SqlAuthentication",
                    "SourceSqlConnectionDataSource": "AALAB03-2K8.REDMOND.CORP.MICROSOFT.COM",
                    "SourceSqlConnectionUserName": "hijavatestuser1",
                    "SourceSqlConnectionPassword": "testAdmin123",
                    "Kind": "SqlMi",
                    "BlobFileshare" : "fileshare",
                    "Offline" : false,
                    "ResourceGroupName": "tsum38RG",   
                    "Scope": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/tsum38RG/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachines/DMSCmdletTest-SqlVM",
                    "DatabasesFromSourceSql": true,
                    "SqlQueryToGetDbs": "select name from sys.databases where name not in ('master', 'tempdb', 'model', 'msdb') and is_distributor <> 1 and name like 'trgt'",
                    "databases" : [
                        "trgt"
                    ],
                    "Cutover" : false
                }
                ]
    }
    
```

# dbsStarted.txt
This text file record the server and db for which migration has started. This should be kept empty before starting the migrations

# logs.json
This file records the failed dbs
