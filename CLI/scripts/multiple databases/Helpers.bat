@rem -----------------------------------------Common Helpers------------------------------------


@rem Function to get %~2 property from json file %~3
@rem Syntax to call - CALL :ReturnValueJson x "name" "package.json".
:ReturnValueJson
for /f "tokens=1,2 delims=:{}, " %%A in (%~3) do (
   If "%%~A"=="%~2" set "%~1=%%~B"
)
EXIT /B 0

@rem Function to get %~2 number property from txt file %~3
@rem Syntax to call - CALL :ReturnValueTxt x 3 "package.txt".
:ReturnValueTxt
set /a "number=0"
for /f "tokens=*" %%s in (%~3) do ( 
  set /a "number+=1"
  If !number!==%~2 set "%~1=%%s"
)
EXIT /B 0

@rem Function to %~2 number property from txt file %~3
@rem Syntax to call - CALL :NumberOfItemsTxt x "package.txt".
:NumberOfItemsTxt
set /a "number=0"
for /f "tokens=*" %%s in (%~2) do ( 
  set /a "number+=1"
)
set "%~1=!number!"
EXIT /B 0

@rem Function to Get parameters of a migration like RG, MI/VM name, TargetDBName and Kind
@rem Syntax to call - CALL :GetMigrationParamters ResourceGroupName TargetPlatformName TargetDbName Kind "%FirstLine%".
:GetMigrationParamters
for /f "tokens=1,2,3,4 delims=: " %%A in ("%~5") do ( 
  set "%~1=%%~A"
  set "%~2=%%~B"
  set "%~3=%%~C"
  set "%~4=%%~D"
)
EXIT /B 0

@rem Function to exit in case any error is encountered. exit -1073741510 is similar to Ctrl+C execution
@rem Syntax to call - CALL :ErrorCatchExit 
:ErrorCatchExit
ECHO --------------- Error Occured: Exiting Script ---------------
ECHO Please press 'y' to safely exit the script or it may lead to unknown effects 
cmd /c exit -1073741510


@rem --------------------------- Migration Helpers ------------------


@rem GET expanded migration status details for SQL VM or SQL MI depending on the Target
@rem Syntax to call - CALL :GetMigrationDetails ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind
:GetMigrationDetails
If "%~4" == "SqlMi" (
   CALL az datamigration sql-managed-instance show --managed-instance-name "%~2" --resource-group "%~1" --target-db-name "%~3" --expand MigrationStatusDetails > JsonDump\_migrationStatus_%~3.json 
) ELSE (
   CALL az datamigration sql-vm show --resource-group "%~1" --sql-vm-name "%~2" --target-db-name "%~3" --expand MigrationStatusDetails > JsonDump\_migrationStatus_%~3.json
)
EXIT /B 0


@rem Perform cutover for the given migration
@rem Syntax to call - CALL :PerformCutover ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind
:PerformCutover
Setlocal EnableDelayedExpansion
CALL :GetMigrationDetails %~1 %~2 %~3 %~4
CALL :ReturnValueJson MigrationOperationId "migrationOperationId" "JsonDump\_migrationStatus_%~3.json"
ECHO --------------- Starting Cutover for the Ongoing Migration %~3 to %~2 ---------------
If "%~4" == "SqlMi" (
   CALL az datamigration sql-managed-instance cutover --managed-instance-name "%~2" --resource-group "%~1" --target-db-name "%~3" --migration-operation-id "!MigrationOperationId!" 
) ELSE (
   CALL az datamigration sql-vm cutover --resource-group "%~1" --sql-vm-name "%~2" --target-db-name "%~3" --migration-operation-id "!MigrationOperationId!"
)
CALL :GetMigrationDetails %~1 %~2 %~3 %~4
CALL :ReturnValueJson MigrationStatus "migrationStatus" "JsonDump\_migrationStatus_%~3.json"
If "!MigrationStatus!" == "Succeeded" (
   ECHO --------------- Cutover completed for the Ongoing Migration to %~4 for DB: %~3 ---------------
   ECHO %~1 %~2 %~3 %~4 >> "RuntimeTexts\CompletedMigrations.txt"
)
If NOT "!MigrationStatus!" == "Succeeded" (
   ECHO --------------- FAILED: Cutover failed for DB: %~3 - Please check JsonDump\_migrationStatus_%~3.json for more details ---------------
   ECHO %~1 %~2 %~3 %~4 >> "RuntimeTexts\FailedMigrations.txt"
)
EndLocal
EXIT /B 0


@rem Checks whether the given database is ready of cutover or not
@rem Syntax to call - CALL :CheckReadyForCutover X ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind
:CheckReadyForCutover
ECHO Checking %~4 restore status to %~3. Kind: %~5
SET val=1
CALL :GetMigrationDetails %~2 %~3 %~4 %~5
CALL :ReturnValueJson LastRestoredFilename "lastRestoredFilename" "JsonDump\_migrationStatus_%~4.json"
CALL :ReturnValueJson CurrentRestoringFilename "currentRestoringFilename" "JsonDump\_migrationStatus_%~4.json"
CALL :ReturnValueJson MigrationStatus "migrationStatus" "JsonDump\_migrationStatus_%~4.json"
CALL :ReturnValueJson PendingLogBackupsCount "pendingLogBackupsCount" "JsonDump\_migrationStatus_%~4.json"

If NOT "!MigrationStatus!" == "InProgress" (
   SET val=-1
   GOTO :CheckReadyForCutoverExit
)  
If NOT "!LastRestoredFilename!" == "!CurrentRestoringFilename!" (
   SET val=0
   GOTO :CheckReadyForCutoverExit
)
If Not "!PendingLogBackupsCount!" == "0" (
   SET val=0
   GOTO :CheckReadyForCutoverExit
)
If "!LastRestoredFilename!" == "null" (
   SET val=0
   GOTO :CheckReadyForCutoverExit
)

:CheckReadyForCutoverExit
SET "%~1=%val%"
EXIT /B 0


@rem Start Migrations of databases from a particular server
@rem Syntax to call - CALL :StartMigrationServerLevel ServerName
:StartMigrationServerLevel
Setlocal EnableDelayedExpansion

ECHO Starting Migration for Server: %~1

@rem Reading the migration-db-config.json
CALL :ReturnValueJson ResourceGroupName "ResourceGroupName" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson Scope "Scope" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson MigrationService "MigrationService" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson SourceSqlConnectionAuthentication "SourceSqlConnectionAuthentication" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson SourceSqlConnectionDataSource "SourceSqlConnectionDataSource" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson SourceSqlConnectionUserName "SourceSqlConnectionUserName" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson SourceSqlConnectionPassword "SourceSqlConnectionPassword" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson Kind "Kind" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson ManagedInstanceName "ManagedInstanceName" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson SqlVirtualMachineName "SqlVirtualMachineName" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson StorageAccountResourceId "StorageAccountResourceId" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson StorageAccountKey "StorageAccountKey" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson BlobFileshare "BlobFileshare" "ServersConfig\%~1.specs.json"
CALL :ReturnValueJson Offline "Offline" "user-config.json"

CALL :NumberOfItemsTxt NumberOfDbs "ServersConfig\%~1.db.txt"

SET cmdTargetMi=az datamigration sql-managed-instance create --managed-instance-name "!ManagedInstanceName!"
SET cmdTargetVm=az datamigration sql-vm create --sql-vm-name "!SqlVirtualMachineName!"
SET cmdCommonParam=--source-location "@ServersConfig\%~1.source-location.json" --migration-service "!MigrationService!" --scope "!Scope!" --source-sql-connection authentication="!SourceSqlConnectionAuthentication!" data-source="!SourceSqlConnectionDataSource!" password="!SourceSqlConnectionPassword!" user-name="!SourceSqlConnectionUserName!" --resource-group "!ResourceGroupName!"
SET cmdTargetLocation=--target-location account-key="!StorageAccountKey!" storage-account-resource-id="!StorageAccountResourceId!"
SET cmdOffline=--offline-configuration offline=!Offline!
SET cmdFinalParam=!cmdCommonParam!

If "!BlobFileshare!" == "fileshare" SET cmdFinalParam=!cmdFinalParam! !cmdTargetLocation!

SET BlobOffline=0
If "!Offline!" == "true" (
   SET cmdFinalParam=!cmdFinalParam! !cmdOffline!
   If "!BlobFileshare!" == "blob" (
      SET BlobOffline=1
   )
)

for /l %%i in (1, 1, !NumberOfDbs!+1) do (
   CALL :ReturnValueTxt DBName %%i "ServersConfig\%~1.db.txt"
   SET cmdDBParam=--source-database-name "!DBName!" --target-db-name "!DBName!"
   
   If !BlobOffline! == 1 (
      CALL :ReturnValueJson OfflineConfigurationLastBackupName "!DBName!_LastBackupName" "ServersConfig\%~1.specs.json"
      SET cmdFinalParam=!cmdFinalParam! last-backup-name="!OfflineConfigurationLastBackupName!"
   )

   ECHO --------------- Starting Migration to !Kind! for TargetDB !DBName! ---------------
   If "!Kind!" == "SqlMi" (
      CALL !cmdTargetMi! !cmdFinalParam! !cmdDBParam!> JsonDump\_migrationStatusCreate_!DBName!.json
   ) ELSE (
      CALL !cmdTargetVm! !cmdFinalParam! !cmdDBParam!> JsonDump\_migrationStatusCreate_!DBName!.json
   )
   set ProvisioningState=Null
   CALL :ReturnValueJson ProvisioningState "provisioningState" "JsonDump\_migrationStatusCreate_!DBName!.json"
   If "!ProvisioningState!" == "Succeeded" (
      ECHO --------------- Started Migration to !Kind! for TargetDB !DBName! ---------------
      If "!Kind!" == "SqlMi" (
         ECHO !ResourceGroupName! !ManagedInstanceName! !DBName! !Kind! >> "RuntimeTexts\InProgressMigrations.txt"
         ECHO !ResourceGroupName! !ManagedInstanceName! !DBName! !Kind! >> "RuntimeTexts\StartedMigrations.txt"
      ) ELSE (
         ECHO !ResourceGroupName! !SqlVirtualMachineName! !DBName! !Kind! >> "RuntimeTexts\InProgressMigrations.txt"
         ECHO !ResourceGroupName! !SqlVirtualMachineName! !DBName! !Kind! >> "RuntimeTexts\StartedMigrations.txt"
      )
   ) ELSE (
      ECHO --------------- FAILED to start Migration to !Kind! for TargetDB !DBName! ---------------
      ECHO --------------- Refer to _migrationStatusCreate_!DBName!.json for more details ---------------
      If "!Kind!" == "SqlMi" (
         ECHO !ResourceGroupName! !ManagedInstanceName! !DBName! !Kind! >> "RuntimeTexts\FailedMigrations.txt"
      ) ELSE (
         ECHO !ResourceGroupName! !SqlVirtualMachineName! !DBName! !Kind! >> "RuntimeTexts\FailedMigrations.txt"
      )
   )
)

EndLocal
EXIT /B 0


@rem Checks whether the given online database migration is ready of cutover or not
@rem Syntax to call - CALL :MonitorMigrationOnline
:MonitorMigrationOnline
Setlocal EnableDelayedExpansion

copy /y NUL "RuntimeTexts\InProgressMigrationsTemp.txt" >NUL
CALL :NumberOfItemsTxt NumInProgressMigs "RuntimeTexts\InProgressMigrations.txt"

for /l %%i in (1, 1, !NumInProgressMigs!+1) do (
   CALL :ReturnValueTxt MigrationLine %%i "RuntimeTexts\InProgressMigrations.txt"
   CALL :GetMigrationParamters ResourceGroupName TargetPlatformName TargetDbName Kind "!MigrationLine!"
   CALL :CheckReadyForCutover Status !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind!
   If !Status! == 1 (
      CALL :PerformCutover !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind!
   ) 
   If !Status! == -1 (
       ECHO --------------- FAILED or CANCELED: Migration to !Kind! for DB- !TargetDBName! FAILED. Check JsonDump\_migrationStatus_!TargetDbName!.json for more details ---------------
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\FailedMigrations.txt"
   )
   If !Status! == 0 (
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\InProgressMigrationsTemp.txt"
   )
)

CALL del "RuntimeTexts\InProgressMigrations.txt"
CALL rename "RuntimeTexts\InProgressMigrationsTemp.txt" "InProgressMigrations.txt"

EndLocal
EXIT /B 0


@rem Checks whether the given database migration has completed or not
@rem Syntax to call - CALL :MonitorMigrationOffline
:MonitorMigrationOffline
Setlocal EnableDelayedExpansion

copy /y NUL "RuntimeTexts\InProgressMigrationsTemp.txt" >NUL
CALL :NumberOfItemsTxt NumInProgressMigs "RuntimeTexts\InProgressMigrations.txt"

for /l %%i in (1, 1, !NumInProgressMigs!+1) do (
   CALL :ReturnValueTxt MigrationLine %%i "RuntimeTexts\InProgressMigrations.txt"
   CALL :GetMigrationParamters ResourceGroupName TargetPlatformName TargetDbName Kind "!MigrationLine!"
   CALL :GetMigrationDetails !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind!
   CALL :ReturnValueJson MigrationStatus "migrationStatus" "JsonDump\_migrationStatus_!TargetDbName!.json"
   If "!MigrationStatus!" == "Succeeded" (
      ECHO --------------- COMPLETED: Migration to !Kind! for DB- !TargetDBName! completed ---------------
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\CompletedMigrations.txt"
   ) 
   If "!MigrationStatus!" == "Failed" (
      ECHO --------------- FAILED: Migration to !Kind! for DB- !TargetDBName! FAILED. Check JsonDump\_migrationStatus_!TargetDbName!.json for more details ---------------
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\FailedMigrations.txt"
   )
   If "!MigrationStatus!" == "Canceled" (
      ECHO --------------- CANCELED: Migration to !Kind! for DB- !TargetDBName! Canceled ---------------
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\FailedMigrations.txt"
   )
   If "!MigrationStatus!" == "InProgress" (
      ECHO !ResourceGroupName! !TargetPlatformName! !TargetDbName! !Kind! >> "RuntimeTexts\InProgressMigrationsTemp.txt"
   )
)

CALL del "RuntimeTexts\InProgressMigrations.txt"
CALL rename "RuntimeTexts\InProgressMigrationsTemp.txt" "InProgressMigrations.txt"

EndLocal
EXIT /B 0