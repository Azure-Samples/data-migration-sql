There are 3 configuration files involved :-
# user-config.json
This files contains some user decisions. The parameters in user-config.json are explained below:-
"NewDMS" : set to true if a new sql dms is reuired
"NewDMSLocation", "NewDMSRG", "NewDMSName" are the parameters required to create a new dms (will be used only if "NewDMS" is set to true)
"DMSName" and "DMSRG" are the name and resource group of an existing DMS that you'd like to register to SHIR
"InstallIR" : set to true if SHIR needs installation
"IRPath" : path where SHIR is downloaded (will be used only if InstallIR is set to true)
"BlobFileshare" : (blob/fileshare)
"WaitTillCompletion" : if set to true, the script waits till the migration status becomes "Suceeded" or "Failed"
"LogFailedDbs" : If set to true, failed migrations are recorded in logs.json
Sample user-config.json file :-

```
{
    "NewDMS": false,
    "NewDMSLocation": "eastus2",
    "NewDMSRG": "myRG",
    "NewDMSName": "mewDMS",
    "DMSName": "dms",
    "DMSRG": "myRG",
    "InstallIR": false,
    "IRPath": "",
    "BlobFileshare": "fileshare",
    "LogFailedDbs": true
}

```
# migration-db-config.json 
This file contains the parameters specific to a  new database migration. They are all null and will be filled up during the execution of the script
Sample migration-db-config.json file :-

```
{
    "ResourceGroupName": null,
    
    "Scope": null,
    "MigrationService": null,

    "StorageAccountResourceId": null,
    "StorageAccountKey": null,

    "SourceSqlConnectionAuthentication": null,
    "SourceSqlConnectionDataSource": null,
    "SourceSqlConnectionUserName": null,
    "SourceSqlConnectionPassword": null,

    "TargetSqlConnectionAuthentication": null,
    "TargetSqlConnectionDataSource": null,
    "TargetSqlConnectionPassword": null,
    "TargetSqlConnectionUserName": null,
    

    "SourceDatabaseName": null,
    "TargetDbName": null,
    
    "Kind": null,
    "ManagedInstanceName": null,
    "SqlVirtualMachineName": null,
    "SqlDbInstanceName": null,

    "FileSharePath": null,
    "FileShareUsername": null,
    "FileSharePassword": null,

    "AzureBlobAccountKey": null,
    "AzureBlobContainerName": null,
    "AzureBlobStorageAccountResourceId": null,
    "OfflineConfigurationLastBackupName": null,

    "Offline": null,
    "WarningAction": "SilentlyContinue"
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
                        "SourceSqlConnectionDataSource": "abc.REDMOND.CORP.MICROSOFT.COM",
                        "SourceSqlConnectionUserName": "user",
                        "SourceSqlConnectionPassword": "password",
                    
                        "TargetSqlConnectionAuthentication": "SqlAuthentication",
                        "TargetSqlConnectionDataSource": "sqldb.database.windows.net",
                        "TargetSqlConnectionPassword": "pass123",
                        "TargetSqlConnectionUserName": "user",
                    
                        "SourceDatabaseName": null,
                        "TargetDbName": null,
                    
                        "MigrationService": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
                    
                        "StorageAccountResourceId": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/rg2/providers/Microsoft.Storage/storageAccounts/storage",
                        "StorageAccountKey": "aaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccc",
                    
                        "Kind": "SqlMi",
                        "ResourceGroupName": "migRG",   
                    
                        "Scope": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/migRG/providers/Microsoft.Sql/managedInstances/mi",
                    
                        "BlobFileshare" : "fileshare",
                    
                        "Offline" : false,
                    
                        "ManagedInstanceName": "mi",
                    
                        "SqlVirtualMachineName": "my-SQLVM",

                        "SqlDbInstanceName": "sqldb",

                        "FileSharePath": "\\\\abc.redmond.corp.microsoft.com\\SharedBackup\\user",
                        "FileShareUsername": "abc\\localuser",
                        "FileSharePassword": "pass",

                        "AzureBlobAccountKey": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        "AzureBlobContainerName": "blob",
                        "AzureBlobStorageAccountResourceId": "/subscriptions/111-222-111-222-3333/resourceGroups/rg1231/providers/Microsoft.Storage/storageAccounts/storage",
                        "OfflineConfigurationLastBackupName": "",
                    
                        "DatabasesFromSourceSql" : false,                  
                        "SqlQueryToGetDbs" : "select name from sys.databases where name not in ('master', 'tempdb', 'model', 'msdb') and is_distributor <> 1 and name like 'trgt'",
                        "databases" : [
                            "AdventureWorks"                     
                        ],
                    
                        "Cutover" : true
                    },
                    {
                        "SourceSqlConnectionAuthentication": "SqlAuthentication",
                        "SourceSqlConnectionDataSource": "onpremsqlserver.fareast.corp.microsoft.com",
                        "SourceSqlConnectionUserName": "user",
                        "SourceSqlConnectionPassword": "pass",
                    
                        "TargetSqlConnectionAuthentication": "SqlAuthentication",
                        "TargetSqlConnectionDataSource": "sqldb.database.windows.net",
                        "TargetSqlConnectionPassword": "pass123",
                        "TargetSqlConnectionUserName": "demouser",
                    
                        "SourceDatabaseName": null,
                        "TargetDbName": null,
                    
                        "MigrationService": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
                    
                        "StorageAccountResourceId": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/rg2/providers/Microsoft.Storage/storageAccounts/storage",
                        "StorageAccountKey": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    
                        "Kind": "SqlDb",
                        "ResourceGroupName": "myRG",   
                    
                        "Scope": "/subscriptions/11111-222222-333333333-2222-1111/resourceGroups/myRG/providers/Microsoft.Sql/servers/sqldb",
                    
                        "BlobFileshare" : "fileshare",
                    
                        "Offline" : true,
                    
                        "ManagedInstanceName": "mi",
                    
                        "SqlVirtualMachineName": "my-SQLVM",

                        "SqlDbInstanceName": "sqldb",

                        "FileSharePath": "\\\\abc.redmond.corp.microsoft.com\\SharedBackup\\vmanhas",
                        "FileShareUsername": "abc\\localuser",
                        "FileSharePassword": "pass",

                        "AzureBlobAccountKey": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        "AzureBlobContainerName": "blob",
                        "AzureBlobStorageAccountResourceId": "/subscriptions/111-222-111-222-3333/resourceGroups/rg1231/providers/Microsoft.Storage/storageAccounts/storage",
                        "OfflineConfigurationLastBackupName": "",

                        "DatabasesFromSourceSql" : false,                  
                        "SqlQueryToGetDbs" : "select name from sys.databases where name not in ('master', 'tempdb', 'model', 'msdb') and is_distributor <> 1 and name like 'trgt'",
                        "databases" : [
                            "adv1"                    
                        ],
                    
                        "Cutover" : true
                    }
                    ]
    }
    
```

# dbsStarted.txt
This text file record the server and db for which migration has started. This should be kept empty before starting the migrations

# logs.json
This file records the failed dbs
