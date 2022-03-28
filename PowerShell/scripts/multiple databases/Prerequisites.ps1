
################## Parameters Section ############################################################
# Below parameters are taken from user-config.json which contains some user decisions.
$Inputs = Get-Content -Path "$PSScriptRoot\user-config.json" | ConvertFrom-Json;
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
##############################Functions#######################################################

# This function isntalls IR (if needed) and registers a DMS to it.
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

function DmsSetup()
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
            # Since the DMS was offline or needed registration , register it
            InstallRegisterIR $DMSRG $DMSName
        }
    }

}

