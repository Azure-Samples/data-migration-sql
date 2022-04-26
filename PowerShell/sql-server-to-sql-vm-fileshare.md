## Perfoming Online Migration

In this article, we perform an online migration of the Adventureworks database from SQL Server on-premises to a SQL Server running on Azure Virtual Machine by using Microsoft Azure PowerShell. You can migrate databases from a SQL Server instance to a SQL Server running on Azure Virtual Machine by using the Az.DataMigration module in Microsoft Azure PowerShell.

**In this article you learn how to**
- Create a resource group
- Create a Database Migration Service
- Register the Database Migration Service with self-hosted Integration Runtime
- Start an online migration
- Perform cutover for the online migration

**Note 1:** Please run the commands in PowerShell 5.x as an Administrator as Register-AzDataMigrationIntegrationRuntime command requires admin permissions. 

**Note 2:** You can add `-Debug` parameter to debug cmdlet execution. 

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- Azure SQL Virtual Machine with write access. You can create Azure SQL Virtual Machine by following the detail in the article [Create a SQL Virtual Machine](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-vm-create-portal-quickstart)
- Already installed Integration Runtime or its downloaded .MSI. You can download it from [here](https://www.microsoft.com/en-in/download/details.aspx?id=39717).
- This exercise expects that you already have details of Fileshare where the backups are stored and an Azure Storage Account.
- Latest version of Az.DataMigration installed from [here](https://www.powershellgallery.com/packages/Az.DataMigration).

## Azure login 

Before we get started with managing Azure resources with Azure PowerShell we need to login into Azure and set our default subscription.

In the following example we login using the `Connect-AzAccount` command and select a particular subscription by passing `-Subscription` command.

```
Connect-AzAccount -Subscription <Subscription-id>
```

If you have already logged into Azure through PowerShell and want to change to subscription you are working with, please use the following command to change your subscription.

```
Set-AzContext -Subscription <Subscription-id>
```

## Create a Resource Group

An Azure resource group is a logical container in which Azure resources are deployed and managed.

Create a resource group by using the [New-AzResourceGroup](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup) command.

The following example creates a resource group named myResourceGroup in the East US 2 region.

```
New-AzResourceGroup -ResourceGroupName MyResourceGroup -Location EastUS2
```

## Create an instance of Database Migration Service

You can create new instance of Azure Database Migration Service by using the `New-AzDataMigrationSqlService` cmdlet. This cmdlet expects the following required parameters:

- _Azure Resource Group name_: You can use [New-AzResourceGroup](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup) command to create an Azure Resource group as previously shown and provide its name as a parameter.
- _SQL Migration Service name (or Name)_: String that corresponds to the desired unique service name for Azure Database Migration Service.
- _Location_: Specifies the location of the service. Specify an Azure data center location, such as West US or Southeast Asia.

The following example creates a service named MySqlMigrationService in the resource group MyResourceGroup located in the East US 2 region.

```
New-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService" -Location "EastUS2"
```

## Register Database Migration Service with self-hosted Integration Runtime

After creating the Database Migration Service, we need to register it on the Self-Hosted Integration Runtime. We register the service on IR using its AuthKeys which we can obtain using `Get-AzDataMigrationSqlServiceAuthKey` command. This command expects the following parameters:

- *Azure Resource Group name*: The resource group in which Database Migration Service is present.
- *SQL Migration Service name*: The name of the Database Migration Service whose authkeys you want to obtain.

The following example gets the authkeys of the service we previously created. We will be capturing the results of this command as we will be using it later on.

```
$authKeys = Get-AzDataMigrationSqlServiceAuthKey -ResourceGroupName "MyResourceGroup" -SqlMigrationServiceName "MySqlMigrationService"
```

We will be using these authkeys to register the service on Integration Runtime. `Register-AzDataMigrationIntegrationRuntime` expects the following parameters:

- *AuthKey*: Authkey of the Database Migration Service you want to register on IR.
- *Integration Runtime Path*: If the IR is not installed, you can pass its .MSI path as parameter to this command.

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

Use the New-AzDataMigrationToSqlVM cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- *SqlVirtualMachineName*: Target SQL Virtual Machine to which source database is being migrated to.
- *ResourceGroupName*: Resource group in which Azure SQL Virtual Machine is present.  
- *TargetDatabaseName*: The name of the migrated database in Azure SQL Virtual Machine.
- *Scope*: Resource Id of the Azure SQL Virtual Machine.
- *Kind*: Kind of Target to which migration is being performed. "SqlVm" in this case.
- *MigrationService*: Resource Id of the Database Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Azure SQL Virtual Machine.
- *SourceDatabaseName*: Name of the source database that is being migrated to Azure SQL Virtual Machine.
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

Before using the New- Cmdlet we will have to convert the passwords to secure strings. The following command does this.

```
$sourcePass = ConvertTo-SecureString "password" -AsPlainText -Force
$sourcrFileSharePass = ConvertTo-SecureString "password" -AsPlainText -Force
```

The following example creates and starts a migration with target database name MyDb:

```
New-AzDataMigrationToSqlVM `
    -ResourceGroupName "MyResourceGroup" `
    -SqlVirtualMachineName "MySqlVM" `
    -TargetDbName "MyDb" `
    -Kind "SqlVM" `
    -Scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachine/MySqlVM" `
    -MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -StorageAccountResourceId "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -StorageAccountKey "xxxxx" `
    -FileSharePath "\\filesharepath.com\SharedBackup\MyBackUps" `
    -FileShareUsername "filesharepath\User" `
    -FileSharePassword $sourceFileSharePass `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword $sourcePass `
    -SourceDatabaseName "AdventureWorks"
```

To start an offline migration, you should add `Offline` parameter. 

```
New-AzDataMigrationToSqlVM `
    -ResourceGroupName "MyResourceGroup" `
    -SqlVirtualMachineName "MySqlVM" `
    -TargetDbName "MyDb" `
    -Kind "SqlVM" `
    -Scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachine/MySqlVM" `
    -MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -StorageAccountResourceId "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -StorageAccountKey "xxxxx" `
    -FileSharePath "\\filesharepath.com\SharedBackup\MyBackUps" `
    -FileShareUsername "filesharepath\User" `
    -FileSharePassword $sourceFileSharePass `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword $sourcePass `
    -SourceDatabaseName "AdventureWorks"
    -Offline
```

## Monitoring Migration

To monitor the migration, check the status of task.

```
$migDetails = Get-AzDataMigrationToSqlVM -ResourceGroupName "MyResourceGroup" -SqlVirtualMachineName "MySqlVM" -TargetDbName "MyDb" -Expand MigrationStatusDetails

#ProvisioningState should be Creating, Failed or Succeeded
$migDetails.ProvisioningState | Format-List

#MigrationStatus should be InProgress, Canceling, Failed or Succeeded
$migDetails.MigrationStatus | Format-List

#To view migration details at each backup file level
$migDetails.MigrationStatusDetail | select *
```

The migration is ready for cutover when `PendingLogBackupCount` is zero and `IsBackupRestored` is true. These properties are returned as part of `Get-AzDataMigrationToSqlVM` with -Expand parameter provided.

## Performing cutover

With an online migration, a restore of provided backups of databases is performed, and then work proceeds on restoring the Transaction Logs stored in the BackupFileShare.

When the database in a Azure SQL Virtual Machine is updated with latest data and is in sync with the source database, you can perform a cutover.

We can perform cutover using the command `Invoke-AzDataMigrationCutoverToSqlVM`. This command accepts the following parameters:

- _SqlVirtualMachineName_: Target SQL Virtual Machine to which source database is being migrated to.
- _ResourceGroupName_: Resource group in which SQL Virtual Machine is present.
- _TargetDatabaseName_: The name with which the database will be stored in SQL Virtual Machine.
- _MigrationOperationId:_ Tracking ID of migration. Can be obtained through Get-\* operation.

The following example, we perform cutover on the earlier started migration. We obtain the `MigrationOperationId` through the properties returned in the `Get-AzDataMigrationToSqlVM` command.

```
#Obtain the MigrationOperationId
$vmMigration = Get-AzDataMigrationToSqlVM -ResourceGroupName "MyResourceGroup" -SqlVirtualMachineName "MySqlVM" -TargetDbName "MyDatabase"

#Perform Cutover 
Invoke-AzDataMigrationCutoverToSqlVM -ResourceGroupName "MyResourceGroup" -SqlVirtualMachineName "MySqlVM" -TargetDbName "MyDatabase" -MigrationOperationId $vmMigration.MigrationOperationId
```
## Delete Database Migration Service Instance

After the migration is complete, you can delete the Azure Database Migration Service instance:

```
Remove-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService"
```

## Addition Resources on Cmdlets

- You can find the documentation of each of the cmdlets here : [DataMigration Cmdlets Doc](https://docs.microsoft.com/powershell/module/az.datamigration/).