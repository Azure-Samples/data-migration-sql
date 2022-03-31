
The MultiServerMigration.bat script performs an end to end migration of a multiple databases in multiple servers.
 
Assumptions:
- Database Migration Service that is being used for migration is already created and online (registered on SHIR) if the backups are in fileshare.
- The target db will have the same name as source db.
- Each database has unique name as this allows the JsonDump folder to have unique _migrationStatus_DBName.json and _migrationStatusCreate_DBName.json for each database. This also helps in having unqiue operation messages when running the script. This operation message can be like `Starting Migration to SqlMi for TargetDB <TargetDbName>`.
- The fileshare or the Storage account container contains at least all the backup files of the databases being migarated from for a particular server. 
- Any of the parameters you provide in the Json files doesn't has any ',' character (As ',' is used as a delimiter when reading the Json)

There are few files to take user input (user-config.json and files in ServersConfig folder - _ServerList.txt, <ServerName>.db.txt, <ServerName>.specs.json, <ServerName>.source-location.json) :-

# user-config.json

user-config.json contains some user decisions. The parameters in user-config.json are explained below:-

- *WaitTillCompletion* : If set to true, the script waits till migration is completed (Succeded or failed). Only works for offline migrations.
- *Cutover* : If set to true, the script waits till the database is ready for cutover and then initiates cutover. Only for online migrations.
- *Offline* : If set to true, all the migrations are done in offline mode.

Sample user-config.json file :-
```Json
{
  "WaitTillCompletion": true,
  "Cutover": true,
  "Offline": false
}
```

# ServersConfig Folder

This folder contains the details of ther servers and databases that are required to be migrated to Azure SQL MI or Azure SQL VM. It contains files like:

- *_ServerList.txt*: To store the list of servers whose databases are to be migrated to Azure SQL Targets.
- *<ServerName>.db.txt*: To store the list of databases to be migrated from the given server <ServerName>.
- *<ServerName>.specs.json*: To contains the parameters specific to a new database migration. These paramter to server level parameters and remain constant for a server.
- *<ServerName>.source-location.json*: To store the details where backups are stored (fileshare or blob).

Please find below the details on how to customize these files and view ServerConfig folder for more details.


# _ServerList.txt

_ServerList.txt stores the list of the servers whose databases are to be migrated to Azure SQL Targets. 

```
Server1
Server2
```

# <ServerName>.db.txt

<ServerName>.db.txt stores the list of the databases to be migrated from the given server <ServerName> to Azure SQL Targets. 

```
Server1Database1
Server1Database2
```

# <ServerName>.specs.json

<ServerName>.specs.json contains the parameters specific to a new database migration. The parameters are explained below:-

- *ResourceGroupName*: Resource group in which Target SQL platform is present.
- *Scope*: Resource Id of the Target SQL platform. 
- *MigrationService*: Resource Id of the SQL Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Target SQL platform.
- *SourceSqlConnectionAuthentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- *SourceSqlConnectionDataSource*: The name or IP of a SQL Server instance.
- *SourceSqlConnectionUserName*: Username of the SQL Server instance.
- *SourceSqlConnectionPassword*: Password of the SQL Server instance.
- *Kind*: Kind of Target to which migration is being performed. "SqlMi" or "SqlVm".
- *ManagedInstanceName*: Target Managed Instance to which source database is being migrated to. 
- *SqlVirtualMachineName*: Target SQL VM to which source database is being migrated to.
- *StorageAccountResourceId*: Resource Id of the storage account for uploading backup files. To be provided when backups are in network fileshare.
- *StorageAccountKey*: The key of Storage Account.
- *<DBName>_LastBackupName*: Last backup file that will be restored to be used in case of Blob Offline migration. It is unique for each database.
- *BlobFileshare* : (blob/fileshare) - Where backups are stored.

Sample <ServerName>.specs.json files :-

For Target SQL Plaform as MI and Backups in Blob case:-

```Json
{
  "ResourceGroupName": "RG1",
  "Scope": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.Sql/managedInstances/MyManagedInstance1",
  "MigrationService": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.DataMigration/SqlMigrationServices/DMSIR1",
  "SourceSqlConnectionAuthentication": "SqlAuthentication",
  "SourceSqlConnectionDataSource": "Server1",
  "SourceSqlConnectionUserName": "<placeholder>",
  "SourceSqlConnectionPassword": "<placeholder>",
  "Kind": "SqlMi",
  "ManagedInstanceName": "MyManagedInstance1",
  "SqlVirtualMachineName": null,
  "StorageAccountResourceId": null,
  "StorageAccountKey": null,
  "Server1Database1_LastBackupName": null,
  "Server1Database2_LastBackupName": null,
  "BlobFileshare": "blob"
}
```

For Target SQL Plaform as VM and Backups in Fileshare case:-

```Json
{
  "ResourceGroupName": "RG2",
  "Scope": "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/RG/providers/Microsoft.SqlVirtualMachine/SqlVirtualMachines/MySqlVM2",
  "MigrationService": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.DataMigration/SqlMigrationServices/DMSIR2",
  "SourceSqlConnectionAuthentication": "SqlAuthentication",
  "SourceSqlConnectionDataSource": "Server2",
  "SourceSqlConnectionUserName": "<placeholder>",
  "SourceSqlConnectionPassword": "<placeholder>",
  "Kind": "SqlVm",
  "ManagedInstanceName": null,
  "SqlVirtualMachineName": "MySqlVM2",
  "StorageAccountResourceId": "/subscriptions/111111-11111-11111-111111/resourceGroups/RG/providers/Microsoft.Storage/storageAccounts/MyStorage2",
  "StorageAccountKey": "<placeholder>",
  "Server2Database1_LastBackupName": null,
  "Server2Database2_LastBackupName": null,
  "BlobFileshare": "fileshare"
}
```

# <ServerName>.source-location.json

<ServerName>.source-location.json is used as the paramter for the source location of backups when creating migration. Depending on the source backup location it can have two types of format. 

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
