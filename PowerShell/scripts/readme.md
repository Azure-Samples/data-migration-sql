
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
  "NewDMSLocation": "eastus2euap",
  "NewDMSRG": "test388RG",
  "NewDMSName": "script2",
  "DMSName": "dms20211030",
  "DMSRG": "test38RG",
  "InstallIR": false,
  "IRPath": "C:\\Users\\testuser\\Downloads\\IntegrationRuntime_5.13.8013.1.msi",
  "BlobFileshare": "fileshare",
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
    "ResourceGroupName": "MigrationTesting",
    "TargetDbName": "at_scriptFileMiOn2",
    "Scope": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Sql/managedInstances/migrationtestmi",
    "MigrationService": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms20211030",
    "StorageAccountResourceId": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Storage/storageAccounts/migrationtest",
    "StorageAccountKey": "xxxxx",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "SQLServer001",
    "SourceSqlConnectionUserName": "testuser1",
    "SourceSqlConnectionPassword": "testAdmin123",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "migrationtestmi",
    "FileSharePath": "\\\\SQLServer001\\SharedBackup\\loc",
    "FileShareUsername": "DOMAIN\\testlocaluser",
    "FileSharePassword": "testAdmin123",
    "Offline": false
  }

```

For MI Offline blob case:-

```
  {
    "ResourceGroupName": "MigrationTesting",
    "TargetDbName": "at_scriptBlobMiOff",
    "Scope": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Sql/managedInstances/migrationtestmi",
    "MigrationService": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms20211030",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "SQLServer001",
    "SourceSqlConnectionUserName": "testuser1",
    "SourceSqlConnectionPassword": "testAdmin123",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "migrationtestmi",
    "AzureBlobAccountKey": "xxxxx",
    "AzureBlobContainerName": "t-adventureworks",
    "AzureBlobStorageAccountResourceId": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Storage/storageAccounts/teststorage",
    "OfflineConfigurationLastBackupName": "AdventureWorksTransactionLog2.trn",
    "Offline": true
  }

```
For MI Online Blob case :-

```
  {
    "ResourceGroupName": "MigrationTesting",
    "TargetDbName": "at_scriptBlobMiOn2",
    "Scope": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Sql/managedInstances/migrationtestmi",
    "MigrationService": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.DataMigration/SqlMigrationServices/dms20211030",
    "SourceSqlConnectionAuthentication": "SqlAuthentication",
    "SourceSqlConnectionDataSource": "SQLServer001",
    "SourceSqlConnectionUserName": "testuser1",
    "SourceSqlConnectionPassword": "testAdmin123",
    "SourceDatabaseName": "AdventureWorks",
    "Kind": "SqlMi",
    "ManagedInstanceName": "migrationtestmi",
    "AzureBlobAccountKey": "xxxxx",
    "AzureBlobContainerName": "t-adventureworks",
    "AzureBlobStorageAccountResourceId": "/subscriptions/MySubscriptionID/resourceGroups/MyRG/providers/Microsoft.Storage/storageAccounts/teststorage",
    "Offline": false
  }

```