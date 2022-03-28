@echo off  

@rem Reading the user-config.json parameters
CALL :ReturnValue NewDMS "NewDMS" "user-config.json"
CALL :ReturnValue NewDMSLocation "NewDMSLocation" "user-config.json"
CALL :ReturnValue NewDMSRG "NewDMSRG" "user-config.json"
CALL :ReturnValue NewDMSName "NewDMSName" "user-config.json"
CALL :ReturnValue DMSName "DMSName" "user-config.json"
CALL :ReturnValue DMSRG "DMSRG" "user-config.json"
CALL :ReturnValue BlobFileshare "BlobFileshare" "user-config.json"
CALL :ReturnValue WaitTillCompletion "WaitTillCompletion" "user-config.json"
CALL :ReturnValue Cutover "Cutover" "user-config.json"

@rem Reading the migration-db-config.json
CALL :ReturnValue ResourceGroupName "ResourceGroupName" "migration-db-config.json"
CALL :ReturnValue TargetDbName "TargetDbName" "migration-db-config.json"
CALL :ReturnValue Scope "Scope" "migration-db-config.json"
CALL :ReturnValue MigrationService "MigrationService" "migration-db-config.json"
CALL :ReturnValue SourceSqlConnectionAuthentication "SourceSqlConnectionAuthentication" "migration-db-config.json"
CALL :ReturnValue SourceSqlConnectionDataSource "SourceSqlConnectionDataSource" "migration-db-config.json"
CALL :ReturnValue SourceSqlConnectionUserName "SourceSqlConnectionUserName" "migration-db-config.json"
CALL :ReturnValue SourceSqlConnectionPassword "SourceSqlConnectionPassword" "migration-db-config.json"
CALL :ReturnValue SourceDatabaseName "SourceDatabaseName" "migration-db-config.json"
CALL :ReturnValue Kind "Kind" "migration-db-config.json"
CALL :ReturnValue ManagedInstanceName "ManagedInstanceName" "migration-db-config.json"
CALL :ReturnValue SqlVirtualMachineName "SqlVirtualMachineName" "migration-db-config.json"
CALL :ReturnValue StorageAccountResourceId "StorageAccountResourceId" "migration-db-config.json"
CALL :ReturnValue StorageAccountKey "StorageAccountKey" "migration-db-config.json"
CALL :ReturnValue AzureBlobAccountKey "Scope" "migration-db-config.json"
CALL :ReturnValue AzureBlobContainerName "Scope" "migration-db-config.json"
CALL :ReturnValue AzureBlobStorageAccountResourceId "AzureBlobStorageAccountResourceId" "migration-db-config.json"
CALL :ReturnValue OfflineConfigurationLastBackupName "OfflineConfigurationLastBackupName" "migration-db-config.json"
CALL :ReturnValue Offline "Offline" "migration-db-config.json"

ECHO --------------- JSON Variables loaded and Execution started ---------------

ECHO --------------- Creating JsonDump Folder to store response Jsons ---------------
If exist JsonDump CALL rmdir /Q /S JsonDump
CALL mkdir JsonDump 
ECHO --------------- Created JsonDump Folder ---------------

CALL :SetupDMS %NewDMS% %NewDMSRG% %NewDMSName% %NewDMSLocation% %DMSName% %DMSRG%
CALL :StartMigration
If "%Offline%" == "true" If "%WaitTillCompletion%" =="true" (
   CALL :WaitForCompleteMigration
)
If "%Offline%" == "false" If "%Cutover%" == "true" (
   CALL :WaitTillReadyForCutover
   CALL :PerformCutover
)

EXIT /B %ERRORLEVEL%

@rem Function to get %~2 property from json file %~3
@rem Syntax to call - CALL :ReturnValue x "name" "package.json".
:ReturnValue
for /f "tokens=1,2 delims=:{}, " %%A in (%~3) do (
   If "%%~A"=="%~2" set "%~1=%%~B"
)
EXIT /B 0

@rem Registers the DMS on SHIR
@rem Syntax to call - CALL :RegisterIntegrationRuntime %DMSRG% %DMSName%
:RegisterIntegrationRuntime
CALL az datamigration sql-service list-auth-key -g "%~1" -n "%~2" > JsonDump\_authkeys.json 
CALL :ReturnValue AuthKey "authKey1" "JsonDump\_authkeys.json"
CALL az datamigration register-integration-runtime --auth-key "%AuthKey%"
:CheckIRStatus @rem GOTO point to check if the DMS is online or not
CALL az datamigration sql-service show -g "%~1" -n "%~2" > JsonDump\_sqlserviceStatus.json
timeout /t 10
CALL :ReturnValue IntegrationRuntimeState "integrationRuntimeState" "JsonDump\_sqlserviceStatus.json"
If NOT "%IntegrationRuntimeState%" == "Online" (
   ECHO Checking Integration Runtime State of DMS - %~2
   GOTO :CheckIRStatus
)
ECHO --------------- Successfully Registered SHIR ---------------
EXIT /B 0

@rem Sets up the DMS i.e. creates or/and registers it on SHIR
@rem Syntax to call - CALL :SetupDMS  %NewDMS% %NewDMSRG% %NewDMSName% %NewDMSLocation% %DMSName% %DMSRG%
:SetUpDMS
Setlocal EnableDelayedExpansion
If "%~1" == "true" (
   ECHO --------------- Creating Database Migration Service ---------------
   CALL az datamigration sql-service create -g "%~2" -n "%~3" --location "%~4" > "JsonDump\_sqlserviceCreate.json"
   set ProvisioningState_Service=null
   CALL :ReturnValue ProvisioningState_Service "provisioningState" "JsonDump\_sqlserviceCreate.json"
   If "!ProvisioningState_Service!" == "Succeeded" (
      ECHO --------------- Created Database Migration Service ----------------
      If "%BlobFileshare%" == "fileshare" CALL :RegisterIntegrationRuntime %~2 %~3
   ) ELSE (
      ECHO --------------- FAILED: Creation failed of Database Migration Service ----------------
      CALL :ErrorCatchExit
   )
) ELSE (
   ECHO --------------- Using existing Database Migration Service ---------------
   CALL az datamigration sql-service show -g "%~6" -n "%~5" > JsonDump\_sqlservice.json
   If "%BlobFileshare%" == "fileshare" (
      set IntegrationRuntimeState=null
      CALL :ReturnValue IntegrationRuntimeState "integrationRuntimeState" "JsonDump\_sqlservice.json"
      If "!IntegrationRuntimeState!" == "null" (
         ECHO --------------- FAILED: Unable to read IR state of service ----------------
         CALL :ErrorCatchExit
      )
      If NOT "!IntegrationRuntimeState!" == "Online" (
         ECHO --------------- Migration Service is not Online ---------------
         CALL :RegisterIntegrationRuntime %~6 %~5
      ) ELSE (
         ECHO --------------- Migration Service is already Online ---------------
      )
   )
)
EndLocal
EXIT /B 0

@rem GET expanded migration status details for SQL VM or SQL MI depending on the Target
@rem Syntax to call - CALL :GetMigrationDetails (It uses global values so no parameters are required)
:GetMigrationDetails
If "%Kind%" == "SqlMi" (
   CALL az datamigration sql-managed-instance show --managed-instance-name "%ManagedInstanceName%" --resource-group "%ResourceGroupName%" --target-db-name "%TargetDbName%" --expand MigrationStatusDetails > JsonDump\_migrationStatus.json 
) ELSE (
   CALL az datamigration sql-vm show --resource-group "%ResourceGroupName%" --sql-vm-name "%SqlVirtualMachineName%" --target-db-name "%TargetDbName%" --expand MigrationStatusDetails > JsonDump\_migrationStatus.json
)
EXIT /B 0


@rem GET expanded migration status details for SQL VM or SQL MI depending on the Target
@rem Syntax to call - CALL :WaitTillReadyForCutover (It uses global values so no parameters are required)
:WaitTillReadyForCutover 
ECHO --------------- Waiting for Migration to be ready for cutover ---------------

:NoNullValues @rem GOTO point to wait till last and current restored files are not null
ECHO Waiting for backup files to be uploaded and start restoring - %TargetDbName%
timeout /t 120
CALL :GetMigrationDetails
CALL :ReturnValue LastRestoredFilename "lastRestoredFilename" "JsonDump\_migrationStatus.json"
CALL :ReturnValue CurrentRestoringFilename "currentRestoringFilename" "JsonDump\_migrationStatus.json"
CALL :ReturnValue MigrationStatus "migrationStatus" "JsonDump\_migrationStatus.json"
If NOT "%MigrationStatus%" == "InProgress" GOTO :ExitPoint
If "%LastRestoredFilename%" == "null" GOTO :NoNullValues
If "%CurrentRestoringFilename%" == "null" GOTO :NoNullValues

:CheckMigrationStatus @rem GOTO point to wait till last and current restored files are same (Cutover condition)
ECHO Waiting for backup files to be restored - %TargetDbName%
timeout /t 120
CALL :GetMigrationDetails
CALL :ReturnValue LastRestoredFilename "lastRestoredFilename" "JsonDump\_migrationStatus.json"
CALL :ReturnValue CurrentRestoringFilename "currentRestoringFilename" "JsonDump\_migrationStatus.json"
CALL :ReturnValue MigrationStatus "migrationStatus" "JsonDump\_migrationStatus.json"
CALL :ReturnValue PendingLogBackupsCount "pendingLogBackupsCount" "JsonDump\_migrationStatus.json"
If NOT "%MigrationStatus%" == "InProgress" GOTO :ExitPoint
If NOT "%LastRestoredFilename%" == "%CurrentRestoringFilename%" GOTO :CheckMigrationStatus
If Not "%PendingLogBackupsCount%" == "0" GOTO :CheckMigrationStatus

:ExitPoint @rem GOTO point for success and failed exits case
If NOT "%MigrationStatus%" == "InProgress" (
   ECHO --------------- FAILED: Migration was canceled or has filed. Please take a look at JsonDump\_migrationStatus.json ---------------
   CALL :ErrorCatchExit
)
If "%LastRestoredFilename%" == "%CurrentRestoringFilename%" ECHO --------------- Migration is ready for cutover ---------------
EXIT /B 0

@rem Perform cutover for the given migration
@rem Syntax to call - CALL :PerformCutover (It uses global values so no parameters are required)
:PerformCutover
CALL :GetMigrationDetails
CALL :ReturnValue MigrationOperationId "migrationOperationId" "JsonDump\_migrationStatus.json"
ECHO --------------- Starting Cutover for the Ongoing Migration ---------------
If "%Kind%" == "SqlMi" (
   CALL az datamigration sql-managed-instance cutover --managed-instance-name "%ManagedInstanceName%" --resource-group "%ResourceGroupName%" --target-db-name "%TargetDbName%" --migration-operation-id "%MigrationOperationId%" 
) ELSE (
   CALL az datamigration sql-vm cutover --resource-group "%ResourceGroupName%" --sql-vm-name "%SqlVirtualMachineName%" --target-db-name "%TargetDbName%" --migration-operation-id "%MigrationOperationId%"
)
CALL :GetMigrationDetails
CALL :ReturnValue MigrationStatus "migrationStatus" "JsonDump\_migrationStatus.json"
If "%MigrationStatus%" == "Succeeded" ECHO --------------- Cutover completed for the Ongoing Migration ---------------
If NOT "%MigrationStatus%" == "Succeeded" ECHO --------------- FAILED: Cutover failed - Please check JsonDump\_migrationStatus.json for more details ---------------
EXIT /B 0

@rem Start the migration with the given parameters
@rem Syntax to call - CALL :PerformCutover (It uses global values so no parameters are required)
:StartMigration
Setlocal EnableDelayedExpansion
SET cmdTargetMi=az datamigration sql-managed-instance create --managed-instance-name "%ManagedInstanceName%"
SET cmdTargetVm=az datamigration sql-vm create --sql-vm-name "%SqlVirtualMachineName%"
SET cmdCommonParam=--source-location "@source-location.json" --migration-service "%MigrationService%" --scope "%Scope%" --source-database-name "%SourceDatabaseName%" --source-sql-connection authentication="%SourceSqlConnectionAuthentication%" data-source="%SourceSqlConnectionDataSource%" password="%SourceSqlConnectionPassword%" user-name="%SourceSqlConnectionUserName%" --target-db-name "%TargetDbName%" --resource-group "%ResourceGroupName%" 
SET cmdTargetLocation=--target-location account-key="%StorageAccountKey%" storage-account-resource-id="%StorageAccountResourceId%"
SET cmdFileshareOffline=--offline-configuration offline=%Offline%
SET cmdBlobOffline=--offline-configuration last-backup-name="%OfflineConfigurationLastBackupName%" offline=%Offline%
SET cmdFinalParam=%cmdCommonParam%


If "%BlobFileshare%" == "fileshare" SET cmdFinalParam=%cmdFinalParam% %cmdTargetLocation%
If "%Offline%" == "true" (
   If "%BlobFileshare%" == "fileshare" SET cmdFinalParam=%cmdFinalParam% %cmdFileshareOffline%
   If "%BlobFileshare%" == "blob" SET cmdFinalParam=%cmdFinalParam% %cmdBlobOffline%
)

ECHO --------------- Starting Migration to %Kind% for TargetDB %TargetDbName% ---------------
If "%Kind%" == "SqlMi" (
   CALL %cmdTargetMi% %cmdFinalParam% > JsonDump\_migrationStatusCreate.json
) ELSE (
   CALL %cmdTargetVm% %cmdFinalParam% > JsonDump\_migrationStatusCreate.json
)
set ProvisioningState=null
CALL :ReturnValue ProvisioningState "provisioningState" "JsonDump\_migrationStatusCreate.json"
If "!ProvisioningState!" == "Succeeded" (
   ECHO --------------- Started Migration ---------------
) ELSE (
   ECHO --------------- FAILED to start Migration ---------------
   CALL :ErrorCatchExit
)
EndLocal
EXIT /B 0

@rem Wait for migration to complete in case of offline migration
@rem Syntax to call - CALL :WaitTillReadyForCutover (It uses global values so no parameters are required)
:WaitForCompleteMigration

:CheckMigrationStatusOffline
ECHO Waiting for Offline migration to complete - %TargetDbName%
CALL :GetMigrationDetails
timeout /t 120
CALL :ReturnValue MigrationStatus "migrationStatus" "JsonDump\_migrationStatus.json"
If NOT "%MigrationStatus%" == "InProgress" GOTO :ExitPointOffline
If "%MigrationStatus%" == "InProgress" GOTO :CheckMigrationStatusOffline

:ExitPointOffline
if "%MigrationStatus%" == "Succeeded" ECHO --------------- Migration Completed ---------------
if "%MigrationStatus%" == "Canceled" ECHO --------------- CANCELED: Migration Canceled ---------------
if "%MigrationStatus%" == "Failed" ECHO --------------- FAILED: Migration Failed. Please check JsonDump\_migrationStatus.json ---------------
EXIT /B 0

@rem Function to exit in case any error is encountered
@rem Syntax to call - CALL :ErrorCatchExit
:ErrorCatchExit
ECHO --------------- Error Occured: Exiting Script ---------------
ECHO Please press 'y' to safely exit the script or it may lead to unknown effects 
cmd /c exit -1073741510
