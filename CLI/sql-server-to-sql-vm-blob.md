## Perfoming Online Migration

In this article, we perform a online migration of the Adventureworks database from SQL Server on-premises to a SQL Server running on Azure Virtual Machine by using Microsoft Azure CLI. You can migrate databases from a SQL Server instance to a SQL Server running on Azure Virtual Machine by using the DataMigration module in Microsoft Azure CLI.

**In this article you learn how to**

- Create a resource group
- Create a Database Migration Service
- Start an online migration
- Perform cutover for the online migration

**Note 1**: The query parameter shown in this tutorial works with powershell only and not with cmd. If you are using cmd, manually copy and paste the parameters mentioned.

**Note 2:** You can add `--debug` parameter to debug command execution. 

## Prerequisites

- SQL Server with AdventureWorks database.
- An Azure subscription. If you don't have one, [create a free account](https://azure.microsoft.com/free/) before you begin.
- Azure SQL Virtual Machine with write access. You can create Azure SQL Virtual Machine by following the detail in the article [Create a SQL Virtual Machine](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-vm-create-portal-quickstart)
- Azure blob storage with back up files.
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

- *Azure Resource Group name*: You can use [az group create](https://docs.microsoft.com/en-us/cli/azure/manage-azure-groups-azure-cli?view=azure-cli-latest) command to create an Azure Resource group as previously shown and provide its name as a parameter.
- *SQL Migration Service name*: String that corresponds to the desired unique service name for Azure Database Migration Service.
- *Location*: Specifies the location of the service. Specify an Azure data center location, such as West US or Southeast Asia.

The following example creates a service named MySqlMigrationService in the resource group MyResourceGroup located in the East US 2 region.

```
az datamigration sql-service create --resource-group "MyResourceGroup" --sql-migration-service-name "MySqlMigrationService" --location "EastUS2"
```

## Start Online Database Migration

Use the `az datamigration sql-vm create` cmdlet to create and start a database migration. This cmdlet expects the following parameters:

- _\--sql-vm-name_: Target SQL Virtual Machine to which source database is being migrated to.
- _\--resource-group_: Resource group in which Azure SQL Virtual Machine is present.
- _\--target-db-name_: The name with which the database will be stored in Azure SQL Virtual Machine.
- _\--scope_: Resource Id of the Azure SQL Virtual Machine.
- _\--migration-service_: Resource Id of the Database Migration Service that will be used to orchestrate the migration. The migration service should be in the same region as Azure SQL Virtual Machine.
- _\--source-database-name_: Name of the source database that is being migrated to Azure SQL Virtual Machine.
- _\--source-sql-connection_: Source SQL connection, which has below parameters.
    - _authentication_: The authentication type for connection, which can be either SqlAuthentication or WindowsAuthentication.
    - _data-source_: The name or IP of a SQL Server instance.
    - _user-name_: Username of the SQL Server instance.
    - _password_: Password of the SQL Server instance.
- _\--source-location_: Blob Container representing the blob share that contains the database backup files, which has below parameters.
    - _storageAccountResourceId_: Resource Id of the Azure blob storage account with backup files.
    - _accountKey_: The key of Azure Blob Account.
    - _blobContainerName_: Container in Azure Blob Account with backup files.
- _\--offline-configuration_: Config parameter used for performing offline migration.
    - _offline_: true when using offline mode.
    - _last-backup-name_: last backup file name

The following example creates and starts an online migration with target database name MyDb:

```
az datamigration sql-vm create `
--source-location '{\"AzureBlob\":{\"storageAccountResourceId\":\"/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount\",\"accountKey\":\"xxxxxxxxxxxxx\",\"blobContainerName\":\"AdventureWorksContainer\"}}' `
--migration-service "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
--scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
--source-database-name "AdventureWorks" `
--source-sql-connection authentication="SqlAuthentication" data-source="Labserver.database.net" password="placeholder" user-name="user" `
--target-db-name "MyDb" `
--resource-group MyResourceGroup `
--sql-vm-name MySqlVM
```

To start an offline migration, you should add `--offline-configuration` parameter.

```
az datamigration sql-vm create `
--source-location '{\"AzureBlob\":{\"storageAccountResourceId\":\"/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Storage/storageAccounts/MyStorageAccount\",\"accountKey\":\"xxxxxxxxxxxxx\",\"blobContainerName\":\"AdventureWorksContainer\"}}' `
--migration-service "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/MySqlMigrationService" `
--scope "/subscriptions/MySubscriptionID/resourceGroups/MyResourceGroup/providers/Microsoft.Sql/managedInstances/MyManagedInstance" `
--source-database-name "AdventureWorks" `
--source-sql-connection authentication="SqlAuthentication" data-source="Labserver.database.net" password="placeholder" user-name="user" `
--target-db-name "MyDb" `
--resource-group MyResourceGroup `
--sql-vm-name MySqlVM `
--offline-configuration last-backup-name="AdventureWorksTransactionLog2.trn" offline=true
```

## Monitoring Migration

To monitor the migration, check the status of task.

```
# Gets complete migration detail
az datamigration sql-vm show --sql-vm-name MySqlVM --resource-group MyResourceGroup --target-db-name MyDb --expand=MigrationStatusDetails

#ProvisioningState should be Creating, Failed or Succeeded
az datamigration sql-vm show --sql-vm-name MySqlVM --resource-group MyResourceGroup --target-db-name MyDb --expand=MigrationStatusDetails --query "properties.provisioningState"

#MigrationStatus should be InProgress, Canceling, Failed or Succeeded
az datamigration sql-vm show --sql-vm-name MySqlVM --resource-group MyResourceGroup --target-db-name MyDb --expand=MigrationStatusDetails --query "properties.migrationStatus"

```

The migration is ready for cutover when `CurrentRestoringFilename` is equal to `LastRestoredFilename`. These properties are returned as part of az datamigration sql-managed-instance show with --expand parameter provided.

## Performing cutover

With an online migration, a restore of provided backups of databases is performed, and then work proceeds on restoring the Transaction Logs stored in the Blob.

When the database in a Azure SQL Virtual Machine is updated with latest data and is in sync with the source database, you can perform a cutover.

We can perform cutover using the command `az datamigration sql-vm cutover`. This command accepts the following parameters:

- _\--sql-vm-name_: Target SQL Virtual Machine to which source database is being migrated to.
- _\--resource-group_: Resource group in which SQL Virtual Machine is present.
- _\--target-db-name_: The name with which the database will be stored in SQL Virtual Machine.
- _\--migration-operation-id:_ Tracking ID of migration. Can be obtained through `show` operation.

The following example, we perform cutover on the earlier started migration. We obtain the `MigrationOperationId` through the properties returned in the `az datamigration sql-vm show` command.

```
#Obtain the MigrationOperationId
$migOpId = az datamigration sql-vm show --sql-vm-name "MySqlVM" --resource-group "MyResourceGroup" --target-db-name "Mydb" --expand=MigrationStatusDetails --query "properties.migrationOperationId"

#Perform Cutover 
az datamigration sql-vm cutover --sql-vm-name "MySqlDb" --resource-group "MyResourceGroup" --target-db-name "Mydb" --migration-operation-id $migOpId
```

## Delete Database Migration Service Instance

After the migration is complete, you can delete the Azure Database Migration Service instance:

```
az datamigration sql-service delete --sql-migration-service-name "MySqlMigrationService" --resource-group "MyResourceGroup"
```

## Addition Resources on Cmdlets

- You can find the documentation of each of the cmdlets here : [DataMigration Cmdlets Doc](https://docs.microsoft.com/cli/azure/datamigration).
