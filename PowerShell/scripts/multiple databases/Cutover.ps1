# import
. "$PSScriptRoot\Helpers.ps1"

# Keeps trying for cutover, whenever a db is ready, cutover will start.
function StartCutover(){
    $serversAndDatabasesObject = Get-Content -Path "$PSScriptRoot\migration-server-config.json" | ConvertFrom-Json;
    $serversAndDatabases = $serversAndDatabasesObject.Servers
    # Hashtable to keep track of the migrations for which the cutover is complete
    $cutoverCompleted = @{}
    while ($true) {
        Start-Sleep -Seconds 60
        # $allComplete tells whether all migrations have started. If yes, the looping stops.
        $allComplete = $true
        foreach ($k in $serversAndDatabases)
        {   
            # the below section stores the server related information (like authentication, data source, username, poassword and databases to migrate) of a particular server in $serverInfo 
            $serverInfo = @{};
            $k.psobject.properties | Foreach{ $serverInfo[$_.Name] = $_.Value };
            if($serverInfo["Cutover"] -eq $true -And $serverInfo["Offline"] -ne $true -And $serverInfo["Kind"] -ne "SqlDb" )
            {               
                # Adding the databases to be migrated
                if($serverInfo["DatabasesFromSourceSql"] -eq $true)
                {
                    $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
                }
                else{
                    $DatabasesToMigrate = $serverInfo["databases"]
                }

                #cutover for Sql MI 
                if($serverInfo["Kind"] -eq "SqlMi")
                {      
                    #Trying cutover for each db one by one
                    foreach ($DB in $DatabasesToMigrate)
                    {                      
                        $tdb = $DB
                        try{
                            $MigrationDetails = Get-AzDataMigrationToSqlManagedInstance -ManagedInstanceName $serverInfo["ManagedInstanceName"] -ResourceGroupName $serverInfo["ResourceGroupName"] -TargetDbName $tdb -Expand MigrationStatusDetails -WarningAction SilentlyContinue
                            if($MigrationDetails.MigrationStatus -eq "Succeeded" -Or $MigrationDetails.MigrationStatus -eq "Canceled" -Or $MigrationDetails.ProvisioningState -eq "Failed" -Or $MigrationDetails.MigrationStatus -eq "Failed")
                            {
                                $cutoverCompleted[$tdb] = 1
                            }
                            else{
                                $cutoverCompleted[$tdb] = 0
                            }              
                            $instance = Invoke-AzDataMigrationCutoverToSqlManagedInstance -ResourceGroupName $serverInfo["ResourceGroupName"] -ManagedInstanceName $serverInfo["ManagedInstanceName"] -TargetDbName  $tdb -MigrationOperationId $MigrationDetails.MigrationOperationId -WarningAction SilentlyContinue
                        }
                        catch{
                        write-host "" -ErrorAction Continue
                        }
                    }     
                }

                #Cutover for Sql VM 
                if($serverInfo["Kind"] -eq "SqlVm")
                {       
                    #Trying cutover for each db one by one
                    foreach ($DB in $DatabasesToMigrate)
                    {
                        
                        try{
                            $MigrationDetails = Get-AzDataMigrationToSqlVM -SqlVirtualMachineName $serverInfo["SqlVirtualMachineName"] -ResourceGroupName $serverInfo["ResourceGroupName"] -TargetDbName $DB -Expand MigrationStatusDetails -WarningAction SilentlyContinue
                            # If a migration has succeeded or failed, we mark it. This helps us in knowing if some migrations have stuck in between (neither succeeded nor failed)
                            if($MigrationDetails.MigrationStatus -eq "Succeeded" -Or $MigrationDetails.MigrationStatus -eq "Canceled" -Or $MigrationDetails.ProvisioningState -eq "Failed" -Or $MigrationDetails.MigrationStatus -eq "Failed")
                            {
                                $cutoverCompleted[$DB] = 1
                            }
                            else
                            {
                                $cutoverCompleted[$DB] = 0
                            }
                            $instance = Invoke-AzDataMigrationCutoverToSqlVM -SqlVirtualMachineName $serverInfo["SqlVirtualMachineName"] -ResourceGroupName $serverInfo["ResourceGroupName"]  -TargetDbName $DB -MigrationOperationId $MigrationDetails.MigrationOperationId -WarningAction SilentlyContinue
                        }
                        catch{ 
                            write-host "" -ErrorAction Continue
                        }   
                    } 
                }                           
            }           
        }
        # To check if there are any stuck migrations. 
        foreach ($key in $cutoverCompleted.Keys){
            if($cutoverCompleted[$key] -eq 0)
            {
                $allComplete = $false
                break  
            }
        }
        # Break out of the while loop if all migrations have either succeeded or failed
        if ($allComplete -eq $true)
        {
            break
        }        
    }
    Write-Host "All cutovers are complete"
}
