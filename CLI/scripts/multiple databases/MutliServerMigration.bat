@echo off
setlocal enabledelayedexpansion

@rem Reading the user-config.json parameters
CALL :ReturnValueJson WaitTillCompletion "WaitTillCompletion" "user-config.json"
CALL :ReturnValueJson Cutover "Cutover" "user-config.json"
CALL :ReturnValueJson Offline "OfflineOrSqlDb" "user-config.json"

ECHO --------------- JSON Variables loaded and Execution started ---------------

ECHO --------------- Creating JsonDump Folder to store response Jsons ---------------
If exist JsonDump CALL rmdir /Q /S JsonDump
CALL mkdir JsonDump 
ECHO --------------- Created JsonDump Folder ---------------

ECHO --------------- Creating RuntimeTexts Folder to store response Migration Runtime Details ---------------
If exist RuntimeTexts CALL rmdir /Q /S RuntimeTexts
CALL mkdir RuntimeTexts 
ECHO --------------- Created RuntimeTexts Folder ---------------

copy /y NUL "RuntimeTexts\StartedMigrations.txt" >NUL
copy /y NUL "RuntimeTexts\InProgressMigrations.txt" >NUL
CALL :NumberOfItemsTxt NoOfServers "ServersConfig\_ServerList.txt"
for /l %%i in (1, 1, !NoOfServers!+1) do (
    CALL :ReturnValueTxt ServerName %%i "ServersConfig\_ServerList.txt"
    CALL :StartMigrationServerLevel !ServerName!
)

If "!Offline!" == "true" (
    If "!WaitTillCompletion!" == "false" GOTO :ScriptExitPoint
) ELSE (
    If "!Cutover!" == "false" GOTO :ScriptExitPoint
)


:UntilFinished

CALL :NumberOfItemsTxt NumInProgress "RuntimeTexts\InProgressMigrations.txt"
If !NumInProgress! == 0 GOTO :ScriptExitPoint
ECHO ----------------- Starting Iteration to check status of In-Progress Migration -------------------
If "!Offline!" == "true" (
    CALL :MonitorMigrationOffline
) ELSE (
    CALL :MonitorMigrationOnline
)
timeout /t 240
GOTO :UntilFinished


:ScriptExitPoint
ECHO ------------------- Exiting Script -----------------------
ECHO ------- Check CompletedMigrations.txt and FailedMigrations.txt for more details on migrations ----------
EndLocal
EXIT /B %ERRORLEVEL%

@rem Function to exit in case any error is encountered. exit -1073741510 is similar to Ctrl+C execution
@rem Syntax to call - CALL :ErrorCatchExit 
:ErrorCatchExit
    Helpers.bat %*

@rem Function to get %~2 property from json file %~3
@rem Syntax to call - CALL :ReturnValue Name "name" "package.json".
:ReturnValueJson
    Helpers.bat %*

@rem Function to get %~2 number property from txt file %~3
@rem Syntax to call - CALL :ReturnValueTxt x 3 "package.txt".
:ReturnValueTxt
    Helpers.bat %*

@rem Function to %~2 number property from txt file %~3
@rem Syntax to call - CALL :NumberOfItemsTxt x "package.txt".
:NumberOfItemsTxt
    Helpers.bat %*

@rem GET expanded migration status details for SQL VM or SQL MI depending on the Target
@rem Syntax to call - CALL :GetMigrationDetails ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind
:GetMigrationDetails
    Helpers.bat %*

@rem Perform cutover for the given migration
@rem Syntax to call - CALL :PerformCutover ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind
:PerformCutover
    Helpers.bat %*

@rem Function to Get parameters of a migration like RG, MI/VM name, TargetDBName
@rem Syntax to call - CALL :GetMigrationParameters X1 X2 X3 X4 InputValue.
:GetMigrationParamters
    Helpers.bat %*

@rem Start Migrations of databases from a particular server
@rem Syntax to call - CALL :StartMigrationServerLevel ServerName
:StartMigrationServerLevel
    Helpers.bat %*

@rem Checks whether the given database is ready of cutover or not
@rem Syntax to call - CALL :CheckReadyForCutover X ResourceGroupName ManagedInstanceName/SqlVmName TargetDbName Kind 
:CheckReadyForCutover
    Helpers.bat %*

@rem Checks whether the given database migration has completed or not
@rem Syntax to call - CALL :MonitorMigrationOffline
:MonitorMigrationOffline
    Helpers.bat %*

@rem Checks whether the given online database migration is ready of cutover or not
@rem Syntax to call - CALL :MonitorMigrationOnline
:MonitorMigrationOnline
    Helpers.bat %*
