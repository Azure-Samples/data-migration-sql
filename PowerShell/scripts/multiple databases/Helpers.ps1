# This function always assumes SQL Authentication. Update if needed.
function Invoke-SqlLCommand {
    param(
        [string] $dataSource,
        [string] $sqlCommand,
        [string] $sqlUserName,
        [string] $sqlPassword
      )

    $connectionString = "Data Source=$dataSource; User Id=$sqlUserName; Password=$sqlPassword;";
    try{
    $connection = New-Object System.Data.SqlClient.SQLConnection($connectionString)  
    $commandObj = New-Object System.Data.SqlClient.SqlCommand($sqlCommand, $connection)  
    $connection.Open()  
    
    $adapter = New-Object System.Data.sqlclient.sqlDataAdapter $commandObj  
    $dataset = New-Object System.Data.DataSet  
    $adapter.Fill($dataSet) | Out-Null  
    
    $connection.Close() 

    # return the response
    $dataSet.Tables 
    }
    catch{
        Write-Error "$_" -ErrorAction Continue
    }
}
# Function gets all DBs from source database.
function Get-DatabasesToMigrate {
    param(
        [string] $dataSource,
        [string] $sqlUserName,
        [string] $sqlPassword,
        [string] $sqlQueryToGetDbs
    )
    try{
        $sqlDbs = Invoke-SqlLCommand -dataSource $dataSource -sqlUserName $sqlUserName -sqlPassword $sqlPassword -sqlCommand $sqlQueryToGetDbs
        $sqlDbs | ForEach-Object { $_.name };
    }
    catch{
        Write-Error "$_" -ErrorAction Continue
    }
    
}