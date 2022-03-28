
The EndToEndDataMigration.bat script performs an end to end migration of a single database. 
It assumes that you have already installed SHIR if the DMS service is not online and migration is to fileshare.
There are 3 files to take user input (user-config.json, migration-db-config.json and source-location.json) :-

# user-config.json

user-config.json contains some user decisions. The parameters in user-config.json are explained below:-

- *NewDMS* : Set to true if a new DMS is required to be created
- *NewDMSLocation*, *NewDMSRG*, *NewDMSName* are the parameters required to create a new DMS (will be used only if "NewDMS" is set to true)
- *DMSName* and *DMSRG* are the name and resource group of an existing DMS that you'd like to register to SHIR
- *BlobFileshare* : (blob/fileshare) - Where backups are stored.
- *Cutover* : If set to true, the script waits till the database is ready for cutover and then initiates cutover. Only for online migrations.
- *WaitTillCompletion* : If set to true, the script waits till migration is completed (Succeded or failed). Only works for offline migrations.

Sample user-config.json file :-
```Json
{
  "NewDMS": false,
  "NewDMSLocation": "eastus2",
  "NewDMSRG": "NewRG",
  "NewDMSName": "NewDMSIR",
  "DMSName": "DMSIR",
  "DMSRG": "RG",
  "BlobFileshare": "blob",
  "WaitTillCompletion": true,
  "Cutover": true
}
```

# migration-db-config.json

migration-db-config.json contains the parameters specific to a new database migration. The parameters in user-config.json are explained below:-

- *ResourceGroupName*: Resource group in which Target SQL platform is present.
- *TargetDbName*: The name with which the database will be stored in Target SQL platform.
- *Scope*: Resource Id of the Target SQL platform. 
- *MigrationService*: Resource Id of the SQL Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Target SQL platform.
- *SourceSqlConnectionAuthentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- *SourceSqlConnectionDataSource*: The name or IP of a SQL Server instance.
- *SourceSqlConnectionUserName*: Username of the SQL Server instance.
- *SourceSqlConnectionPassword*: Password of the SQL Server instance.
- *SourceDatabaseName*: Name of the source database that is being migrated.
- *Kind*: Kind of Target to which migration is being performed. "SqlMi" or "SqlVm".
- *ManagedInstanceName*: Target Managed Instance to which source database is being migrated to. 
- *SqlVirtualMachineName*: Target SQL VM to which source database is being migrated to.
- *StorageAccountResourceId*: Resource Id of the storage account for uploading backup files. To be provided when backups are in network fileshare.
- *StorageAccountKey*: The key of Storage Account.
- *OfflineConfigurationLastBackupName*: Last backup file that will be restored to be used in case of Blob Offline migration.
- *Offline*: Switch parameter used for performing offline migration.

Sample migration-db-config.json files :-

For MI Online case :-

```Json
{
  "ResourceGroupName": "RG",
  "TargetDbName": "DatabaseAzure",
  "Scope": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.Sql/managedInstances/MyManagedInstance",
  "MigrationService": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.DataMigration/SqlMigrationServices/DMSIR",
  "SourceSqlConnectionAuthentication": "SqlAuthentication",
  "SourceSqlConnectionDataSource": "<placeholder>",
  "SourceSqlConnectionUserName": "<placeholder>",
  "SourceSqlConnectionPassword": "<placeholder>",
  "SourceDatabaseName": "Database1",
  "Kind": "SqlMi",
  "ManagedInstanceName": "MyManagedInstance",
  "SqlVirtualMachineName": null,
  "StorageAccountResourceId": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.Storage/storageAccounts/MyStorage",
  "StorageAccountKey": "<placeholder>",
  "OfflineConfigurationLastBackupName": null,
  "Offline": false
}
```

For VM Offline case:-

```Json
{
  "ResourceGroupName": "RG",
  "TargetDbName": "DatabaseAzure",
  "Scope": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/RG/providers/Microsoft.SqlVirtualMachine/SqlVirtualMachines/MySqlVM",
  "MigrationService": "/subscriptions/111111-11111-11111-111111/resourceGroups/tsum38RG/providers/Microsoft.DataMigration/SqlMigrationServices/DMSIR",
  "SourceSqlConnectionAuthentication": "SqlAuthentication",
  "SourceSqlConnectionDataSource": "<placeholder>",
  "SourceSqlConnectionUserName": "<placeholder>",
  "SourceSqlConnectionPassword": "<placeholder>",
  "SourceDatabaseName": "Database1",
  "Kind": "SqlVm",
  "ManagedInstanceName": null,
  "SqlVirtualMachineName": "MySqlVM",
  "StorageAccountResourceId": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.Storage/storageAccounts/MyStorage",
  "StorageAccountKey": "<placeholder>",
  "OfflineConfigurationLastBackupName": "DatabaseLog.trn",
  "Offline": true
}
```

# source-location.json

source-location.json is used as the paramter for the source location of backups when creating migration. Depending on the source backup location it can have two types of format. 

## Backups are in fileshare

```Json
{
  "fileShare": {
    "path": "<Placeholder>",
    "password": "<Placeholder>",
    "username": "<Placeholder>"
  }
}
```

## Backups are in Azure Blob Storage

```Json
{
  "AzureBlob": {
    "storageAccountResourceId": "/subscriptions/1111-2222-3333-4444/resourceGroups/RG/prooviders/Microsoft.Storage/storageAccounts/MyStorage",
    "accountKey": "======AccountKey====",
    "blobContainerName": "ContanerName-X"
  }
}
```