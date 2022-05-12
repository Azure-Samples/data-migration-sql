# import
. (Join-Path $PSScriptRoot Prerequisites.ps1)
. (Join-Path $PSScriptRoot Cutover.ps1)
. (Join-Path $PSScriptRoot helpers.ps1)

# The below section takes care of DMS creation and registration
DmsSetup

# migration-server-config.json contains an array of server related information (like authentication, data source, username, poassword and databases within a server to migrate)
$serversAndDatabasesObject = Get-Content -Path "$PSScriptRoot\migration-server-config.json" | ConvertFrom-Json;
$serversAndDatabases = $serversAndDatabasesObject.Servers

# takes plain text and returns secure string
function toSecureString([string] $plain)
{
$secure = ConvertTo-SecureString $plain -AsPlainText -Force
return $secure
}

# The below for loop iterates for each server and then starts migrations of the databases from the given server.
foreach ($k in $serversAndDatabases)
{ 
    # the below section stores the server related information (like authentication, data source, username, poassword and databases to migrate) of a particular server in $serverInfo 
    $serverInfo = @{};
    $k.psobject.properties | Foreach{ $serverInfo[$_.Name] = $_.Value };

    # migration-db-config.json contains all the parameters needed for a new migration 
    $NewDatabaseMigrationInfo = Get-Content -Path "$PSScriptRoot\migration-db-config.json" | ConvertFrom-Json;

    # Checking for valid value of Kind
    if($serverInfo["Kind"] -ne "SqlMi" -And $serverInfo["Kind"] -ne "SqlVm" -And $serverInfo["Kind"] -ne "SqlDb" )
    {
        throw "Invalid value provided for the parameter 'Kind' in migration-server-config.json . The valid values are : SqlMi , SqlVm, SqlDb "
    }
    else{
        #This portion makes sure that we provide only one of (SQL MI or SQL VM or SQL DB ) related parameters
        if($serverInfo["Kind"] -eq "SqlMi")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlVirtualMachineName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlDbInstanceName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionAuthentication')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionDataSource')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionPassword')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionUserName')
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
                    #$NewDatabaseMigrationInfo.FileSharePassword = toSecureString $NewDatabaseMigrationInfo.FileSharePassword ;
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
            
        }
        elseif($serverInfo["Kind"] -eq "SqlVm")
        {
            $NewDatabaseMigrationInfo.PSObject.properties.remove('ManagedInstanceName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlDbInstanceName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionAuthentication')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionDataSource')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionPassword')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('TargetSqlConnectionUserName')
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
        }
        else{
            $NewDatabaseMigrationInfo.PSObject.properties.remove('ManagedInstanceName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlVirtualMachineName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePath')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileShareUsername')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePassword')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountResourceId')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountKey')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobStorageAccountResourceId')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobContainerName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobAccountKey')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('OfflineConfigurationLastBackupName')
            $NewDatabaseMigrationInfo.PSObject.properties.remove('Offline')
        }
    }
    
    # Store migration parameters in a dictionary $NewDatabaseMigrationParameters which can be directly passed to New-AzDataMigrationToSqlManagedInstance / New-AzDataMigrationToSqlVM commandlets.
    $NewDatabaseMigrationParameters = @{};
    $NewDatabaseMigrationInfo.psobject.properties | Foreach{ $NewDatabaseMigrationParameters[$_.Name] = $_.Value };

    # Adding the server connection details
    $NewDatabaseMigrationParameters.SourceSqlConnectionAuthentication = $serverInfo["SourceSqlConnectionAuthentication"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionDataSource =$serverInfo["SourceSqlConnectionDataSource"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionUserName =$serverInfo["SourceSqlConnectionUserName"]
    $NewDatabaseMigrationParameters.SourceSqlConnectionPassword = $serverInfo["SourceSqlConnectionPassword"]
    #Changing the source sql connection password to secure string
    $NewDatabaseMigrationParameters.SourceSqlConnectionPassword = toSecureString $NewDatabaseMigrationParameters.SourceSqlConnectionPassword ;
    # Adding the Kind, resource group, migration service and scope
    $NewDatabaseMigrationParameters.Kind = $serverInfo["Kind"]
    $NewDatabaseMigrationParameters.ResourceGroupName = $serverInfo["ResourceGroupName"]
    $NewDatabaseMigrationParameters.Scope = $serverInfo["Scope"]
    if($serverInfo["Kind"] -ne "SqlDb")
    {
        $NewDatabaseMigrationParameters.Offline = $serverInfo["Offline"]
    }    
    $NewDatabaseMigrationParameters.MigrationService = $serverInfo["MigrationService"]

    #Adding sql DB specific details and starting the migrations:
    if($NewDatabaseMigrationParameters.Kind -eq "SqlDb")
    {        
        $NewDatabaseMigrationParameters.TargetSqlConnectionAuthentication = $serverInfo["TargetSqlConnectionAuthentication"]
        $NewDatabaseMigrationParameters.TargetSqlConnectionDataSource = $serverInfo["TargetSqlConnectionDataSource"]
        $NewDatabaseMigrationParameters.TargetSqlConnectionPassword = $serverInfo["TargetSqlConnectionPassword"]
        $NewDatabaseMigrationParameters.TargetSqlConnectionUserName = $serverInfo["TargetSqlConnectionUserName"]
        $NewDatabaseMigrationParameters.SqlDbInstanceName = $serverInfo["SqlDbInstanceName"]
        #Changing the password to secure string
        $NewDatabaseMigrationParameters.TargetSqlConnectionPassword = toSecureString $NewDatabaseMigrationParameters.TargetSqlConnectionPassword ;
        # Adding the databases to be migrated
        if($serverInfo["DatabasesFromSourceSql"] -eq $true)
        {
            $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
        }
        else{
            $DatabasesToMigrate = $serverInfo["databases"]
        }
        
        #Starting migration for each db one by one
        foreach ($DB in $DatabasesToMigrate)
        {   
            $NewDatabaseMigrationParameters.SourceDatabaseName = $DB
            $NewDatabaseMigrationParameters.TargetDbName = $DB # in case of sql db ,user must create these target dbs in the target server before strating these migrations
            try{
                Write-Host "Starting Migration for Database $DB"
                $instance = New-AzDataMigrationToSqlDb @NewDatabaseMigrationParameters -ErrorAction Continue
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

    #Adding Sql MI specific details and starting the migration
    if($NewDatabaseMigrationParameters.Kind -eq "SqlMi")
    {
        $NewDatabaseMigrationParameters.ManagedInstanceName = $serverInfo["ManagedInstanceName"]
        if($serverInfo["BlobFileshare"] -eq "fileshare")
        {
            $NewDatabaseMigrationParameters.FileSharePath = $serverInfo["FileSharePath"]
            $NewDatabaseMigrationParameters.FileShareUsername = $serverInfo["FileShareUsername"]
            $NewDatabaseMigrationParameters.FileSharePassword = $serverInfo["FileSharePassword"]
            $NewDatabaseMigrationParameters.StorageAccountResourceId = $serverInfo["StorageAccountResourceId"]
            $NewDatabaseMigrationParameters.StorageAccountKey = $serverInfo["StorageAccountKey"]
            #Changing the password to secure string
            $NewDatabaseMigrationParameters.FileSharePassword = toSecureString $NewDatabaseMigrationParameters.FileSharePassword ;
        }
        if($serverInfo["BlobFileshare"] -eq "blob")
        {
            $NewDatabaseMigrationParameters.AzureBlobStorageAccountResourceId = $serverInfo["AzureBlobStorageAccountResourceId"]
            $NewDatabaseMigrationParameters.AzureBlobContainerName = $serverInfo["AzureBlobContainerName"]
            $NewDatabaseMigrationParameters.AzureBlobAccountKey = $serverInfo["AzureBlobAccountKey"]
            $NewDatabaseMigrationParameters.OfflineConfigurationLastBackupName = $serverInfo["OfflineConfigurationLastBackupName"]
        }

        # Adding the databases to be migrated
        if($serverInfo["DatabasesFromSourceSql"] -eq $true)
        {
            $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
        }
        else{
            $DatabasesToMigrate = $serverInfo["databases"]
        }
        
        #Starting migration for each db one by one
        foreach ($DB in $DatabasesToMigrate)
        {   
            $NewDatabaseMigrationParameters.SourceDatabaseName = $DB
            $NewDatabaseMigrationParameters.TargetDbName = $DB
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

    #Adding Sql VM specific details and starting the migration
    if($NewDatabaseMigrationParameters.Kind -eq "SqlVm")
    {
        $NewDatabaseMigrationParameters.SqlVirtualMachineName = $serverInfo["SqlVirtualMachineName"]
        if($serverInfo["BlobFileshare"] -eq "fileshare")
        {
            $NewDatabaseMigrationParameters.FileSharePath = $serverInfo["FileSharePath"]
            $NewDatabaseMigrationParameters.FileShareUsername = $serverInfo["FileShareUsername"]
            $NewDatabaseMigrationParameters.FileSharePassword = $serverInfo["FileSharePassword"]
            $NewDatabaseMigrationParameters.StorageAccountResourceId = $serverInfo["StorageAccountResourceId"]
            $NewDatabaseMigrationParameters.StorageAccountKey = $serverInfo["StorageAccountKey"]
            #Changing the password to secure string
            $NewDatabaseMigrationParameters.FileSharePassword = toSecureString $NewDatabaseMigrationParameters.FileSharePassword ;
        }
        if($serverInfo["BlobFileshare"] -eq "blob")
        {
            $NewDatabaseMigrationParameters.AzureBlobStorageAccountResourceId = $serverInfo["AzureBlobStorageAccountResourceId"]
            $NewDatabaseMigrationParameters.AzureBlobContainerName = $serverInfo["AzureBlobContainerName"]
            $NewDatabaseMigrationParameters.AzureBlobAccountKey = $serverInfo["AzureBlobAccountKey"]
            $NewDatabaseMigrationParameters.OfflineConfigurationLastBackupName = $serverInfo["OfflineConfigurationLastBackupName"]
        }
        
        # Adding the databases to be migrated
        if($serverInfo["DatabasesFromSourceSql"] -eq $true)
        {
            $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
        }
        else{
            $DatabasesToMigrate = $serverInfo["databases"]
        }

        #Starting migration for each db one by one
        foreach ($DB in $DatabasesToMigrate)
        {
            $NewDatabaseMigrationParameters.SourceDatabaseName = $DB
            $NewDatabaseMigrationParameters.TargetDbName = $DB
            
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
                $instance = Get-AzDataMigrationToSqlManagedInstance -ManagedInstanceName $serverInfo["ManagedInstanceName"] -ResourceGroupName $serverInfo["ResourceGroupName"]  -Expand MigrationStatusDetails -TargetDbName $tdb -ErrorAction Continue -WarningAction SilentlyContinue
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
    if($serverInfo["Kind"] -eq "SqlVm")
    {  
        foreach ($DB in $DatabasesToMigrate)
        {
        
            #Write-Host "Checking status for Database $DB"
            try{
                $instance = Get-AzDataMigrationToSqlVM -SqlVirtualMachineName $serverInfo["SqlVirtualMachineName"] -ResourceGroupName $serverInfo["ResourceGroupName"]  -Expand MigrationStatusDetails -TargetDbName $DB -ErrorAction Continue -WarningAction SilentlyContinue
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
    if($serverInfo["Kind"] -eq "SqlDb")
    {  
        foreach ($DB in $DatabasesToMigrate)
        {
        
            #Write-Host "Checking status for Database $DB"
            try{
                $instance = Get-AzDataMigrationToSqlDb -SqlDbInstanceName $serverInfo["SqlDbInstanceName"] -ResourceGroupName $serverInfo["ResourceGroupName"]  -Expand MigrationStatusDetails -TargetDbName $DB -ErrorAction Continue -WarningAction SilentlyContinue
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






