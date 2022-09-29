# Migrate databases at scale using Azure Database Migration automation (Preview)

The [Azure SQL Migration extension for Azure Data Studio](https://docs.microsoft.com/sql/azure-data-studio/extensions/azure-sql-migration-extension) brings together a simplified assessment, recommendation, and migration experience that delivers the following capabilities:
- An enhanced assessment mechanism that can evaluate SQL Server instances, identifying databases that are ready for migration to the different Azure SQL targets.
- A SKU recommendation engine that collects performance data from the source SQL Server instance on-premises, generating right-sized SKU recommendations based on your Azure SQL target.
- A reliable Azure service powered by Azure Database Migration Service that orchestrates data movement activities to deliver a seamless migration experience.
- The ability to run online (for migrations requiring minimal downtime) or offline (for migrations where downtime persists through the migration) migration modes to suit your business requirements.
- The flexibility to create and configure a self-hosted integration runtime to provide your own compute for accessing the source SQL Server and backups in your on-premises environment.

With automation tools like [Powershell - Azure DataMigration Service Module](https://docs.microsoft.com/powershell/module/az.datamigration) or [Azure CLI](https://docs.microsoft.com/cli/azure/datamigration), you can leverage the capabilities of the Azure SQL Migration extension together with Azure Database Migration Service to migrate one or more databases at scale (including databases across multiple SQL Server instances).

The following sample scripts can be referenced to suit your migration scenario using Azure PowerShell or Azure CLI:

| Migration scenario | Scripting language
|---------|---------|
SQL Server assessment| [PowerShell](/PowerShell/sql-server-assessment.md) / [Azure CLI](/CI/sql-server-assessment.md)
SQL Server to Azure SQL Managed Instance (using file share)|[PowerShell](/PowerShell/sql-server-to-sql-mi-fileshare.md) / [Azure CLI](/CLI/sql-server-to-sql-mi-fileshare.md)
SQL Server to Azure SQL Managed Instance (using Azure storage)|[PowerShell](/PowerShell/sql-server-to-sql-mi-blob.md) / [Azure CLI](/CLI/sql-server-to-sql-mi-blob.md)
SQL Server to SQL Server on Azure Virtual Machines (using file share)|[PowerShell](/PowerShell/sql-server-to-sql-vm-fileshare.md) / [Azure CLI](/CLI/sql-server-to-sql-vm-fileshare.md)
SQL Server to SQL Server on Azure Virtual Machines (using Azure Storage)|[PowerShell](/PowerShell/sql-server-to-sql-vm-blob.md) / [Azure CLI](/CLI/sql-server-to-sql-vm-blob.md)
SQL Server to Azure SQL Database (Preview)|[PowerShell](/PowerShell/sql-server-to-sql-db.md) / [Azure CLI](/CLI/sql-server-to-sql-db.md)
SKU recommendations (Preview)|[PowerShell](/PowerShell/sql-server-sku-recommendation.md) / [Azure CLI](/CLI/sql-server-sku-recommendation.md)
End-to-End migration automation|[PowerShell](/PowerShell/scripts/) / [Azure CLI](/CLI/scripts/)
End-to-End migration automation for multiple databases|[PowerShell](/PowerShell/scripts/multiple%20databases/) / [Azure CLI](/CLI/scripts/multiple%20databases/)

## Getting Started

## Prerequisites

Pre-requisites that are common across all supported migration scenarios using Azure PowerShell or Azure CLI are:

* Have an Azure account that is assigned to one of the built-in roles listed below:
    - Contributor for the target Azure SQL Managed Instance, SQL Server on Azure Virtual Machines or Azure SQL Database (Preview) and, Storage Account to upload your database backup files from SMB network share (*Not applicable for Azure SQL Database*).
    - Reader role for the Azure Resource Groups containing the target Azure SQL Managed Instance, SQL Server on Azure Virtual Machines or Azure SQL Database (Preview).
    - Owner or Contributor role for the Azure subscription.
    > [!IMPORTANT]
    > Azure account is only required when running the migration steps and is not required for assessment or Azure recommendation steps process.
* Create a target [Azure SQL Managed Instance](/azure/azure-sql/managed-instance/create-configure-managed-instance-powershell-quickstart), [SQL Server on Azure Virtual Machine](/azure/azure-sql/virtual-machines/windows/sql-vm-create-powershell-quickstart) or [Azure SQL Database (Preview)](/azure/azure-sql/database/single-database-create-quickstart)
    > [!IMPORTANT] If your target is Azure SQL Database (Preview) you have to migrate database schema from source to target using [SQL Server dacpac extension](/sql/azure-data-studio/extensions/sql-server-dacpac-extension) or, [SQL Database Projects extension](/sql/azure-data-studio/extensions/sql-database-project-extension) for Azure Data Studio.
    > 
    > If you have an existing Azure Virtual Machine, it should be registered with [SQL IaaS Agent extension in Full management mode](/azure/azure-sql/virtual-machines/windows/sql-server-iaas-agent-extension-automate-management#management-modes).
* If your target is **Azure SQL Managed Instance** or **SQL Server on Azure Virtual Machine** ensure that the logins used to connect the source SQL Server are members of the *sysadmin* server role or have `CONTROL SERVER` permission.
* If your target is **Azure SQL Database (Preview)** ensure that the login used to connect the source SQL Server is member of the `db_datareader` and login for target SQL server is `db_owner`.
* Use one of the following storage options for the full database and transaction log backup files: 
    - SMB network share 
    - Azure storage account file share or blob container 

    > [!IMPORTANT]
    > - If your database backup files are provided in an SMB network share, [Create an Azure storage account](../storage/common/storage-account-create.md) that allows the DMS service to upload the database backup files.  Make sure to create the Azure Storage Account in the same region as the Azure Database Migration Service instance is created.
    > - Make sure the Azure storage account blob container is used exclusively to store backup files only. Any other type of files (txt, png, jpg, etc.) will interfere with the restore process leading to a failure.
    > - Azure Database Migration Service does not initiate any backups, and instead uses existing backups, which you may already have as part of your disaster recovery plan, for the migration.
    > - You should take [backups using the `WITH CHECKSUM` option](/sql/relational-databases/backup-restore/enable-or-disable-backup-checksums-during-backup-or-restore-sql-server). 
    > - Each backup can be written to either a separate backup file or multiple backup files. However, appending multiple backups (i.e. full and t-log) into a single backup media is not supported. 
    > - Use compressed backups to reduce the likelihood of experiencing potential issues associated with migrating large backups.
* Ensure that the service account running the source SQL Server instance has read and write permissions on the SMB network share that contains database backup files.
* The source SQL Server instance certificate from a database protected by Transparent Data Encryption (TDE) needs to be migrated to the target Azure SQL Managed Instance or SQL Server on Azure Virtual Machine before migrating data. To learn more, see [Migrate a certificate of a TDE-protected database to Azure SQL Managed Instance](/azure/azure-sql/managed-instance/tde-certificate-migrate) and [Move a TDE Protected Database to Another SQL Server](/sql/relational-databases/security/encryption/move-a-tde-protected-database-to-another-sql-server).
    > [!TIP]
    > If your database contains sensitive data that is protected by [Always Encrypted](/sql/relational-databases/security/encryption/configure-always-encrypted-using-sql-server-management-studio), migration process using Azure Data Studio with DMS will automatically migrate your Always Encrypted keys to your target Azure SQL Managed Instance or SQL Server on Azure Virtual Machine.

* If your database backups are in a network file share, provide a machine to install [self-hosted integration runtime](../data-factory/create-self-hosted-integration-runtime.md) to access and migrate database backups. The Azure PowerShell or Azure CLI modules provide the authentication keys to register your self-hosted integration runtime. In preparation for the migration, ensure that the machine where you plan to install the self-hosted integration runtime has the following outbound firewall rules and domain names enabled:

    | Domain names                                          | Outbound ports | Description                |
    | ----------------------------------------------------- | -------------- | ---------------------------|
    | Public Cloud: `{datafactory}.{region}.datafactory.azure.net`<br> or `*.frontend.clouddatahub.net` <br> Azure Government: `{datafactory}.{region}.datafactory.azure.us` <br> China: `{datafactory}.{region}.datafactory.azure.cn` | 443            | Required by the self-hosted integration runtime to connect to the Data Migration service. <br>For new created Data Factory in public cloud, locate the FQDN from your Self-hosted Integration Runtime key, which is in format `{datafactory}.{region}.datafactory.azure.net`. For old Data factory, if you don't see the FQDN in your Self-hosted Integration key, use *.frontend.clouddatahub.net instead. |
    | `download.microsoft.com`    | 443            | Required by the self-hosted integration runtime for downloading the updates. If you have disabled auto-update, you can skip configuring this domain. |
    | `*.core.windows.net`          | 443            | Used by the self-hosted integration runtime that connects to the Azure storage account for uploading database backups from your network share |

    > [!TIP]
    > If your database backup files are already provided in an Azure storage account, self-hosted integration runtime is not required during the migration process.

* When using self-hosted integration runtime, make sure that the machine where the runtime is installed can connect to the source SQL Server instance and the network file share where backup files are located. Outbound port 445 should be enabled to allow access to the network file share.
* If you're using the Azure Database Migration Service for the first time, ensure that Microsoft.DataMigration resource provider is registered in your subscription. You can follow the steps to [register the resource provider](./quickstart-create-data-migration-service-portal.md#register-the-resource-provider)

    > [!IMPORTANT]
    > If your target is Azure SQL Database (Preview), you don't neet backups to perform this migration. The migration to Azure SQL Database is considered a logical migration which involves the pre-creation of the database and the data movement (peformed by DMS).

## Resources

- For PowerShell reference documentation for SQL Server database migrations, see [Az.DataMigration](https://docs.microsoft.com/powershell/module/az.datamigration).
- For Azure CLI reference documentation for SQL Server database migrations, see [az datamigration](https://docs.microsoft.com/cli/azure/datamigration).
