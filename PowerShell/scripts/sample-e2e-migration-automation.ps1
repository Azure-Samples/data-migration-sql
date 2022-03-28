################## Parameters Section ############################################################
# migration-db-config.json contains all the parameters needed for a new migration. The below section reads those parameters
$NewDatabaseMigrationInfo = Get-Content -Path "$PSScriptRoot\migration-db-config.json" | ConvertFrom-Json;

# Below parameters are taken from user-config.json which contains some user decisions.
$Inputs = Get-Content -Path "$PSScriptRoot\user-config.json" | ConvertFrom-Json;

# This variable will be set to false if some input value is wrong and we'll ask the user to rectify the parameters  
$inputsValid = $true
# Parameter telling whether using blob or fileshare (blob/fileshare).
$BlobFileshare = $Inputs.BlobFileshare
if($BlobFileshare -ne "blob" -And $BlobFileshare -ne "fileshare")
{
    Write-Host "Invalid value provided for the parameter 'BlobFileshare' . The valid values are : blob , fileshare "
    $inputsValid = $false
}
#This portion makes sure that we provide only one of  (fileshare or blob) parameters
if($BlobFileshare -eq "fileshare")
{
    $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobStorageAccountResourceId')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobContainerName')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('AzureBlobAccountKey')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('OfflineConfigurationLastBackupName')
}
if($BlobFileshare -eq "blob")
{
    $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePath')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('FileShareUsername')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('FileSharePassword')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountResourceId')
    $NewDatabaseMigrationInfo.PSObject.properties.remove('StorageAccountKey')
}

#This portion makes sure that we provide only one of (SQL MI or SQL VM ) related parameters
$Kind =  $NewDatabaseMigrationInfo.Kind

if($Kind -eq "SqlMi")
{
    $NewDatabaseMigrationInfo.PSObject.properties.remove('SqlVirtualMachineName')
}
if($Kind -eq "SqlVm")
{
    $NewDatabaseMigrationInfo.PSObject.properties.remove('ManagedInstanceName')
}

# Storing the parameters in $NewDatabaseMigrationInfo in a dictionary $NewDatabaseMigrationParameters which can be directly passed to New-AzDataMigrationToSqlManagedInstance / New-AzDataMigrationToSqlVM commandlets.
$NewDatabaseMigrationParameters = @{};
$NewDatabaseMigrationInfo.psobject.properties | Foreach{ $NewDatabaseMigrationParameters[$_.Name] = $_.Value };

# Storing some parameter values that are frequently used.
$Kind = $NewDatabaseMigrationParameters["Kind"]
$ResourceGroupName = $NewDatabaseMigrationParameters["ResourceGroupName"]
$TargetDbName = $NewDatabaseMigrationParameters["TargetDbName"]
$ManagedInstanceName = $NewDatabaseMigrationParameters["ManagedInstanceName"]
$SqlVirtualMachineName = $NewDatabaseMigrationParameters["SqlVirtualMachineName"]

# Parameter telling whether the user wants to perform cutover (true/false).
$Cutover = $Inputs.Cutover
# Parameter telling whether a New DMS creation is required (true/false).
$NewDMS = $Inputs.NewDMS
# Parameters for creating a new DMS.
$NewDMSLocation = $Inputs.NewDMSLocation
$NewDMSRG = $Inputs.NewDMSRG
$NewDMSName = $Inputs.NewDMSName
# Parameter telling whether IR installation is required or not (true/false).
$InstallIR = $Inputs.InstallIR
# The path where IR is downloaded(used in case IR installation is needed).
$IRPath = $Inputs.IRPath
# Info regarding the DMS being used (in case an existing one is used instead of creating a new one).
$DMSRG = $Inputs.DMSRG
$DMSName = $Inputs.DMSName
# Parameter telling whether the user wants to keep checking mnigration status until it succeeds or fails.
$WaitTillCompletion = $Inputs.WaitTillCompletion

##############################Functions#######################################################

# This function installs IR (if needed) and registers a DMS to it.
function InstallRegisterIR([string]$ResourceGroup, [string]$DMS)
{  
    # Getting the auth keys for the given DMS
    $AuthKeys = Get-AzDataMigrationSqlServiceAuthKey -ResourceGroupName $ResourceGroup -SqlMigrationServiceName $DMS
    
    # Installing the IR and then registering :-
    if($InstallIR -eq $true)
    {        
        Register-AzDataMigrationIntegrationRuntime -AuthKey $AuthKeys.AuthKey1 -IntegrationRuntimePath $IRPath
    }
    # If IR is already installed , just registration is required :-
    else
    {
        Register-AzDataMigrationIntegrationRuntime -AuthKey $AuthKeys.AuthKey1
    }
    
    #Wait till dms status shows online
    $dmsDetails = Get-AzDataMigrationSqlService -Name $DMS -ResourceGroupName $ResourceGroup
    while($dmsDetails.IntegrationRuntimeState -eq "Offline" -Or $dmsDetails.IntegrationRuntimeState -eq "NeedRegistration")
    {
        Start-Sleep -Seconds 5
        $dmsDetails = Get-AzDataMigrationSqlService -Name $DMS -ResourceGroupName $ResourceGroup       
    }

    Write-Host "SHIR registration completed successfully" -ForegroundColor Green
}

# This function gets the specified database migration for a given SQL Managed Instance or SQL VM
function GetDatabaseMigrationDetails()
{
    if($Kind -eq "SqlMi")
    {
        $MigrationDetails =  Get-AzDataMigrationToSqlManagedInstance -ManagedInstanceName $ManagedInstanceName -ResourceGroupName $ResourceGroupName -TargetDbName $TargetDbName -Expand MigrationStatusDetails
    }
    else
    {
        $MigrationDetails =  Get-AzDataMigrationToSqlVM -SqlVirtualMachineName $SqlVirtualMachineName -ResourceGroupName $ResourceGroupName -TargetDbName $TargetDbName -Expand MigrationStatusDetails
    }

    return $MigrationDetails
}

# This function waits till the migration is ready for cutover
function WaitTillReadyForCutover([string]$BlobFileshare)
{  
    Write-Host "Waiting for migration to be ready for cutover" -ForegroundColor Green
    $MigrationDetails = GetDatabaseMigrationDetails
    # In case blob is used, the migration is ready for cutover when CurrentRestoringFilename is same as LastRestoringFileName
    if($BlobFileshare -eq "blob")
    {
        
        while($MigrationDetails.MigrationStatusDetail.CurrentRestoringFilename -eq $null -Or $MigrationDetails.MigrationStatusDetail.LastRestoredFilename -eq $null){
            if($MigrationDetails.MigrationStatus -eq "Canceled")
            {
                Write-Host "Can not perform cutover as the Migration was canceled" -ForegroundColor Red
                break
            }
            Start-Sleep -Seconds 10
            $MigrationDetails = GetDatabaseMigrationDetails
        }
        while($MigrationDetails.MigrationStatusDetail.CurrentRestoringFilename -ne $MigrationDetails.MigrationStatusDetail.LastRestoredFilename)
        {   
            if($MigrationDetails.MigrationStatus -eq "Canceled")
            {
                Write-Host "Can not perform cutover as the Migration was canceled" -ForegroundColor Red
                break
            }
            Start-Sleep -Seconds 10
            $MigrationDetails =  GetDatabaseMigrationDetails
        }
        
    } 
    # In case of fileshare, the Migration is ready for cutover when IsFullBackupRestored is true and PendingLogBackupsCount is 0
    else 
    {
        while(-Not $MigrationDetails.MigrationStatusDetail.IsFullBackupRestored){
            if($MigrationDetails.MigrationStatus -eq "Canceled")
            {
                Write-Host "Can not perform cutover as the Migration was canceled" -ForegroundColor Red
                break
            }
            Start-Sleep -Seconds 10
            $MigrationDetails =  GetDatabaseMigrationDetails
        }
        # Now FullBackuprestored is true, we also need to make sure  that PendingLogBackupsCount is 0
        
        while($MigrationDetails.MigrationStatusDetail.PendingLogBackupsCount -ne 0)
        {
            if($MigrationDetails.MigrationStatus -eq "Canceled")
            {
                Write-Host "Can not perform cutover as the Migration was canceled" -ForegroundColor Red
                break
            }
            Start-Sleep -Seconds 10
            $MigrationDetails =  GetDatabaseMigrationDetails
        }
    }
    if($MigrationDetails.MigrationStatus -ne "Canceled")
    {
        Write-Host "Ready for cutover" -ForegroundColor Green
    }

    return $MigrationDetails
}

# This function performs the cutover, when the Migration is ready
function PerformCutover()
{
    # Wait till the migration is ready for cutover to be performed
    $MigrationDetails = WaitTillReadyForCutover $BlobFileshare
    if($MigrationDetails.MigrationStatus -ne "Canceled")
    {
        if($Kind -eq "SqlMi")
        {
            Invoke-AzDataMigrationCutoverToSqlManagedInstance -ResourceGroupName $ResourceGroupName -ManagedInstanceName $ManagedInstanceName -TargetDbName  $TargetDbName -MigrationOperationId $MigrationDetails.MigrationOperationId
        }
        else
        {
            Invoke-AzDataMigrationCutoverToSqlVM -ResourceGroupName $ResourceGroupName -SqlVirtualMachineName $SqlVirtualMachineName -TargetDbName  $TargetDbName -MigrationOperationId $MigrationDetails.MigrationOperationId
        }
        Write-Host "Cutover initiated" -ForegroundColor Green
    }
}

# This function keeps checking the migration status until it has succeeded or failed
function WaitForCompleteMigration()
{
    $MigrationDetails = GetDatabaseMigrationDetails
    $failed = $false

    # Looping till Migration succeeds or fails
    Write-Host "Checking Migration Status"
    while($MigrationDetails.MigrationStatus -ne "Succeeded"){
        # In case migration failed
        if($MigrationDetails.MigrationStatus -eq "Failed")
        {
            $failed = $true
            $failureMessage = $MigrationDetails.MigrationFailureErrorMessage
            Write-Host "$failureMessage" -ForegroundColor Red
            break
        }
        # In case migration was canceled
        if($MigrationDetails.MigrationStatus -eq "Canceled")
        {
            $failed = $true
            Write-Host "Migration was canceled" -ForegroundColor Red
            break
        }
        Start-Sleep -Seconds 10
        $MigrationDetails =  GetDatabaseMigrationDetails
    }
    
    # Migration succeeded
    if($failed -eq $false)
    {
        Write-Host "Migration succeeded" -ForegroundColor Green
    }
}

# This function starts the actual migration 
function NewDatabaseMigration()
{
    if($Kind -eq "SqlMi")
    {   
        # Start the migration to managed instance
        $instance = New-AzDataMigrationToSqlManagedInstance @NewDatabaseMigrationParameters      
    }
    else
    {
        # Start the migration to SQL VM
        $instance = New-AzDataMigrationToSqlVM @NewDatabaseMigrationParameters             
    }
    Write-Host "Migration started" -ForegroundColor Green

}
function main()
{
    # If the user has chosen to create a new SQL DMS
    if ($NewDMS -eq $true)
    {
        # This creates a new SQL DMS
        New-AzDataMigrationSqlService -ResourceGroupName $NewDMSRG -SqlMigrationServiceName $NewDMSName -Location $NewDMSLocation
        #Since the DMS is new, it needs registration
        InstallRegisterIR $NewDMSRG $NewDMSName
    }
    # If the user is using an existing DMS, check if it requires registration
    else 
    { 
        $dmsDetails = Get-AzDataMigrationSqlService -Name $DMSName -ResourceGroupName $DMSRG 
        if($dmsDetails.IntegrationRuntimeState -eq "Offline" -Or $dmsDetails.IntegrationRuntimeState -eq "NeedRegistration")
        {
            # Since the DMS was offline , register it
            InstallRegisterIR $DMSRG $DMSName
        }
    }

    # This function starts the migration
    NewDatabaseMigration
    
    $MigrationDetails = GetDatabaseMigrationDetails

    # If user wants to perform cutover on an online migration :-
    if($Cutover -eq $true -And $MigrationDetails.OfflineConfigurationOffline -ne $true)
    {
        PerformCutover
    }

    # If user wants to wait till Migration is succeeded :-
    if($WaitTillCompletion -eq $true)
    {
        WaitForCompleteMigration
    }
}
if($inputsValid -eq $true)
{
    main
}