## Perfoming Migration

In this article, we perform a offline migration of the Adventureworks database from SQL Server on-premises to an Azure SQL Database by using Microsoft Azure PowerShell. You can migrate databases from a SQL Server instance to an Azure SQL Database by using the Az.DataMigration module in Microsoft Azure PowerShell.

**In this article you learn how to**
- Create a resource group
- Create a Database Migration Service
- Register the Database Migration Service with self-hosted Integration Runtime
- Start an migration

**Note 1:** Please run the commands in PowerShell 5.x as an Administrator as `Register-AzDataMigrationIntegrationRuntime` command requires admin permissions. 

**Note 2:** You can add `-Debug` parameter to debug cmdlet execution.

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- Azure SQL Database with write access. You can create Azure SQL Database by following the detail in the article [Create a SQL Database](https://docs.microsoft.com/en-us/azure/azure-sql/database/single-database-create-quickstart?tabs=azure-portal)
- Already installed Integration Runtime or its downloaded .MSI. You can download it from [here](https://www.microsoft.com/en-in/download/details.aspx?id=39717).
- A completed assessment on the source SQL server to see if the migration to Azure SQL Database is possible or not. 
- Crate Azure SQL Database and perform schema migration from source database to it. Please follow the instructions [here](https://www.mssqltips.com/sqlservertip/5455/using-the-data-migration-assistant-dma-tool-to-migrate-from-sql-server-to-azure-sql-database) to perform schema migration using DMA.
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

- _Azure Resource Group name_: The resource group in which Database Migration Service is present.
- _SQL Migration Service name_: The name of the Database Migration Service whose authkeys you want to obtain.

The following example gets the authkeys of the service we previously created. We will be capturing the results of this command as we will be using it later on.

```
$authKeys = Get-AzDataMigrationSqlServiceAuthKey -ResourceGroupName "MyResourceGroup" -SqlMigrationServiceName "MySqlMigrationService"
```

We will be using these authkeys to register the service on Integration Runtime. `Register-AzDataMigrationIntegrationRuntime` expects the following parameters:

- _AuthKey_: Authkey of the Database Migration Service you want to register on IR.
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

## Start Database Migration

Use the New-AzDataMigrationToSqlDb cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- *SqlDbInstanceName*: Target SQL Database logical server to which source database is being migrated to.
- *ResourceGroupName*: Resource group in which Azure SQL Database instance is present.  
- *TargetDatabaseName*: The name of the migrated database in Azure SQL Database
- *Scope*: Resource Id of the Azure SQL Database logical server.
- *Kind*: Kind of Target to which migration is being performed. "SqlDb" in this case.
- *MigrationService*: Resource Id of the Database Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Azure SQL Database.
- *SourceDatabaseName*: Name of the source database that is being migrated to Azure SQL Database.
- *SourceSqlConnectionAuthentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- *SourceSqlConnectionDataSource*: The name or IP of a SQL Server instance.
- *SourceSqlConnectionUserName*: Username of the SQL Server instance.
- *SourceSqlConnectionPassword*: Password of the SQL Server instance.
- *TargetSqlConnectionAuthentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
- *TargetSqlConnectionDataSource*: The name or IP of Azure SQL Database logical server.
- *TargetSqlConnectionUserName*: Username of the Azure SQL Database.
- *TargetSqlConnectionPassword*: Password of the Azure SQL Database.
- *TableList*: In case if only selected tables are required to be migrated use this parameter to provide comma separated table names. 

Before using the New- Cmdlet we will have to convert the passwords to secure strings. The following command does this.

```
$sourcePass = ConvertTo-SecureString "password" -AsPlainText -Force
$targetPass = ConvertTo-SecureString "password" -AsPlainText -Force
```

The following example creates and starts a migration of complete source database with target database name AdventureWorksTarget:

```
New-AzDataMigrationToSqlDb `
-ResourceGroupName MyGroup `
-SqlDbInstanceName labserver `
-Kind "SqlDb" `
-TargetDbName AdventureWorksTarget `
-SourceDatabaseName AdventureWorks `
-SourceSqlConnectionAuthentication SQLAuthentication `
-SourceSqlConnectionDataSource LABSERVER.MICROSOFT.COM `
-SourceSqlConnectionUserName user `
-SourceSqlConnectionPassword $sourcePass `
-Scope "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.Sql/servers/labserver" `
-TargetSqlConnectionAuthentication SQLAuthentication `
-TargetSqlConnectionDataSource labserver.database.windows.net `
-TargetSqlConnectionUserName user `
-TargetSqlConnectionPassword $targetPass `
-MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MyService"
```

The following example creates and starts a migration of selected tables from source database with target database name AdventureWorksTarget:


```
New-AzDataMigrationToSqlDb `
-ResourceGroupName MyGroup `
-SqlDbInstanceName labserver `
-Kind "SqlDb" `
-TargetDbName AdventureWorksTarget `
-SourceDatabaseName AdventureWorks `
-SourceSqlConnectionAuthentication SQLAuthentication `
-SourceSqlConnectionDataSource LABSERVER.MICROSOFT.COM `
-SourceSqlConnectionUserName user `
-SourceSqlConnectionPassword $sourcePass `
-Scope "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.Sql/servers/labserver" `
-TargetSqlConnectionAuthentication SQLAuthentication `
-TargetSqlConnectionDataSource labserver.database.windows.net `
-TargetSqlConnectionUserName user `
-TargetSqlConnectionPassword $targetPass `
-TableList "[dbo].[Table_1]", "[dbo].[Table_2]" `
-MigrationService "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MyService"
```


## Monitoring Migration

To monitor the migration, check the status of task.

```
$migDetails = Get-AzDataMigrationToSqlDb -ResourceGroupName MyGroup -SqlDbInstanceName labserver -TargetDbName AdventureWorksTarget -Expand MigrationStatusDetails

#ProvisioningState should be Creating, Failed or Succeeded
$migDetails.ProvisioningState | Format-List

#MigrationStatus should be InProgress, Canceling, Failed or Succeeded
$migDetails.MigrationStatus | Format-List

#To view migration details at each backup file level
$migDetails.MigrationStatusDetail | select *

```
The migration is by default offline, so no cutover is required. The migration is completed when migration status changes to succeeded.

## Delete Database Migration Service Instance

After the migration is complete, you can delete the Azure Database Migration Service instance:

```
Remove-AzDataMigrationSqlService -ResourceGroupName "MyResourceGroup" -Name "MySqlMigrationService"
```

## Addition Resources on Cmdlets
- You can find the documentation of each of the cmdlets here : [DataMigration Cmdlets Doc](https://docs.microsoft.com/en-us/powershell/module/az.datamigration/?view=azps-7.2.0#data-migration).