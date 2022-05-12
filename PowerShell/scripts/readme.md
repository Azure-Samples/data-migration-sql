
The EndToEndDataMigration.ps1 script performs an end to end migration of a single database. 
There are 2 files to take user input (user-config.json and migration-db-config.json) :-

# user-config.json

user-config.json contains some user decisions. The parameters in user-config.json are explained below:-

"NewDMS" : set to true if a new sql dms is reuired
"NewDMSLocation", "NewDMSRG", "NewDMSName" are the parameters required to create a new dms (will be used only if "NewDMS" is set to true)
"DMSName" and "DMSRG" are the name and resource group of an existing DMS that you'd like to register to SHIR
"InstallIR" : set to true if SHIR needs installation
"IRPath" : path where SHIR is downloaded (will be used only if InstallIR is set to true)
"BlobFileshare" : (blob/fileshare)
"Cutover" : if set to true, the script waits till the database is ready for cutover and then initiates cutover
"WaitTillCompletion" : if set to true, the script waits till the migration status becomes "Suceeded" or "Failed"

Sample user-config.json file :-
```
 {
  "NewDMS": false,
  "NewDMSLocation": "eastus2",
  "NewDMSRG": "myRG",
  "NewDMSName": "dms32",
  "DMSName": "dms",
  "DMSRG": "myRG",
  "InstallIR": false,
  "IRPath": "",
  "BlobFileshare": "blob",
  "WaitTillCompletion": true,
  "Cutover": true
}

```
# migration-db-config.json

migration-db-config.json contains the parameters specific to a  new database migration. Some samples are given below:-
Sample migration-db-config.json files :-

For MI Online fileshare case :-

```
{
    "ResourceGroupName": "migrationRG",
    "TargetDbName": "abc",
    "Scope": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/migrationRG/providers/Microsoft.Sql/managedInstances/myMI",
    "MigrationService": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
    "StorageAccountResourceId": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/rg2/providers/Microsoft.Storage/storageAccounts/storageabc",
    "StorageAccountKey": "aaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "abc.REDMOND.CORP.MICROSOFT.COM",
    "SourceSqlConnectionUserName": "user",
    "SourceSqlConnectionPassword": "password",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "myMI",
    "FileSharePath": "\\\\abc.redmond.corp.microsoft.com\\SharedBackup\\user",
    "FileShareUsername": "abc\\user",
    "FileSharePassword": "password",
    "Offline": false
  }

```

For MI Offline blob case:-

```
  {
    "ResourceGroupName": "migrationRG",
    "TargetDbName": "abc2",
    "Scope": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/migrationRG/providers/Microsoft.Sql/managedInstances/myMI",
    "MigrationService": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "abc.REDMOND.CORP.MICROSOFT.COM",
    "SourceSqlConnectionUserName": "user",
    "SourceSqlConnectionPassword": "password",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "myMI",
    "AzureBlobAccountKey": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccc",
    "AzureBlobContainerName": "blob",
    "AzureBlobStorageAccountResourceId": "/subscriptions/11-22222222222-3333333-222222-111111/resourceGroups/rg211/providers/Microsoft.Storage/storageAccounts/storage",
    "OfflineConfigurationLastBackupName": "AdventureWorksTransactionLog2.trn",
    "Offline": true
  }

```
For MI Online Blob case :-

```
  {
    "ResourceGroupName": "migrationRG",
    "TargetDbName": "abc3",
    "Scope": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/migrationRG/providers/Microsoft.Sql/managedInstances/myMI",
    "MigrationService": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "abc.REDMOND.CORP.MICROSOFT.COM",
    "SourceSqlConnectionUserName": "user",
    "SourceSqlConnectionPassword": "password",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "myMI",
    "AzureBlobAccountKey": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccccccccccc",
    "AzureBlobContainerName": "tsum38-adventureworks",
    "AzureBlobStorageAccountResourceId": "/subscriptions/11-22222222222-3333333-222222-111111/resourceGroups/rg211/providers/Microsoft.Storage/storageAccounts/storage",
    "Offline": false
  }

```
For SQL DB case :-

```
  {
  "ResourceGroupName": "myRG",
  "TargetDbName": "abc4",
  "Scope": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/myRG/providers/Microsoft.SqlVirtualMachine/SqlVirtualMachines/my-SQLVM",
  "MigrationService": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/myRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms",
  "SourceSqlConnectionAuthentication": "SqlAuthentication",
  "SourceSqlConnectionDataSource": "abc.REDMOND.CORP.MICROSOFT.COM",
  "SourceSqlConnectionUserName": "user",
  "SourceSqlConnectionPassword": "password",
  "SourceDatabaseName": "AdventureWorks",
  "Kind": "SqlVm",
  "ManagedInstanceName": "myMI",
  "SqlVirtualMachineName": "my-SQLVM",
  "SqlDbInstanceName": "sqldb",
  "TargetSqlConnectionAuthentication": "SqlAuthentication",
  "TargetSqlConnectionDataSource": "sqldb.database.windows.net",
  "TargetSqlConnectionPassword": "pass123",
  "TargetSqlConnectionUserName": "user",
  "FileSharePath": "\\\\abc.redmond.corp.microsoft.com\\SharedBackup\\user",
  "FileShareUsername": "abc\\user",
  "FileSharePassword": "password",
  "StorageAccountResourceId": "/subscriptions/1111-2222-1111-2222-3333/resourceGroups/rg2/providers/Microsoft.Storage/storageAccounts/storageabc",
  "StorageAccountKey": "aaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc",
  "AzureBlobAccountKey": "aaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccccc",
  "AzureBlobContainerName": "blob",
  "AzureBlobStorageAccountResourceId": "/subscriptions/11-22222222222-3333333-222222-111111/resourceGroups/rg211/providers/Microsoft.Storage/storageAccounts/storage",
  "OfflineConfigurationLastBackupName": "AdventureWorksTransactionLog2.trn",
  "Offline": true,
  "WarningAction": "SilentlyContinue"
}

```