# import
. "$PSScriptRoot\Helpers.ps1"


# Hashtable to keep track of the migrations for which the cutover is complete
$cutoverCompleted = @{}

# Keeps trying for cutover, whenever a db is ready, cutover will start.
function StartCutover(){
    while ($true) {
        Start-Sleep -Seconds 60
        # $allComplete tells whether all migrations have started. If yes, the looping stops.
        $allComplete = $true
        foreach ($k in $serversAndDatabases)
        {   
            # the below section stores the server related information (like authentication, data source, username, poassword and databases to migrate) of a particular server in $serverInfo 
            Write-Host "server loop"
            $serverInfo = @{};
            $k.psobject.properties | Foreach{ $serverInfo[$_.Name] = $_.Value };
            if($serverInfo["Cutover"] -eq $true -And $serverInfo["Offline"] -ne $true )
            {
                
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
        
                # Adding the databases 
                if($serverInfo["DatabasesFromSourceSql"] -eq $true)
                {
                    $DatabasesToMigrate = Get-DatabasesToMigrate -dataSource $serverInfo["SourceSqlConnectionDataSource"] -sqlUserName $serverInfo["SourceSqlConnectionUserName"] -sqlPassword $serverInfo["SourceSqlConnectionPassword"] -sqlQueryToGetDbs $serverInfo["SqlQueryToGetDbs"]
                }
                else{
                    $DatabasesToMigrate = $serverInfo["databases"]
                }
                
                # loop over each db in the server
                if($serverInfo["Kind"] -eq "SqlMi")
                {   
                    foreach ($DB in $DatabasesToMigrate)
                    {                      
                        try{
                            $MigrationDetails = Get-AzDataMigrationToSqlManagedInstance -ManagedInstanceName $NewDatabaseMigrationParameters.ManagedInstanceName -ResourceGroupName $serverInfo["ResourceGroupName"] -TargetDbName $DB -Expand MigrationStatusDetails
                            if($MigrationDetails.MigrationStatus -eq "Succeeded" -Or $MigrationDetails.MigrationStatus -eq "Canceled" -Or $MigrationDetails.ProvisioningState -eq "Failed" -Or $MigrationDetails.MigrationStatus -eq "Failed")
                            {
                                $cutoverCompleted[$DB] = 1
                            }
                            else{
                                $cutoverCompleted[$DB] = 0
                            }
                            $instance = Invoke-AzDataMigrationCutoverToSqlManagedInstance -ResourceGroupName $serverInfo["ResourceGroupName"] -ManagedInstanceName $NewDatabaseMigrationParameters.ManagedInstanceName -TargetDbName  $tdb -MigrationOperationId $MigrationDetails.MigrationOperationId 
                        }
                        catch{
                            write-host "" -ErrorAction Continue
        
                        }
                    }   
                }
                else
                {  
                    foreach ($DB in $DatabasesToMigrate)
                    {
                
                        Write-Host "trying cutover for $DB"
                        try{
                            $MigrationDetails = Get-AzDataMigrationToSqlVM -SqlVirtualMachineName $NewDatabaseMigrationParameters.SqlVirtualMachineName -ResourceGroupName $serverInfo["ResourceGroupName"] -TargetDbName $DB -Expand MigrationStatusDetails
                            # If a migration has succeeded or failed, we mark it. This helps us in knowing if some migrations have stuck in between (neither succeeded nor failed)
                            if($MigrationDetails.MigrationStatus -eq "Succeeded" -Or $MigrationDetails.MigrationStatus -eq "Canceled" -Or $MigrationDetails.ProvisioningState -eq "Failed" -Or $MigrationDetails.MigrationStatus -eq "Failed")
                            {
                                $cutoverCompleted[$DB] = 1
                            }
                            else{
                                $cutoverCompleted[$DB] = 0
                            }
                            $instance = Invoke-AzDataMigrationCutoverToSqlVM -SqlVirtualMachineName $NewDatabaseMigrationParameters.SqlVirtualMachineName -ResourceGroupName $serverInfo["ResourceGroupName"]  -TargetDbName $DB -MigrationOperationId $MigrationDetails.MigrationOperationId 
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

    