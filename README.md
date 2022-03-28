# Migrate databases at scale using Azure Database Migration Service automation

The [Azure SQL Migration extension for Azure Data Studio](/sql/azure-data-studio/extensions/azure-sql-migration-extension) enables you to assess, get Azure recommendations and migrate your SQL Server databases to Azure. Using automation with [Azure PowerShell](/powershell/module/az.datamigration) or [Azure CLI](/cli/azure/datamigration), you can leverage the capabilities of the extension with Azure Database Migration Service to migrate one or more databases at scale (including databases across multiple SQL Server instances).

The following sample scripts can be referenced to suit your migration scenario using Azure PowerShell or Azure CLI:
|Scripting language  |Migration scenario  |Azure Samples link  |
|---------|---------|---------|
|PowerShell     |SQL Server assessment         |[https://github.com](https://github.com)         |
|PowerShell     |SQL Server to Azure SQL Managed Instance (using file share)         |[https://github.com](https://github.com)         |
|PowerShell     |SQL Server to Azure SQL Managed Instance (using Azure storage)         |[https://github.com](https://github.com)           |
|PowerShell     |SQL Server to SQL Server on Azure Virtual Machines (using file share)          |[https://github.com](https://github.com)         |
|PowerShell     |SQL Server to SQL Server on Azure Virtual Machines (using Azure Storage)         |[https://github.com](https://github.com)         |
|PowerShell     |Sample: End-to-End migration automation         |[https://github.com](https://github.com)         |
|PowerShell     |Sample: End-to-End migration automation for multiple databases         |[https://github.com](https://github.com)         |
|CLI     |SQL Server assessment         |[https://github.com](https://github.com)         |
|CLI     |SQL Server to Azure SQL Managed Instance (using file share)         |[https://github.com](https://github.com)         |
|CLI     |SQL Server to Azure SQL Managed Instance (using Azure storage)         |[https://github.com](https://github.com)         |
|CLI     |SQL Server to SQL Server on Azure Virtual Machines (using file share)         |[https://github.com](https://github.com)         |
|CLI     |SQL Server to SQL Server on Azure Virtual Machines (using Azure Storage)         |[https://github.com](https://github.com)         |
|CLI     |Sample: End-to-End migration automation         |[https://github.com](https://github.com)         |
|CLI     |Sample: End-to-End migration automation for multiple databases         |[https://github.com](https://github.com)         |

## Getting Started

## Prerequisites

Pre-requisites that are common across all supported migration scenarios using Azure PowerShell or Azure CLI are:

* Have an Azure account that is assigned to one of the built-in roles listed below:
    - Contributor for the target Azure SQL Managed Instance (and Storage Account to upload your database backup files from SMB network share).
    - Reader role for the Azure Resource Groups containing the target Azure SQL Managed Instance or the Azure storage account.
    - Owner or Contributor role for the Azure subscription.
    > [!IMPORTANT]
    > Azure account is only required when running the migration steps and is not required for assessment or Azure recommendation steps process.
* Create a target [Azure SQL Managed Instance](../azure-sql/managed-instance/create-configure-managed-instance-powershell-quickstart.md) or [SQL Server on Azure Virtual Machine](../azure-sql/virtual-machines/windows/sql-vm-create-powershell-quickstart.md)

    > [!IMPORTANT]
    > If you have an existing Azure Virtual Machine, it should be registered with [SQL IaaS Agent extension in Full management mode](../azure-sql/virtual-machines/windows/sql-server-iaas-agent-extension-automate-management.md#management-modes).
* Ensure that the logins used to connect the source SQL Server are members of the *sysadmin* server role or have `CONTROL SERVER` permission. 
* Use one of the following storage options for the full database and transaction log backup files: 
    - SMB network share 
    - Azure storage account file share or blob container 

    > [!IMPORTANT]
    > - If your database backup files are provided in an SMB network share, [Create an Azure storage account](../storage/common/storage-account-create.md) that allows the DMS service to upload the database backup files.  Make sure to create the Azure Storage Account in the same region as the Azure Database Migration Service instance is created.
    > - Azure Database Migration Service does not initiate any backups, and instead uses existing backups, which you may already have as part of your disaster recovery plan, for the migration.
    > - You should take [backups using the `WITH CHECKSUM` option](/sql/relational-databases/backup-restore/enable-or-disable-backup-checksums-during-backup-or-restore-sql-server). 
    > - Each backup can be written to either a separate backup file or multiple backup files. However, appending multiple backups (i.e. full and t-log) into a single backup media is not supported. 
    > - Use compressed backups to reduce the likelihood of experiencing potential issues associated with migrating large backups.
* Ensure that the service account running the source SQL Server instance has read and write permissions on the SMB network share that contains database backup files.
* The source SQL Server instance certificate from a database protected by Transparent Data Encryption (TDE) needs to be migrated to the target Azure SQL Managed Instance or SQL Server on Azure Virtual Machine before migrating data. To learn more, see [Migrate a certificate of a TDE-protected database to Azure SQL Managed Instance](../azure-sql/managed-instance/tde-certificate-migrate.md) and [Move a TDE Protected Database to Another SQL Server](/sql/relational-databases/security/encryption/move-a-tde-protected-database-to-another-sql-server).
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

## Resources

- For Azure PowerShell reference documentation for SQL Server database migrations, see Az.DataMigration](/powershell/module/az.datamigration).
- For Azure CLI reference documentation for SQL Server database migrations, see Az.DataMigration](/cli/azure/datamigration).
- For Azure Samples code repository, see [data-migration-sql](https://github.com/Azure-Samples/data-migration-sql)