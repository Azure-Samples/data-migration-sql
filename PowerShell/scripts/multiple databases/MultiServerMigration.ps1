# import
. (Join-Path $PSScriptRoot Prerequisites.ps1)
. (Join-Path $PSScriptRoot Cutover.ps1)
. (Join-Path $PSScriptRoot helpers.ps1)

# The below section takes care of DMS creation and registration
DmsSetup

# migration-server-config.json contains an array of server related information (like authentication, data source, username, poassword and databases within a server to migrate)
$serversAndDatabasesObject = Get-Content -Path "$PSScriptRoot\migration-server-config.json" | ConvertFrom-Json;
$serversAndDatabases = $serversAndDatabasesObject.Servers


# The below for loop iterates for each server and then starts migrations of the databases from the given server.
foreach ($k in $serversAndDatabases)
{ 
    # the below section stores the server related information (like authentication, data source, username, poassword and databases to migrate) of a particular server in $serverInfo 
    $serverInfo = @{};
    $k.psobject.properties | Foreach{ $serverInfo[$_.Name] = $_.Value };

    # migration-db-config.json contains all the parameters needed for a new migration (except server , kind, blob/fileshare and database related information which will be populated later).
    $NewDatabaseMigrationInfo = Get-Content -Path "$PSScriptRoot\migration-db-config.json" | ConvertFrom-Json;

    # Checking for valid value of Kind
    if($serverInfo["Kind"] -ne "SqlMi" -And $serverInfo["Kind"] -ne "SqlVm")
    {
        throw "Invalid value provided for the parameter 'Kind' in migration-server-config.json . The valid values are : SqlMi , SqlVm "

    }
    else{
        #This portion makes sure that we provide only one of (SQL MI or SQL VM ) related parameters
        if($serverInfo["Kind"] -eq "SqlMi")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlVirtualMachineName')
        }
        if($serverInfo["Kind"] -eq "SqlVm")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('ManagedInstanceName')
        }

    }
    # Checking for valid value of BlobFileshare
    if($serverInfo["BlobFileshare"] -ne "blob" -And $serverInfo["BlobFileshare"] -ne "fileshare")
    {
        throw "Invalid value provided for the parameter 'BlobFileshare' in migration-server-config.json . The valid values are : blob , fileshare "
    }
    else{
        #This portion makes sure that we provide only one of  (fileshare or blob) parameters
        if($serverInfo["BlobFileshare"] -eq "fileshare")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobStorageAccountResourceId')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobContainerName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobAccountKey')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('OfflineConfigurationLastBackupName')
        }
        if($serverInfo["BlobFileshare"] -eq "blob")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePath')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileShareUsername')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePassword')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountResourceId')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountKey')
        }

    }

    # Store migration parameters in a dictionary $NewDatabaseMigrationParameters which can be directly passed to New-AzDataMigrationToSqlManagedInstance / New-AzDataMigrationToSqlVM commandlets.
    $NewDatabaseMigrationParameters = @{};
    $NewDatabaseMigrationInfo.psobject.properties | Foreach{ $NewDatabaseMigrationParameters[$_.Name] = $_.Value };

    # Adding the server 
    $NewDatabaseMigrationParameters.SourceSqlConnectionAuthentication = $serverInfo["SourceSqlConnectionAuthentication"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionDataSource =$serverInfo["SourceSqlConnectionDataSource"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionUserName =$serverInfo["SourceSqlConnectionUserName"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionPassword = $serverInfo["SourceSqlConnectionPassword"]

    # Adding the Kind, resource group and scope
    $NewDatabaseMigrationParameters.Kind = $serverInfo["Kind"]
    $NewDatabaseMigrationParameters.ResourceGroupName = $serverInfo["ResourceGroupName"]
    $NewDatabaseMigrationParameters.Scope = $serverInfo["Scope"]
    $NewDatabaseMigrationParameters.Offline = $serverInfo["Offline"]

    # Adding the databases to be migrated
    if($serverInfo["DatabasesFromSourceSql"] -eq $true)
    {
        $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
    }
    else{
        $DatabasesToMigrate = $serverInfo["databases"]
    }

    # Performing single server, multi db migrations 
    $Kind = $NewDatabaseMigrationParameters["Kind"]
    if($Kind -eq "SqlMi")
    {   
        foreach ($DB in $DatabasesToMigrate)
        {   
            $NewDatabaseMigrationParameters.SourceDatabaseName = $DB
            $NewDatabaseMigrationParameters.TargetDbName = $DB
            $NewDatabaseMigrationParameters.FileSharePath = $NewDatabaseMigrationParameters.FileSharePath + '\' + $DB + '\'
            
            try{
                Write-Host "Starting Migration for Database $DB"
                $instance = New-AzDataMigrationToSqlManagedInstance @NewDatabaseMigrationParameters -ErrorAction Continue
                if($instance.ProvisioningState -eq "Succeeded")
                {   
                    $ServerDataSource = $serverInfo["SourceSqlConnectionDataSource"] 
                    Add-Content $PSScriptRoot\dbsStarted.txt "`n $ServerDataSource  $DB" 
                }
            }
            catch{
                Write-Error "$_"
            }
        }       
    }
    else
    {  
        foreach ($DB in $DatabasesToMigrate)
        {
            $NewDatabaseMigrationParameters.SourceDatabaseName = $DB
            $NewDatabaseMigrationParameters.TargetDbName = $DB
            $NewDatabaseMigrationParameters.FileSharePath = $NewDatabaseMigrationParameters.FileSharePath + '\' + $DB + '\'
            
            Write-Host "Starting Migration for Database $DB"
            try{
                $instance = New-AzDataMigrationToSqlVM @NewDatabaseMigrationParameters -ErrorAction Continue
                if($instance.ProvisioningState -eq "Succeeded")
                {
                    $ServerDataSource = $serverInfo["SourceSqlConnectionDataSource"] 
                    Add-Content $PSScriptRoot\dbsStarted.txt "`n $ServerDataSource  $DB"
                    
                }
            }
            catch{ 
                Write-Error "$_" 
            }
        }                         
    }           
}

###############################################################################################
# This section is for recording migrations that failed. This does not record migrations that were stuck
$Inputs = Get-Content -Path "$PSScriptRoot\user-config.json" | ConvertFrom-Json;
$LogFailedDbs = $Inputs.LogFailedDbs

if($LogFailedDbs -eq $true)
{
# Hashtable storing failed db migrations for each server
$ErrorDbTable = @{}
# Checking for migrations with provisioning error / Migration error and writing them to logs.json:-
foreach ($k in $serversAndDatabases)
{   
    # the below section stores the server related information (like authentication, data source, username, poassword and databases to migrate) of a particular server in $serverInfo 
    $serverInfo = @{};
    $k.psobject.properties | Foreach{ $serverInfo[$_.Name] = $_.Value };

    # migration-db-config.json contains all the parameters needed for a new migration.
    $NewDatabaseMigrationInfo = Get-Content -Path "$PSScriptRoot\migration-db-config.json" | ConvertFrom-Json;

    # Store migration parameters in a dictionary $NewDatabaseMigrationParameters 
    
    $NewDatabaseMigrationParameters = @{};
    $NewDatabaseMigrationInfo.psobject.properties | Foreach{ $NewDatabaseMigrationParameters[$_.Name] = $_.Value };

    # Adding the server 
    $NewDatabaseMigrationParameters.SourceSqlConnectionAuthentication = $serverInfo["SourceSqlConnectionAuthentication"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionDataSource =$serverInfo["SourceSqlConnectionDataSource"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionUserName =$serverInfo["SourceSqlConnectionUserName"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionPassword = $serverInfo["SourceSqlConnectionPassword"]

    # Adding the Kind, resource group and scope
    $NewDatabaseMigrationParameters.Kind = $serverInfo["Kind"]
    $NewDatabaseMigrationParameters.ResourceGroupName = $serverInfo["ResourceGroupName"]
    $NewDatabaseMigrationParameters.Scope = $serverInfo["Scope"]
    $NewDatabaseMigrationParameters.Offline = $serverInfo["Offline"]

    # Adding the databases to be checked
    if($serverInfo["DatabasesFromSourceSql"] -eq $true)
    {
        $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
    }
    else{
        $DatabasesToMigrate = $serverInfo["databases"]
    }
    # Array list to store failed migrations for a given server
    [System.Collections.ArrayList]$ErrorDbs= @()
    # check for failures
    if($serverInfo["Kind"] -eq "SqlMi")
    {   
        foreach ($DB in $DatabasesToMigrate)
        {   
            
            try{
                $tdb = $DB
                $instance = Get-AzDataMigrationToSqlManagedInstance -ManagedInstanceName $NewDatabaseMigrationParameters.ManagedInstanceName -ResourceGroupName $serverInfo["ResourceGroupName"]  -Expand MigrationStatusDetails -TargetDbName $tdb -ErrorAction Continue 
                if($instance.ProvisioningState -eq "Failed" -Or $instance.MigrationStatus -eq "Failed" -Or $instance.MigrationStatus -eq "Canceled" )
                {
                    $ErrorDbs.Add($DB) > $null                               
                }
            }
            catch{
                Write-Error "$_"
            }
        }   
    }
    else
    {  
        foreach ($DB in $DatabasesToMigrate)
        {
        
            Write-Host "Checking status for Database $DB"
            try{
                $instance = Get-AzDataMigrationToSqlVM -SqlVirtualMachineName $NewDatabaseMigrationParameters.SqlVirtualMachineName -ResourceGroupName $serverInfo["ResourceGroupName"]  -Expand MigrationStatusDetails -TargetDbName $DB -ErrorAction Continue
                if($instance.ProvisioningState -eq "Failed" -Or $instance.MigrationStatus -eq "Failed" -Or $instance.MigrationStatus -eq "Canceled")
                {
                    $ErrorDbs.Add($DB) > $null
                }
            }
            catch{ 
                Write-Error "$_" 
            }
        }                         
    }
    $ServerDataSource = $serverInfo["SourceSqlConnectionDataSource"]
    $ErrorDbTable[$ServerDataSource] = $ErrorDbs
    $ErrorDbTable | ConvertTo-Json  | Out-File "$PSScriptRoot\logs.json"
}
}
#############################################CUTOVER###########################################

# Uncomment if u want cutover script to execute
#StartCutover






