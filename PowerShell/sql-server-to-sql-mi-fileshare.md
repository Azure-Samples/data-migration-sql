
## Perfoming Online Migration

In this article, we perform a online migration of the Adventureworks database restored to an on-premises instance of SQL Server to an Azure SQL Managed Instance by using Microsoft Azure PowerShell. You can migrate databases from a SQL Server instance to an SQL Managed Instance by using the Az.DataMigration module in Microsoft Azure PowerShell.

**In this article you learn how to**
- Create a resource group
- Create a SQL Migration Service
- Register the SQL Migration Service on Integration Runtime
- Start an online migration
- Perform cutover for the online migration

**Note:** Please run the commands in PowerShell 5.x as an Administrator as Register-AzDataMigrationIntegrationRuntime command requires admin permissions. 

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- A SQL Managed Instance with write access. You can create a SQL Managed Instance by following the detail in the article [Create a SQL Managed Instance](https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/instance-create-quickstart)
- Already installed Integration Runtime or its downloaded .MSI. You can download it from [here](https://www.microsoft.com/en-in/download/details.aspx?id=39717).
- To have run assessment on the source SQL server to see if the migration to SQL Managed Instance is possible or not.
- This exercise expects that you already have details of Fileshare where the backups are stored and an Azure Storage Account.
- Az.DataMigration Version 0.8.0 installed from [here](https://www.powershellgallery.com/packages/Az.DataMigration/0.8.0).

## Create a Resource Group

An Azure resource group is a logical container in which Azure resources are deployed and managed.

Create a resource group by using the [New-AzResourceGroup](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup) command.

The following example creates a resource group named myResourceGroup in the East US 2 region.

```
New-AzResourceGroup -ResourceGroupName MyResourceGroup -Location EastUS2
```

## Create an instance of SQL Migration Service

You can create new instance of Azure SQL Migration Service by using the `New-AzDataMigrationSqlService` cmdlet. This cmdlet expects the following required parameters:

- _Azure Resource Group name_: You can use [New-AzResourceGroup](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup) command to create an Azure Resource group as previously shown and provide its name as a parameter.
- _SQL Migration Service name (or Name)_: String that corresponds to the desired unique service name for Azure SQL Migration Service.
- _Location_: Specifies the location of the service. Specify an Azure data center location, such as West US or Southeast Asia.

The following example creates a service named MySqlMigrationService in the resource group MyResourceGroup located in the East US 2 region.

```
New-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService" -Location "EastUS2"
```
## Register SQL Migration Service on Integration Runtime

After creating the SQL Migration Service, we need to register it on the Self-Hosted Integration Runtime. We register the service on IR using its AuthKeys which we can obtain using `Get-AzDataMigrationSqlServiceAuthKey` command. This command expects the following parameters:

- _Azure Resource Group name_: The resource group in which SQL Migration Service is present.
- _SQL Migration Service name_: The name of the SQL Migration Service whose authkeys you want to obtain.

The following example gets the authkeys of the service we previously created. We will be capturing the results of this command as we will be using it later on.

```
$authKeys = Get-AzDataMigrationSqlServiceAuthKey -ResourceGroupName "MyResourceGroup" -SqlMigrationServiceName "MySqlMigrationService"
```

We will be using these authkeys to register the service on Integration Runtime. `Register-AzDataMigrationIntegrationRuntime` expects the following parameters:

- _AuthKey_: Authkey of the SQL Migration Service you want to register on IR.
- _Integration Runtime Path_: If the IR is not installed, you can pass its .MSI path as parameter to this command.

In the following example, we pass the previously obtained authkeys and the path of Integration Runtime .MSI to install Integration Runtime and register the service on it.

```
Register-AzDataMigrationIntegrationRuntime -AuthKey $authKeys.AuthKey1 -IntegrationRuntimePath "C:\Users\user\Downloads\IntegrationRuntime.msi"
```

If you already have Integration Runtime installed you can just pass the AuthKey to the above command.

```
Register-AzDataMigrationIntegrationRuntime -AuthKey $authKeys.AuthKey1
```

**Note**: You might get this error if you are using PowerShell 7.x. `get-wmiobject is not recognized as a name of a cmdlet`. Switch to PowerShell 5.x to avoid this error.

## Start Online Database Migration

Use the New-AzDataMigrationToSqlManagedInstance cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- *ManagedInstanceName*: Target Managed Instance to which source database is being migrated to.
- *ResourceGroupName*: Resource group in which SQL Managed Instance is present.  
- *TargetDatabaseName*: The name with which the database will be stored in SQL Managed Instance.
- *Scope*: Resource Id of the SQL Managed Instance.
- *Kind*: Kind of Target to which migration is being performed. "SqlMi" in this case.
- *MigrationService*: Resource Id of the SQL Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Managed Instance.
- *SourceDatabaseName*: Name of the source database that is being migrated to SQL Managed Instance.
- *SourceSqlConnectionAuthentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- *SourceSqlConnectionDataSource*: The name or IP of a SQL Server instance.
- *SourceSqlConnectionUserName*: Username of the SQL Server instance.
- *SourceSqlConnectionPassword*: Password of the SQL Server instance.
- *FileSharePath*: FileShare path representing the local network share that contains the database backup files.
- *FileShareUsername*: Username of the fileshare.
- *FileSharePassword*: Password of the fileshare
- *StorageAccountResourceId*: Resource Id of the storage account for uploading backup files.
- *StorageAccountKey*: The key of Storage Account.
- *Offline*: Switch parameter used for performing offline migration.

The following example creates and starts an online migration with target database name MyDb:

```
New-AzDataMigrationToSqlManagedInstance `
    -ResourceGroupName "MyResourceGroup" `
    -ManagedInstanceName "MyManagedInstance" `
    -TargetDbName "MyDb" `
    -Kind "SqlMI" `
    -Scope "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
    -MigrationService "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -StorageAccountResourceId "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -StorageAccountKey "dwidjwiwnnwiojnnmskoam==adnkdnwdnwknk" `
    -FileSharePath "\\filesharepath.com\SharedBackup\MyBackUps" `
    -FileShareUsername "filesharepath\User" `
    -FileSharePassword "password" `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword "password" `
    -SourceDatabaseName "AdventureWorks"
```

To start an offline migration, you should add `Offline` parameter.


```
New-AzDataMigrationToSqlManagedInstance `
    -ResourceGroupName "MyResourceGroup" `
    -ManagedInstanceName "MyManagedInstance" `
    -TargetDbName "MyDb" `
    -Kind "SqlMI" `
    -Scope "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
    -MigrationService "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -StorageAccountResourceId "/subscriptions/f890983-56793-782e7-378-3563829e/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -StorageAccountKey "dwidjwiwnnwiojnnmskoam==adnkdnwdnwknk" `
    -FileSharePath "\\filesharepath.com\SharedBackup\MyBackUps" `
    -FileShareUsername "filesharepath\User" `
    -FileSharePassword "password" `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword "password" `
    -SourceDatabaseName "AdventureWorks" `
    -Offline
```

**Working Command**
```
New-AzDataMigrationToSqlManagedInstance `
    -ResourceGroupName "MigrationTesting" `
    -ManagedInstanceName "migrationtestmi" `
    -TargetDbName "<<DB Name>>" `
    -Kind "SqlMI" `
    -Scope "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/MigrationTesting/providers/Microsoft.Sql/managedInstances/migrationtestmi" `
    -MigrationService "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/tsum38RG/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService1" `
    -StorageAccountResourceId "/subscriptions/f133ff51-53dc-4486-a487-47049d50ab9e/resourceGroups/aaskhan/providers/Microsoft.Storage/storageAccounts/aasimmigrationtest" `
    -StorageAccountKey "<<Key>>" `
    -FileSharePath "\\aalab03-2k8.redmond.corp.microsoft.com\SharedBackup\tsuman" `
    -FileShareUsername "AALAB03-2K8\hijavatestlocaluse" `
    -FileSharePassword "testAdmin123" `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "AALAB03-2K8.REDMOND.CORP.MICROSOFT.COM" `
    -SourceSqlConnectionUserName "hijavatestuser1" `
    -SourceSqlConnectionPassword "testAdmin123" `
    -SourceDatabaseName "AdventureWorks"
```


## Monitoring Migration

To monitor the migration, check the status of task.

```
$migDetails = Get-AzDataMigrationToSqlManagedInstance -ResourceGroupName "MyResourceGroup" -ManagedInstanceName "MyManagedInstance" -TargetDbName "MyDatabase" -Expand MigrationStatusDetails

#ProvisioningState should be Creating, Failed or Succeeded
$migDetails.ProvisioningState | Format-List

#MigrationStatus should be InProgress, Canceling, Failed or Succeeded
$migDetails.MigrationStatus | Format-List

#To view migration details at each backup file level
$migDetails.MigrationStatusDetail | select *

```

The migration is ready for cutover when `PendingLogBackupCount` is zero and `IsBackupRestored` is true. These properties are returned as part of `Get-AzDataMigrationToSqlManagedInstance` with -Expand parameter provided.

## Performing cutover

With an online migration, a full backup and restore of databases is performed, and then work proceeds on restoring the Transaction Logs stored in the BackupFileShare.

When the database in a Azure SQL Managed Instance is updated with latest data and is in sync with the source database, you can perform a cutover.

We can perform cutover using the command `Invoke-AzDataMigrationCutoverToSqlManagedInstance`. This command accepts the following parameters:

- _ManagedInstanceName_: Target SQL Managed Instance to which source database is being migrated to.
- _ResourceGroupName_: Resource group in which SQL Managed Instance is present.
- _TargetDatabaseName_: The name with which the database will be stored in SQL Managed Instance.
- _MigrationOperationId:_ Tracking ID of migration. Can be obtained through Get-\* operation.

The following example, we perform cutover on the earlier started migration. We obtain the `MigrationOperationId` through the properties returned in the `Get-AzDataMigrationToSqlManagedInstance` command.

```
#Obtain the MigrationOperationId
$miMigration = Get-AzDataMigrationToSqlManagedInstance -ResourceGroupName "MyResourceGroup" -ManagedInstanceName "MyManagedInstance" -TargetDbName "MyDb"

#Perform Cutover 
Invoke-AzDataMigrationCutoverToSqlManagedInstance -ResourceGroupName "MyResourceGroup" -ManagedInstanceName "MyManagedInstance" -TargetDbName "MyDb" -MigrationOperationId $miMigration.MigrationOperationId
```
## Delete SQL Migration Service Instance

After the migration is complete, you can delete the Azure SQL Migration Service instance:

```
Remove-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService"
```

## Addition Resources on Cmdlets
- You can find the documentation of each of the cmdlets here : [DataMigration Cmdlets Doc](https://docs.microsoft.com/en-us/powershell/module/az.datamigration/?view=azps-7.2.0#data-migration).