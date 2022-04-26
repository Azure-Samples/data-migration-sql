Note: 

- <b>Please run the commands in Azure CLI Administrator Mode as az datamigration register-integration-runtime command requires admin permissions.</b>
- <b> Both Migration Service and Azure SQL Managed Instance or SQL Server on Azure Virtual Machine or Azure SQL Database  must be in the same location.</b>

## Perfoming Migration

In this article, we perform an offline migration of the Adventureworks database from SQL Server on-premises to an Azure SQL Database by using Microsoft Azure CLI. You can migrate databases from a SQL Server instance to Azure SQL Database by using the DataMigration extension in Microsoft Azure CLI.

**In this article you learn how to**

- Create a resource group
- Create a Database Migration Service
- Register the Database Migration Service with self-hosted Integration Runtime
- Start an migration

**Note 1**: The query parameter shown in this tutorial works with PowerShell only and not with cmd. If you are using cmd, please manually copy and paste the parameters mentioned.

**Note 2:** Please run the commands as an Administrator as `az datamigration register-integration-runtime` command requires admin permissions.

**Note 3:** You can add `--debug` parameter to debug command execution. 

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- Azure SQL Database instance with write access. You can create Azure SQL Database instance by following the detail in the article [Create a SQL Database instance](https://docs.microsoft.com/en-us/azure/azure-sql/database/single-database-create-quickstart?tabs=azure-portal)
- Already installed Integration Runtime or its downloaded .MSI. You can download it from [here](https://www.microsoft.com/en-in/download/details.aspx?id=39717).
- A completed assessment on the source SQL server to see if the migration to Azure SQL Database is possible or not. 
- Create Azure SQL Database and perform schema migration from source database to it. Please follow the instructions [here](https://www.mssqltips.com/sqlservertip/5455/using-the-data-migration-assistant-dma-tool-to-migrate-from-sql-server-to-azure-sql-database) to perform schema migration using DMA.
- Azure CLI installed. You can do it using `pip install azure-cli` or follow the instructions [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
- `az datamigtation`  CLI extension installed. You can do it using `az extension add --name datamigration`.

## Azure login 

Before we get started with managing Azure resources with Azure CLI we need to login into Azure and set our default subscription.

In the following example we login using the `az login` command and select a particular subscription with `az account set` command.

```
az login

az account set --subscription <Subscription-id>
```

## Create a Resource Group

An Azure resource group is a logical container in which Azure resources are deployed and managed.

Create a resource group by using the [az group create](https://docs.microsoft.com/en-us/cli/azure/manage-azure-groups-azure-cli?view=azure-cli-latest) command.

The following example creates a resource group named myResourceGroup in the East US 2 region.

```
az group create --name MyResourceGroup  --location EastUS2 
```


## Create an instance of Database Migration Service

You can create new instance of Azure Database Migration Service by using the `az datamigration sql-service create` cmdlet. This cmdlet expects the following required parameters:

- _Azure Resource Group name_: You can use [az group create](https://docs.microsoft.com/en-us/cli/azure/manage-azure-groups-azure-cli?view=azure-cli-latest) command to create an Azure Resource group as previously shown and provide its name as a parameter.
- _SQL Migration Service name_: String that corresponds to the desired unique service name for Azure SQL Migration Service.
- _Location_: Specifies the location of the service. Specify an Azure data center location, such as West US or Southeast Asia.

The following example creates a service named MySqlMigrationService in the resource group MyResourceGroup located in the East US 2 region.

```
az datamigration sql-service create --resource-group "MyResourceGroup" --sql-migration-service-name "MySqlMigrationService" --location "EastUS2"
```

## Register Database Migration Service with self-hosted Integration Runtime

After creating the Database Migration Service, we need to register it on the Self-Hosted Integration Runtime. We register the service on IR using its AuthKeys which we can obtain using `az datamigration sql-service list-auth-key` command. This command expects the following parameters:

- _Azure Resource Group name_: The resource group in which SQL Migration Service is present.
- _SQL Migration Service name_: The name of the SQL Migration Service whose authkeys you want to obtain.

The following example gets the authkeys of the service we previously created. We will be capturing the results of this command as we will be using it later on.

```
$authKey1 = az datamigration sql-service list-auth-key --resource-group "MyResourceGroup" --sql-migration-service-name "MySqlMigrationService" --query "authKey1"
```

We will be using these authkeys to register the service on Integration Runtime. `az datamigration register-integration-runtime` expects the following parameters:

- _AuthKey_: Authkey of the Database Migration Service you want to register on IR.
- _Integration Runtime Path_: If the IR is not installed, you can pass its .MSI path as parameter to this command.

In the following example, we pass the previously obtained authkeys and the path of Integration Runtime .MSI to install Integration Runtime and register the service on it.

```
az datamigration register-integration-runtime  --auth-key $authKey1 --ir-path "C:\Users\user\Downloads\IntegrationRuntime.msi"
```

If you already have Integration Runtime installed you can just pass the AuthKey to the above command.

```
az datamigration register-integration-runtime --auth-key $authKey1
```

## Start Database Migration

Use the `az datamigration sql-db create` cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- *--sqldb-instance-name*: Target SQL Database logical server to which source database is being migrated to.
- *--resource-group*: Resource group in which Azure SQL Database is present.   
- *--target-db-name*: The name of the migrated database in Azure SQL Database.
- *--scope*: Resource Id of the Azure SQL Database logical server.
- *--migration-service*: Resource Id of the Database Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Azure SQL Database.
- *--source-database-name*: Name of the source database that is being migrated to Azure SQL Database.
- *--source-sql-connection*: Source SQL connection, which has below parameters.
  - *authentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
  - *data-source*: The name or IP of a SQL Server instance.
  - *user-name*: Username of the SQL Server instance.
  - *password*: Password of the SQL Server instance.
- *--target-sql-connection*: Target SQL connection (Azure SQL Database), which has below parameters.
  - *authentication*: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
  - *data-source*: The name or IP of Azure SQL Database logical server.
  - *user-name*: Username to connect to Azure SQL Database.
  - *password*: Password to connect to Azure SQL Database.
- *--table-list*: In case if only selected tables are required to be migrated use this parameter to provide space separated table names. 


The following example creates and starts a migration of complete source database with target database name AdventureWorksTarget:

```
az datamigration sql-db create `
--migration-service "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MyService" `
--scope "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.Sql/servers/labserver" `
--source-database-name "AdventureWorks" `
--source-sql-connection authentication="SQLAuthentication" data-source="LABSERVER.MICROSOFT.COM" password="password" user-name="user" `
--target-sql-connection authentication="SQLAuthentication" data-source="labserver.database.windows.net" password="password" user-name="user" `
--resource-group "MyGroup" --sqldb-instance-name "labserver" --target-db-name AdventureWorksTarget
```


The following example creates and starts a migration of selected tables from source database with target database name AdventureWorksTarget:

```
az datamigration sql-db create `
--migration-service "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MyService" `
--scope "/subscriptions/MySubscriptionID/resourceGroups/MyGroup/providers/Microsoft.Sql/servers/labserver" `
--source-database-name "AdventureWorks" `
--source-sql-connection authentication="SQLAuthentication" data-source="LABSERVER.MICROSOFT.COM" password="password" user-name="user" `
--target-sql-connection authentication="SQLAuthentication" data-source="labserver.database.windows.net" password="password" user-name="user" `
--table-list "[dbo].[Table_1]" "[dbo].[Table_2]" `
--resource-group "MyGroup" --sqldb-instance-name "labserver" --target-db-name AdventureWorksTarget
```

## Monitoring Migration

To monitor the migration, check the status of task.

```
# Basic migration details
az datamigration sql-db show --resource-group MyGroup --sqldb-instance-name labserver --target-db-name AdventureWorksTarget

# Gets complete migration detail
az datamigration sql-db show --resource-group MyGroup --sqldb-instance-name labserver --target-db-name AdventureWorksTarget --expand MigrationStatusDetails

# ProvisioningState should be Creating, Failed or Succeeded
az datamigration sql-db show --resource-group MyGroup --sqldb-instance-name labserver --target-db-name AdventureWorksTarget --expand MigrationStatusDetails --query "properties.provisioningState"

# MigrationStatus should be InProgress, Canceling, Failed or Succeeded
az datamigration sql-db show --resource-group MyGroup --sqldb-instance-name labserver --target-db-name AdventureWorksTarget --expand MigrationStatusDetails --query "properties.migrationStatus"
```

The migration is by default offline, so no cutover is required. The migration is completed when migration status changes to succeeded.


## Delete SQL Migration Service Instance

After the migration is complete, you can delete the Azure Database Migration Service instance:

```
az datamigration sql-service delete --sql-migration-service-name "MySqlMigrationService" --resource-group "MyResourceGroup"
```

## Addition Resources on Cmdlets
- You can find the documentation of each of the cmdlets here: [DataMigration Cmdlets Doc](https://docs.microsoft.com/en-us/cli/azure/datamigration?view=azure-cli-latest).