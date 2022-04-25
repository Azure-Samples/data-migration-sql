
## Perfoming Online Migration

In this article, we perform a online migration of the Adventureworks database restored to an on-premises instance of SQL Server to an Azure SQL Managed Instance by using Microsoft Azure PowerShell. Here, our backups files are present in Azure Blob storage. You can migrate databases from a SQL Server instance to an SQL Managed Instance by using the Az.DataMigration module in Microsoft Azure PowerShell.

**In this article you learn how to**

- Create a resource group
- Create a SQL Migration Service
- Start an online migration
- Perform cutover for the online migration

**Note 1:** You can add `-Debug` parameter to debug cmdlet execution. 

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- A SQL Managed Instance with write access. You can create a SQL Managed Instance by following the detail in the article [Create a SQL Managed Instance](https://docs.microsoft.com/en-us/azure/azure-sql/managed-instance/instance-create-quickstart)
- To have run assessment on the source SQL server to see if the migration to SQL Managed Instance is possible or not.
- Azure blob storage with back up files.
- Latest version of Az.DataMigration installed from [here](https://www.powershellgallery.com/packages/Az.DataMigration).

## Azure login 

Before we get started with managing azure resources with Azure PowerShell we need to login into azure and set our default subscription.

In the following example we login using the `Connect-AzAccount` command and select a particular subscription by passing `-Subscription` command.

```
Connect-AzAccount -Subscription <Subscription-id>
```

If you have already logged into azure through PowerShell and want to change to subscription you are working with, please use the following command to change your subscription.

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

## Create an instance of SQL Migration Service

You can create new instance of Azure SQL Migration Service by using the `New-AzDataMigrationSqlService` cmdlet. This cmdlet expects the following required parameters:

- _Azure Resource Group name_: You can use [New-AzResourceGroup](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup) command to create an Azure Resource group as previously shown and provide its name as a parameter.
- _SQL Migration Service name (or Name)_: String that corresponds to the desired unique service name for Azure SQL Migration Service.
- _Location_: Specifies the location of the service. Specify an Azure data center location, such as West US or Southeast Asia.

The following example creates a service named MySqlMigrationService in the resource group MyResourceGroup located in the East US 2 region.

```
New-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService" -Location "EastUS2"
```
When using azure blob storage for backups, we don't need to register Migration Service on Integration Runtime.

## Start Online Database Migration

Use the New-AzDataMigrationToSqlManagedInstance cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- _ManagedInstanceName_: Target Managed Instance to which source database is being migrated to.
- _ResourceGroupName_: Resource group in which SQL Managed Instance is present.
- _TargetDatabaseName_: The name with which the database will be stored in SQL Managed Instance.
- _Scope_: Resource Id of the SQL Managed Instance.
- _Kind_: Kind of Target to which migration is being performed. "SqlMi" in this case.
- _MigrationService_: Resource Id of the SQL Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Managed Instance.
- _SourceDatabaseName_: Name of the source database that is being migrated to SQL Managed Instance.
- _SourceSqlConnectionAuthentication_: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- _SourceSqlConnectionDataSource_: The name or IP of a SQL Server instance.
- _SourceSqlConnectionUserName_: Username of the SQL Server instance.
- _SourceSqlConnectionPassword_: Password of the SQL Server instance.
- _AzureBlobStorageAccountResourceId_: Resource Id of the blob storage account with backup files.
- _AzureBlobAccountKey_: The key of Azure Blob Account.
- _AzureBlobContainerName_: Container in Azure Blob Account with backup files.
- _Offline_: Switch parameter used for performing offline migration.
- _OfflineConfigurationLastBackupName_: Last backup file that will be restored.

Before using the New- Cmdlet we will have to convert the passwords to secure strings. The following command does this.

```
$sourcePass = ConvertTo-SecureString "password" -AsPlainText -Force
```


The following example creates and starts an online migration with target database name MyDb:

```
New-AzDataMigrationToSqlManagedInstance `
    -ResourceGroupName "MyResourceGroup" `
    -ManagedInstanceName "MyManagedInstance" `
    -TargetDbName "MyDb" `
    -Kind "SqlMI" `
    -Scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
    -MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -AzureBlobStorageAccountResourceId "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -AzureBlobAccountKey "xxxxx" `
    -AzureBlobContainerName "BlobContainer" `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword $sourcePass `
    -SourceDatabaseName "AdventureWorks"
```

To start an offline migration, you should add `Offline` parameter and the last backup file to be restored.

```
New-AzDataMigrationToSqlManagedInstance `
    -ResourceGroupName "MyResourceGroup" `
    -ManagedInstanceName "MyManagedInstance" `
    -TargetDbName "MyDb" `
    -Kind "SqlMI" `
    -Scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
    -MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
    -AzureBlobStorageAccountResourceId "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount" `
    -AzureBlobAccountKey "xxxxx" `
    -AzureBlobContainerName "BlobContainer" `
    -SourceSqlConnectionAuthentication "SqlAuthentication" `
    -SourceSqlConnectionDataSource "LabServer.database.net" `
    -SourceSqlConnectionUserName "User" `
    -SourceSqlConnectionPassword $sourcePass `
    -SourceDatabaseName "AdventureWorks" `
    -Offline `
    -OfflineConfigurationLastBackupName "AdventureWorksTransactionLog2.trn"
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

The migration is ready for cutover when `CurrentRestoringFilename` is equal to `LastRestoredFilename`. These properties are returned as part of `Get-AzDataMigrationToSqlManagedInstance` with -Expand parameter provided.

## Performing cutover

With an online migration, a restore of provided backups of databases is performed, and then work proceeds on restoring the Transaction Logs stored in the Blob storage.

When the database in a Azure SQL Managed Instance is updated with latest data and is in sync with the source database, you can perform a cutover.

We can perform cutover using the command `Invoke-AzDataMigrationCutoverToSqlManagedInstance`. This command accepts the following parameters:

- _ManagedInstanceName_: Target SQL Managed Instance to which source database is being migrated to.
- _ResourceGroupName_: Resource group in which SQL Managed Instance is present.
- _TargetDatabaseName_: The name with which the database will be stored in SQL Managed Instance.
- _MigrationOperationId:_ Tracking ID of migration. Can be obtained through Get-\* operation.

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

- You can find the documentation of each of the cmdlets here : [DataMigration Cmdlets Doc](https://docs.microsoft.com/powershell/module/az.datamigration/).