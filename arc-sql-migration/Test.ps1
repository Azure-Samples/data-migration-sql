# This script demonstrates how to use the helper functions in Invoke-ArcSqlMigration.ps1 to migrate databases using LRS method from SQL Server enabled by Azure Arc to Azure SQL Managed Instance.

# ============================================================================
# PARAMETERS — Replace the placeholder values below with your environment details
# ============================================================================

$TenantId              = "<YOUR_TENANT_ID>"                    # Azure AD tenant ID (e.g. "00000000-0000-0000-0000-000000000000")
$SubscriptionId        = "<YOUR_SUBSCRIPTION_ID>"              # Azure subscription ID
$ArcSqlResourceId      = "<YOUR_ARC_SQL_RESOURCE_ID>"          # Full ARM resource ID of the Arc SQL Server instance
                                                                # e.g. "/subscriptions/.../resourceGroups/.../providers/Microsoft.AzureArcData/SqlServerInstances/..."
$ManagedInstanceName   = "<YOUR_MI_NAME>"                      # Name of the target Azure SQL Managed Instance
$StorageAccountName    = "<YOUR_STORAGE_ACCOUNT_NAME>"         # Storage account holding database backups
$DmsResourceGroupName  = "<YOUR_RESOURCE_GROUP>"               # Resource group for the DMS resource
$DmsResourceName       = "<YOUR_DMS_RESOURCE_NAME>"            # Name for the Database Migration Service resource
$Location              = "<YOUR_AZURE_REGION>"                 # Azure region (e.g. "eastus", "centralindia")
$DatabasesToMigrate    = @("<YOUR_DATABASE_1>", "<YOUR_DATABASE_2>")  # List of database names to migrate

# ============================================================================

function Wait-ForKeyPress {
    param(
        [Parameter(Position = 0)][string]$NextStep
    )
    Write-Host "`n==> $NextStep"
    Write-Host "`nPress any key to continue, or ESC to exit..." -ForegroundColor Yellow
    
    # Read a single key without displaying it
    $key = [System.Console]::ReadKey($true)

    if ($key.Key -eq 'Escape') {
        Write-Host "Escape pressed. Exiting script..." -ForegroundColor Red
        exit
    }
}

Write-Host ("=" * 75) 
Write-Host "We will now demonstrate how the accompanying helper script can"  -ForegroundColor Yellow
Write-Host "be used to review assessments and perform migration of databases"  -ForegroundColor Yellow
Write-Host "from SQL Server enabled by Azure Arc to Azure SQL Managed Instance" -ForegroundColor Yellow
Write-Host "using backups via the LRS method." -ForegroundColor Yellow
Write-Host ("=" * 75) 
Wait-ForKeyPress "Load the script (dot-source to import all functions)"

# Dot-source the script to import all functions into the current session
. .\Invoke-ArcSqlMigration.ps1

Wait-ForKeyPress "Step 1. Authenticate"
Connect-ArcMigration -TenantId $TenantId -SubscriptionId $SubscriptionId

Wait-ForKeyPress "Step 2 :  Get source instance details"
$instance = Get-ArcSqlServerInstance -ResourceId $ArcSqlResourceId

Wait-ForKeyPress "Steps 3 :  Discover source database details"
$databases = Get-ArcSqlDatabases -ResourceId $instance.id

Wait-ForKeyPress "Step 4. Fetch Assessment report"
$report = Get-MigrationAssessmentReport -ResourceId $instance.id


Wait-ForKeyPress "Step 5. List target managed instances"
$miList = Get-ManagedInstances -SubscriptionId $SubscriptionId
$mi = $miList | Where-Object { $_.Name -eq $ManagedInstanceName }
Write-Host "Selected Azure SQL Managed Instance : $mi"

Wait-ForKeyPress "Step 6. Set up storage"
$storageAccounts = Get-StorageAccounts -SubscriptionId $SubscriptionId
$sa = $storageAccounts | Where-Object { $_.Name -eq $StorageAccountName }
$containers = Get-BlobContainers -StorageAccountResourceId $sa.ResourceId

Wait-ForKeyPress "Step 7. Check Azure SQL MI Managed Identity RBAC on storage account"
$missing = Test-ManagedIdentityRbac `
    -ManagedInstanceId $mi.ResourceId `
    -StorageAccountResourceIds @($sa.ResourceId)


Wait-ForKeyPress "Step 8. Create DMS resource"
$dms = New-DmsResource `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $DmsResourceGroupName `
    -DmsResourceName $DmsResourceName `
    -Location $Location

Wait-ForKeyPress "Step 9. Start migration of databases"
foreach ($dbToMigrate in $DatabasesToMigrate) {
    Start-LrsMigration `
        -ManagedInstanceId $mi.ResourceId `
        -ArcSqlServerResourceId $instance.id `
        -Databases @(@{
            SourceDatabaseName       = $dbToMigrate
            TargetDatabaseName       = $dbToMigrate
            StorageAccountResourceId = $sa.ResourceId
            BlobContainerName        = ($containers | Where-Object {$_.Name -ieq $dbToMigrate} | Select-Object -First 1).Name
            BlobFolderPath           = "/"
        }) `
        -DmsResourceId $dms.ResourceId `
        -Location $Location
}

Wait-ForKeyPress "Step 10. Monitor until all ready for cutover"
$status = Get-LrsMigrationStatus -DmsResourceId $dms.ResourceId -ShowDetails
while ($status | Where-Object { $_.MigrationStatus -notin @("ReadyForCutover","Succeeded") }) {
  Start-Sleep -Seconds 3
  $status = Get-LrsMigrationStatus -DmsResourceId $dms.ResourceId -ShowDetails
}


Wait-ForKeyPress "Step 11. Cutover when ReadyForCutover"
$ready = $status | Where-Object { $_.MigrationStatus -eq "ReadyForCutover" }
Invoke-LrsCutover -Migrations $ready