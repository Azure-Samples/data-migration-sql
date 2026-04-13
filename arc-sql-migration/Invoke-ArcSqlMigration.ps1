<#
.SYNOPSIS
    Automates database migration from Arc-enabled SQL Server to Azure SQL Managed Instance.

.DESCRIPTION
    This script provides step-by-step commands for migrating databases from an Azure Arc-enabled
    SQL Server to Azure SQL Managed Instance using either the MI Link method (via Availability Groups)
    or the Log Replay Service (LRS) method (via blob storage backups).

    Each function represents a discrete step in the migration journey and can be run independently.
    Use -Verbose on any command to enable detailed diagnostic logging.

.NOTES
    Author:  Azure Arc Data automation
    Requires: Az.Accounts PowerShell module (for authentication)
    API versions aligned with Azure Arc Portal extension (TinaExtension) as of 2025.

.EXAMPLE
    # Full MI Link migration workflow (single subscription)
    .\Invoke-ArcSqlMigration.ps1
    Connect-ArcMigration -TenantId "00000000-0000-0000-0000-000000000000"           # Step 1
    $instance = Get-ArcSqlServerInstance -ResourceId "/subscriptions/.../sqlServerInstances/myServer" # Step 2
    $databases = Get-ArcSqlDatabases -ResourceId $instance.id                          # Step 3
    $report = Get-MigrationAssessmentReport -ResourceId $instance.id                   # Step 4
    $miList = Get-ManagedInstances -SubscriptionId "00000000-..."                      # Step 5
    $mi = $miList | Where-Object { $_.name -eq "my-mi" }
    $ips = Get-ArcMachineIPAddresses -ArcMachineResourceId "..."                    # Step 6
    $validation = Invoke-MiLinkValidation -ResourceId $instance.id -ManagedInstanceId $mi.ResourceId -DatabaseNames @("db1") -SqlServerIP "10.0.0.5" # Step 7
    $link = New-MiLink -ResourceId $instance.id -ManagedInstanceId $mi.ResourceId -DatabaseNames @("db1") -SqlServerIP "10.0.0.5" -ManagedInstanceDomainName $mi.FQDN # Step 8a
    $agStatus = Get-MiLinkReplicationStatus -ResourceId $instance.id                   # Step 9a
    Invoke-MiLinkCutover -ResourceId $instance.id -AvailabilityGroupName "yourAG" -ManagedInstanceId $mi.ResourceId # Step 10a

.EXAMPLE
    # Cross-subscription workflow (source SQL in sub A, target MI in sub B)
    .\Invoke-ArcSqlMigration.ps1
    $auth = Connect-ArcMigration -TenantId "00000000-0000-0000-0000-000000000000" `
        -SubscriptionId "aaaaaaaa-source-sub" `
        -TargetSubscriptionId "bbbbbbbb-target-sub"                                    # Step 1

    $instance = Get-ArcSqlServerInstance -ResourceId "/subscriptions/aaaaaaaa-source-sub/..." # Step 2
    $databases = Get-ArcSqlDatabases -ResourceId $instance.id                          # Step 3
    $miList = Get-ManagedInstances                                                     # Step 5: auto-uses target sub
    $mi = $miList | Where-Object { $_.Name -eq "my-mi" }
#>

#Requires -Version 5.1

# ============================================================================
# CONFIGURATION & CONSTANTS
# ============================================================================

$script:ArmEndpoint = "https://management.azure.com"
$script:ArmToken = $null
$script:StorageToken = $null
$script:SourceSubscriptionId = $null
$script:TargetSubscriptionId = $null

# API Versions (aligned with portal extension)
$script:ApiVersions = @{
    ArcSqlInstance         = "2025-05-01-preview"
    ArcSqlDatabases        = "2024-05-01-preview"
    ArcSqlActions          = "2025-06-01-preview"
    ArcSqlCreateLink       = "2024-09-01-preview"
    ArcSqlAvailabilityGroups = "2025-04-01-preview"
    ArcSqlTelemetry        = "2024-05-01-preview"
    ManagedInstances       = "2023-05-01-preview"
    ManagedInstanceSku     = "2024-08-01-preview"
    ManagedInstanceDbs     = "2024-08-01-preview"
    DistributedAGs         = "2021-11-01"
    DistributedAGByName    = "2024-11-01-preview"
    DataMigrationService   = "2025-06-30"
    StorageAccounts        = "2024-01-01"
    BlobContainers         = "2024-01-01"
    RoleAssignments        = "2022-04-01"
    HybridComputeMachines  = "2024-05-20-preview"
    HybridComputeDetailed  = "2024-11-10-preview"
}

# RBAC role definition IDs for storage access
$script:StorageRoles = @{
    Contributor              = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    Owner                    = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    StorageBlobDataContrib   = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    StorageBlobDataOwner     = "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
    StorageBlobDataReader    = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-StepHeader {
    <#
    .SYNOPSIS
        Prints a formatted step header for human-readable output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StepNumber,
        [Parameter(Mandatory)][string]$Title,
        [string]$Description
    )

    $separator = "=" * 70
    Write-Host " "
    Write-Verbose "  Step ${StepNumber}:  $Title"
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan
    if ($Description) {
        Write-Host "  $Description" -ForegroundColor Gray
    }
    Write-Host " "
}

function Write-ResultTable {
    <#
    .SYNOPSIS
        Prints key-value pairs in a readable format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [string]$Title
    )

    if ($Title) {
        Write-Host "  $Title" -ForegroundColor Yellow
        Write-Host "  $('-' * $Title.Length)" -ForegroundColor Yellow
    }
    foreach ($key in $Data.Keys | Sort-Object) {
        Write-Host ("  {0,-35} : {1}" -f $key, $Data[$key]) -ForegroundColor White
    }
    Write-Host " "
}

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Sends an authenticated ARM API request with error handling and verbose logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH")]
        [string]$Method = "GET",
        [object]$Body,
        [string]$BearerToken,
        [int]$TimeoutSec = 120
    )

    if (-not $BearerToken) {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:ArmToken)
        $BearerToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    if (-not $BearerToken) {
        throw "No authentication token available. Run Connect-ArcMigration first."
    }

    # Ensure full URI
    if ($Uri -notmatch "^https?://") {
        $Uri = "$($script:ArmEndpoint)$Uri"
    }

    $headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type"  = "application/json"
    }

    $invokeParams = @{
        Uri             = $Uri
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
    }

    if ($Body) {
        $jsonBody = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
        $invokeParams["Body"] = $jsonBody
        Write-Verbose "Request body: $jsonBody"
    }

    Write-Verbose "$Method $Uri"

    try {
        $response = Invoke-WebRequest @invokeParams -ErrorAction Stop
        Write-Verbose "Response status: $($response.StatusCode)"

        $result = [PSCustomObject]@{
            StatusCode = $response.StatusCode
            Headers    = $response.Headers
            Content    = $null
        }

        if ($response.Content) {
            try {
                $result.Content = $response.Content | ConvertFrom-Json
                Write-Verbose "Response Body : $(ConvertTo-Json $result.Content -Depth 20)"
            }
            catch {
                $result.Content = $response.Content
                Write-Verbose "Response Body (raw): $($response.Content)"
            }
        }

        return $result
    }
    catch {
        $statusCode = $null
        $errorBody = $null

        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd() | ConvertFrom-Json
                $reader.Close()
            }
            catch {
                $errorBody = $_.Exception.Message
            }
        }

        Write-Error "ARM API call failed [$statusCode]: $Method $Uri"
        if ($errorBody) {
            Write-Error ($errorBody | ConvertTo-Json -Depth 5)
        }
        throw
    }
}

function Wait-AsyncOperation {
    <#
    .SYNOPSIS
        Polls a long-running ARM operation until completion.
    .DESCRIPTION
        Supports both Azure-AsyncOperation and Location header polling patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$ResponseHeaders,
        [int]$PollIntervalSeconds = 5,
        [int]$TimeoutMinutes = 30,
        [scriptblock]$OnStatusUpdate
    )

    # Determine polling URL
    $pollUrl = $null
    if ($ResponseHeaders.ContainsKey("Azure-AsyncOperation")) {
        $pollUrl = $ResponseHeaders["Azure-AsyncOperation"]
        if ($pollUrl -is [array]) { $pollUrl = $pollUrl[0] }
        Write-Verbose "Polling via Azure-AsyncOperation header"
    }
    elseif ($ResponseHeaders.ContainsKey("Location")) {
        $pollUrl = $ResponseHeaders["Location"]
        if ($pollUrl -is [array]) { $pollUrl = $pollUrl[0] }
        Write-Verbose "Polling via Location header"
    }
    else {
        Write-Warning "No async operation header found. The operation may have completed synchronously."
        return $null
    }

    Write-Verbose "Poll URL: $pollUrl"

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $attempt = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        Start-Sleep -Seconds $PollIntervalSeconds

        try {
            $pollResponse = Invoke-ArmRequest -Uri $pollUrl -Method GET
            $status = $pollResponse.Content.status

            if (-not $status -and $pollResponse.Content.properties) {
                $status = $pollResponse.Content.properties.provisioningState
            }

            Write-Verbose "Poll attempt $attempt - Status: $status"

            if ($OnStatusUpdate) {
                & $OnStatusUpdate $status $pollResponse.Content
            }

            switch ($status) {
                "Succeeded" {
                    Write-Host "  Operation completed successfully." -ForegroundColor Green
                    return $pollResponse.Content
                }
                "Failed" {
                    $errorMsg = "Operation failed."
                    if ($pollResponse.Content.error) {
                        $errorMsg = $pollResponse.Content.error.message
                    }
                    throw "Async operation failed: $errorMsg"
                }
                "Canceled" {
                    throw "Async operation was canceled."
                }
            }
        }
        catch {
            if ($_.Exception.Message -match "Async operation (failed|canceled)") {
                throw
            }
            Write-Verbose "Poll attempt $attempt failed: $($_.Exception.Message). Retrying..."
        }
    }

    throw "Operation timed out after $TimeoutMinutes minutes."
}

function Format-ResourceIdParts {
    <#
    .SYNOPSIS
        Parses an ARM resource ID into its component parts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId
    )

    $parts = @{}
    $segments = $ResourceId.Trim("/").Split("/")

    for ($i = 0; $i -lt $segments.Count - 1; $i += 2) {
        $parts[$segments[$i]] = $segments[$i + 1]
    }

    return [PSCustomObject]@{
        SubscriptionId = $parts["subscriptions"]
        ResourceGroup  = $parts["resourceGroups"]
        Provider       = if ($parts.ContainsKey("providers")) { $parts["providers"] } else { $null }
        FullId         = $ResourceId
        Segments       = $parts
    }
}

# ============================================================================
# STEP 1: AUTHENTICATION
# ============================================================================

function Connect-ArcMigration {
    <#
    .SYNOPSIS
        Authenticates to Azure and caches the ARM bearer token for subsequent API calls.

    .DESCRIPTION
        Uses the Az.Accounts module to sign in interactively (or via service principal)
        and obtains an access token for the ARM management endpoint.

        The ARM token is tenant-scoped, so it works across all subscriptions within
        the same Azure AD tenant. When the target Managed Instance is in a different
        subscription than the source Arc SQL Server, specify -TargetSubscriptionId
        so that subsequent commands (Get-ManagedInstances, Get-StorageAccounts,
        New-DmsResource) default to the correct target subscription.

    .PARAMETER TenantId
        Azure AD tenant ID. If omitted, uses the default tenant.

    .PARAMETER SubscriptionId
        Source subscription (where the Arc SQL Server resides). Sets the default
        Azure context. If omitted, uses the current default.

    .PARAMETER TargetSubscriptionId
        Target subscription (where the Managed Instance resides). Used as the
        default for target-side commands. If omitted, defaults to the same value
        as SubscriptionId (single-subscription workflow).

    .PARAMETER UseDeviceCode
        Use device code flow for authentication (useful for headless environments).

    .EXAMPLE
        # Single subscription (source and target in same subscription)
        Connect-ArcMigration -TenantId "00000000-0000-0000-0000-000000000000"

    .EXAMPLE
        # Cross-subscription (source Arc SQL in sub A, target MI in sub B)
        Connect-ArcMigration -TenantId "00000000-0000-0000-0000-000000000000" `
            -SubscriptionId "aaaaaaaa-source-sub" `
            -TargetSubscriptionId "bbbbbbbb-target-sub"
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$SubscriptionId,
        [string]$TargetSubscriptionId,
        [switch]$UseDeviceCode
    )

    Write-StepHeader -StepNumber "1" -Title "Authenticate to Azure" `
        -Description "Sign in and obtain ARM access token for migration operations."

    # Check for Az.Accounts module
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Error "Az.Accounts module is required. Install with: Install-Module Az.Accounts -Force"
        throw "Missing required module: Az.Accounts"
    }

    Write-Verbose "Importing Az.Accounts module..."
    Import-Module Az.Accounts -ErrorAction Stop

    # Build login parameters
    $loginParams = @{}
    if ($TenantId) { $loginParams["TenantId"] = $TenantId }
    if ($SubscriptionId) { $loginParams["SubscriptionId"] = $SubscriptionId }
    if ($UseDeviceCode) { $loginParams["UseDeviceAuthentication"] = $true }

    Write-Host "  Signing in to Azure..." -ForegroundColor White
    $context = Connect-AzAccount @loginParams -ErrorAction Stop
    Write-Verbose "Signed in as: $($context.Context.Account.Id)"

    if (($SubscriptionId) -and ($TenantId)) {
        Set-AzContext -SubscriptionId $SubscriptionId  -TenantId $TenantId -ErrorAction Stop | Out-Null
        Write-Verbose "Set subscription context to: $SubscriptionId"
    }

    # Get ARM token
    Write-Verbose "Acquiring ARM access token..."
    $tokenResult = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -ErrorAction Stop
    $script:ArmToken = $tokenResult.Token

    # Get Storage token (for LRS blob folder listing)
    Write-Verbose "Acquiring Azure Storage access token..."
    try {
        $storageTokenResult = Get-AzAccessToken -ResourceUrl "https://storage.azure.com" -ErrorAction Stop
        $script:StorageToken = $storageTokenResult.Token
        Write-Verbose "Storage token acquired."
    }
    catch {
        Write-Verbose "Storage token not available (not needed for MI Link method): $($_.Exception.Message)"
    }

    $ctx = Get-AzContext
    $script:SourceSubscriptionId = $ctx.Subscription.Id

    # Resolve target subscription
    if ($TargetSubscriptionId) {
        $script:TargetSubscriptionId = $TargetSubscriptionId
    }
    else {
        $script:TargetSubscriptionId = $ctx.Subscription.Id
    }

    $isCrossSub = $script:SourceSubscriptionId -ne $script:TargetSubscriptionId

    Write-Host " "
    $authData = [ordered]@{
        "Account"             = $ctx.Account.Id
        "Tenant"              = $ctx.Tenant.Id
        "Source Subscription"  = "$($ctx.Subscription.Name) ($($ctx.Subscription.Id))"
    }
    if ($isCrossSub) {
        $authData["Target Subscription"] = $script:TargetSubscriptionId
        $authData["Cross-Subscription"]  = "Yes (ARM token is tenant-scoped)"
    }
    else {
        $authData["Target Subscription"] = "(same as source)"
    }
    $authData["Environment"] = $ctx.Environment.Name

    Write-ResultTable -Title "Authentication Successful" -Data $authData

    Write-Host "  You are now authenticated. All subsequent commands will use these credentials." -ForegroundColor Green
    if ($isCrossSub) {
        Write-Host "  Cross-subscription mode: source and target are in different subscriptions." -ForegroundColor Yellow
        Write-Host "  Target-side commands will default to subscription: $($script:TargetSubscriptionId)" -ForegroundColor Yellow
    }
    Write-Host " "

    return [PSCustomObject]@{
        AccountId            = $ctx.Account.Id
        TenantId             = $ctx.Tenant.Id
        SubscriptionId       = $ctx.Subscription.Id
        SubscriptionName     = $ctx.Subscription.Name
        TargetSubscriptionId = $script:TargetSubscriptionId
    }
}

# ============================================================================
# STEP 2: GET SQL SERVER INSTANCE
# ============================================================================

function Get-ArcSqlServerInstance {
    <#
    .SYNOPSIS
        Retrieves Arc-enabled SQL Server instance details.

    .DESCRIPTION
        Fetches the SQL Server instance metadata from Azure Arc, including
        assessment upload status, version, edition, and licensing info.

    .PARAMETER ResourceId
        Full ARM resource ID of the Arc SQL Server instance.
        Example: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.AzureArcData/sqlServerInstances/{name}

    .EXAMPLE
        $instance = Get-ArcSqlServerInstance -ResourceId "/subscriptions/.../sqlServerInstances/myServer"
        $instance | Format-List
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId
    )

    Write-StepHeader -StepNumber "2" -Title "Get SQL Server Instance" `
        -Description "Retrieve Arc-enabled SQL Server instance metadata."

    $uri = "$ResourceId`?api-version=$($script:ApiVersions.ArcSqlInstance)"
    Write-Verbose "Fetching SQL Server instance: $ResourceId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $instance = $response.Content
    $props = $instance.properties

    Write-ResultTable -Title "SQL Server Instance Details" -Data ([ordered]@{
        "Name"               = $instance.name
        "Location"           = $instance.location
        "Resource ID"        = $instance.id
        "Version"            = $props.version
        "Edition"            = $props.edition
        "Patch Level"        = $props.patchLevel
        "Container Type"     = $props.containerResourceId
        "Status"             = $props.status
        "License Type"       = $props.licenseType
        "TCP Enabled"        = $props.tcpStaticPorts
        "Assessment Upload"  = $props.lastDatabaseUploadTime
    })

    return $instance
}

# ============================================================================
# STEP 3: GET DATABASES
# ============================================================================

function Get-ArcSqlDatabases {
    <#
    .SYNOPSIS
        Lists databases on the Arc-enabled SQL Server instance.

    .DESCRIPTION
        Retrieves all user databases (system databases are excluded).
        Shows database name, size, state, and last backup/upload time.

    .PARAMETER ResourceId
        Full ARM resource ID of the Arc SQL Server instance.

    .PARAMETER IncludeSystemDatabases
        Include system databases in the output.

    .EXAMPLE
        $databases = Get-ArcSqlDatabases -ResourceId $instance.id
        $databases | Format-Table Name, SizeMB, State
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [switch]$IncludeSystemDatabases
    )

    Write-StepHeader -StepNumber "3" -Title "List Databases" `
        -Description "Retrieve databases available for migration."

    $uri = "$ResourceId/databases?api-version=$($script:ApiVersions.ArcSqlDatabases)"
    Write-Verbose "Fetching databases for: $ResourceId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $databases = $response.Content.value

    # Filter system databases
    $systemDbs = @("master", "model", "msdb", "tempdb")
    if (-not $IncludeSystemDatabases) {
        $databases = $databases | Where-Object { $_.name -notin $systemDbs }
        Write-Verbose "Filtered out system databases. Remaining: $($databases.Count)"
    }

    # Format output
    $results = $databases | ForEach-Object {
        [PSCustomObject]@{
            Name           = $_.name
            ResourceId     = $_.id
            State          = $_.properties.state
            SizeMB         = $_.properties.sizeMB
            CreationDate   = $_.properties.databaseCreationDate
            LastUploadTime = $_.properties.lastDatabaseUploadTime
        }
    }

    Write-Host "  Found $($results.Count) user database(s):" -ForegroundColor White
    Write-Host " "
    $results | Format-Table -Property Name, State, SizeMB, CreationDate -AutoSize | Out-String | Write-Host

    return $results
}

# ============================================================================
# STEP 4: FETCH MIGRATION ASSESSMENT REPORT
# ============================================================================

function Get-MigrationAssessmentReport {
    <#
    .SYNOPSIS
        Fetches the full migration assessment report from the Arc-enabled SQL Server.

    .DESCRIPTION
        Calls the getTelemetry API with the MigrationAssessments dataset to retrieve
        the suitability report and SKU recommendation reports for all Azure SQL targets
        (Managed Instance, SQL Database, SQL VM).

        The suitability report includes per-database readiness, blocker issues, and
        warnings for each target platform. The SKU recommendation reports provide
        right-sized target SKU suggestions with cost estimates.

        This API uses the Azure-AsyncOperation polling pattern. The response data
        may be gzip-compressed (Base64-encoded); the function handles decompression
        automatically.

    .PARAMETER ResourceId
        Full ARM resource ID of the Arc SQL Server instance.

    .PARAMETER Target
        Filter results to a specific Azure SQL target platform.
        Valid values: All, AzureSqlMI, AzureSqlDB, AzureSqlVM.
        Default: All.

    .EXAMPLE
        $report = Get-MigrationAssessmentReport -ResourceId $instance.id
        $report.SuitabilityReport.Servers[0].TargetReadinesses

    .EXAMPLE
        $report = Get-MigrationAssessmentReport -ResourceId $instance.id -Target AzureSqlMI
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [ValidateSet("All", "AzureSqlMI", "AzureSqlDB", "AzureSqlVM")]
        [string]$Target = "All"
    )

    Write-StepHeader -StepNumber "4" -Title "Migration Assessment Report" `
        -Description "Fetch suitability and SKU recommendation reports for migration readiness."

    # The assessment uses the dedicated assessment API version (same as portal)
    $assessmentApiVersion = "2025-05-01-preview"

    $body = @{
        datasetName = "MigrationAssessments"
    }

    $uri = "$ResourceId/getTelemetry?api-version=$assessmentApiVersion"
    Write-Verbose "Fetching migration assessment via getTelemetry (datasetName=MigrationAssessments)..."
    Write-Host "  Requesting assessment data..." -ForegroundColor White

    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    # Poll the Azure-AsyncOperation header
    $result = $null
    if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("azure-asyncoperation"))) {
        $asyncUrl = $response.Headers["Azure-AsyncOperation"]
        if (-not $asyncUrl) { $asyncUrl = $response.Headers["azure-asyncoperation"] }
        if ($asyncUrl -is [array]) { $asyncUrl = $asyncUrl[0] }

        Write-Verbose "Polling async operation: $asyncUrl"
        $deadline = (Get-Date).AddSeconds(30)
        $attempt = 0

        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $attempt++

            try {
                $pollResponse = Invoke-ArmRequest -Uri $asyncUrl -Method GET
                $status = $pollResponse.Content.status
                Write-Verbose "Poll attempt $attempt - Status: $status"

                if ($status -eq "Succeeded") {
                    $result = $pollResponse.Content
                    break
                }
                elseif ($status -eq "Failed") {
                    throw "Assessment telemetry request failed: $($pollResponse.Content.error.message)"
                }
            }
            catch {
                if ($_.Exception.Message -match "Assessment telemetry request failed") { throw }
                Write-Verbose "Poll attempt $attempt error: $($_.Exception.Message)"
            }
        }

        if (-not $result) {
            Write-Warning "Assessment telemetry polling timed out after 30 seconds."
            return $null
        }
    }
    else {
        $result = $response.Content
    }

    # Parse the columnar response
    # Columns typically: Type, Body (or CompressedBody), ObservedTimestampUTC
    $columns = $result.properties.columns
    $rows = $result.properties.rows

    if (-not $columns -or -not $rows) {
        Write-Warning "No assessment data available. Ensure the Arc SQL Server extension has completed an assessment run."
        return $null
    }

    # Build column index map
    $colMap = @{}
    for ($i = 0; $i -lt $columns.Count; $i++) {
        $colMap[$columns[$i].name] = $i
    }
    Write-Verbose "Response columns: $($columns | ForEach-Object { $_.name })"

    # Determine body column (CompressedBody vs Body)
    $bodyCol = if ($colMap.ContainsKey("CompressedBody")) { "CompressedBody" } else { "Body" }
    $isCompressed = ($bodyCol -eq "CompressedBody")
    $typeIdx = $colMap["Type"]
    $bodyIdx = $colMap[$bodyCol]
    $tsIdx = if ($colMap.ContainsKey("ObservedTimestampUTC")) { $colMap["ObservedTimestampUTC"] } else { $null }

    Write-Verbose "Body column: $bodyCol (compressed=$isCompressed), rows: $($rows.Count)"

    # Helper to decompress gzip+base64 data
    $decompressBlock = {
        param([string]$encoded)
        try {
            $bytes = [Convert]::FromBase64String($encoded)
            $ms = [System.IO.MemoryStream]::new($bytes)
            $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $sr = [System.IO.StreamReader]::new($gz)
            $text = $sr.ReadToEnd()
            $sr.Close(); $gz.Close(); $ms.Close()
            return $text
        }
        catch {
            Write-Verbose "Decompression failed, treating as plain text."
            return $encoded
        }
    }

    # Extract a report by type name
    $extractReport = {
        param([string]$typeName)
        $row = $rows | Where-Object { $_[$typeIdx] -eq $typeName } | Select-Object -First 1
        if (-not $row) { return $null }

        $rawBody = $row[$bodyIdx]
        if (-not $rawBody) { return $null }

        # Handle NaN values (portal does this too)
        $rawBody = $rawBody -replace '\bNaN\b', 'null'

        if ($isCompressed) {
            $rawBody = & $decompressBlock $rawBody
            $rawBody = $rawBody -replace '\bNaN\b', 'null'
        }

        $timestamp = if ($null -ne $tsIdx) { $row[$tsIdx] } else { $null }

        try {
            return [PSCustomObject]@{
                Report    = $rawBody | ConvertFrom-Json
                Timestamp = $timestamp
            }
        }
        catch {
            Write-Warning "Failed to parse $typeName report JSON."
            return $null
        }
    }

    # Extract all reports (try V2 compressed versions first, fall back to V1)
    Write-Verbose "Extracting suitability report..."
    $suitV2 = & $extractReport "Suitability_V2"
    $suitV1 = & $extractReport "Suitability"
    $suitability = if ($suitV2 -and $suitV2.Report) { $suitV2 } elseif ($suitV1 -and $suitV1.Report) { $suitV1 } else { $null }

    $suitability | ConvertTo-Json -Depth 20 | Out-String | Write-Verbose

    Write-Verbose "Extracting SKU recommendation reports..."
    $skuMI_V2 = & $extractReport "SKURecommendation_AzureSQLMI_V2"
    $skuMI_V1 = & $extractReport "SKURecommendation_AzureSQLMI"
    $skuMI = if ($skuMI_V2 -and $skuMI_V2.Report) { $skuMI_V2 } elseif ($skuMI_V1 -and $skuMI_V1.Report) { $skuMI_V1 } else { $null }

    $skuMI | ConvertTo-Json -Depth 20 | Out-String | Write-Verbose

    $skuDB_V2 = & $extractReport "SKURecommendation_AzureSQLDB_V2"
    $skuDB_V1 = & $extractReport "SKURecommendation_AzureSQLDB"
    $skuDB = if ($skuDB_V2 -and $skuDB_V2.Report) { $skuDB_V2 } elseif ($skuDB_V1 -and $skuDB_V1.Report) { $skuDB_V1 } else { $null }

    $skuDB | ConvertTo-Json -Depth 20 | Out-String | Write-Verbose

    $skuVM_V2 = & $extractReport "SKURecommendation_AzureSQLVM_V2"
    $skuVM_V1 = & $extractReport "SKURecommendation_AzureSQLVM"
    $skuVM = if ($skuVM_V2 -and $skuVM_V2.Report) { $skuVM_V2 } elseif ($skuVM_V1 -and $skuVM_V1.Report) { $skuVM_V1 } else { $null }

    $skuVM | ConvertTo-Json -Depth 20 | Out-String | Write-Verbose

    # Build result object
    $reportResult = [PSCustomObject]@{
        SuitabilityReport            = if ($suitability) { $suitability.Report } else { $null }
        SuitabilityTimestamp         = if ($suitability) { $suitability.Timestamp } else { $null }
        SkuRecommendation_AzureSqlMI = if ($skuMI) { $skuMI.Report } else { $null }
        SkuRecommendation_AzureSqlDB = if ($skuDB) { $skuDB.Report } else { $null }
        SkuRecommendation_AzureSqlVM = if ($skuVM) { $skuVM.Report } else { $null }
        AssessmentExists             = ($null -ne $suitability)
    }

    # Display summary
    if (-not $reportResult.AssessmentExists) {
        Write-Warning "No assessment data found. Ensure the SQL Server extension has run at least one migration assessment."
        Write-Warning "Assessment can be triggered from the Azure portal under Migration > Assessment settings."
        return $reportResult
    }

    $suit = $reportResult.SuitabilityReport
    $serverProps = $suit.Servers[0].Properties

    Write-Host " "
    Write-ResultTable -Title "Source SQL Server" -Data ([ordered]@{
        "Server Name"     = $serverProps.ServerName
        "Version"         = $serverProps.ServerVersion
        "Edition"         = $serverProps.ServerEdition
        "Platform"        = $serverProps.ServerHostPlatform
        "vCores"          = "$($serverProps.LogicalCpuCount) logical / $($serverProps.PhysicalCpuCount) physical"
        "Memory In Use"   = "$([math]::Round($serverProps.MaxServerMemoryInUse / 1024, 1)) GB"
        "User Databases"  = $serverProps.NumberOfUserDatabases
        "Total DB Size"   = "$([math]::Round($serverProps.SumOfUserDatabasesSize / 1024, 1)) GB"
        "Assessment Date" = $reportResult.SuitabilityTimestamp
    })

    # Target readiness summary
    $targetReadiness = $suit.Servers[0].TargetReadinesses

    $showTarget = {
        param([string]$Label, $readiness, $skuReport, [string]$targetKey)

        if (-not $readiness) { return }

        Write-Verbose "Readiness : "
        $readiness | ConvertTo-Json -Depth 20 | Out-String | Write-Verbose

        $color = if ($readiness.RecommendationStatus -eq "NotReady") { "Red" }
                 elseif ($readiness.RecommendationStatus -eq "Ready") { "Green" }
                 else { "Yellow" }

        Write-Host "  $Label" -ForegroundColor $color
        if ($readiness.DatabasesListReadyForMigration -and $readiness.DatabasesListReadyForMigration.Count -gt 0) {
            Write-Host ("    Ready: {0}/{1} databases  |  Blockers: {2}  |  Status: {3}" -f `
                ($readiness.DatabasesListReadyForMigration).Count,
                $readiness.TotalNumberOfDatabases,
                $readiness.NumberOfServerBlockerIssues,
                $readiness.RecommendationStatus) -ForegroundColor $color

            Write-Host "    Ready DBs: $($readiness.DatabasesListReadyForMigration -join ', ')" -ForegroundColor Gray
        }else{
            Write-Host ("    Total: {0} databases  |  Blockers: {1}  |  Status: {2}" -f `
                $readiness.TotalNumberOfDatabases,
                $readiness.NumberOfServerBlockerIssues,
                $readiness.RecommendationStatus) -ForegroundColor $color


        }

        # Show SKU recommendation if available
        if ($skuReport -and $skuReport.SkuRecommendationForServers) {
            $skuResults = $skuReport.SkuRecommendationForServers | Select-Object -First 1
            if ($skuResults.SkuRecommendationResults -and $skuResults.SkuRecommendationResults.Count -gt 0) {
                $topSku = $skuResults.SkuRecommendationResults | Sort-Object { $_.Ranking } | Select-Object -First 1
                $skuCat = $topSku.TargetSku.Category
                $cost = $topSku.MonthlyCost
                Write-Host ("    Recommended SKU: {0} {1} ({2} vCores)  |  Est. cost: `${3:N0}/mo" -f `
                    $skuCat.SqlPurchasingModel, $skuCat.SqlServiceTier, $topSku.TargetSku.ComputeSize, $cost.TotalCost) -ForegroundColor Cyan
            }
        }
        Write-Host " "
    }

    Write-Host " "
    Write-Host "  Target Readiness Summary" -ForegroundColor Yellow
    Write-Host "  $('-' * 50)" -ForegroundColor Yellow

    if ($Target -eq "All" -or $Target -eq "AzureSqlMI") {
        & $showTarget "Azure SQL Managed Instance" $targetReadiness.AzureSqlManagedInstance $reportResult.SkuRecommendation_AzureSqlMI "AzureSqlMI"
    }
    if ($Target -eq "All" -or $Target -eq "AzureSqlDB") {
        & $showTarget "Azure SQL Database" $targetReadiness.AzureSqlDatabase $reportResult.SkuRecommendation_AzureSqlDB "AzureSqlDB"
    }
    if ($Target -eq "All" -or $Target -eq "AzureSqlVM") {
        $vmreadiness = [PSCustomObject]@{
            RecommendationStatus = "Ready"
            TotalNumberOfDatabases = $targetReadiness.AzureSqlDatabase.TotalNumberOfDatabases
        }    
        & $showTarget "SQL Server on Azure VM" $vmreadiness $reportResult.SkuRecommendation_AzureSqlVM "AzureSqlVM"
    }

    # Per-database detail
    $databases = $suit.Servers[0].Databases
    if ($databases -and $databases.Count -gt 0) {
        Write-Host "  Per-Database Assessment (Azure SQL MI readiness)" -ForegroundColor Yellow
        Write-Host "  $('-' * 50)" -ForegroundColor Yellow

        foreach ($db in $databases) {
            $dbName = $db.Properties.Name
            $miReady = $db.TargetReadinesses.AzureSqlManagedInstance
            $state = $miReady.RecommendationStatus
            $blockers = $miReady.NumOfBlockerIssues

            $color = switch ($state) {
                "Ready"    { "Green" }
                "NotReady" { "Red" }
                default    { "Yellow" }
            }

            $sizeMB = $db.Properties.SizeMB
            $sizeDisplay = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 1)) GB" } else { "$sizeMB MB" }

            Write-Host ("  [{0,-9}] {1,-30} Size: {2,-10} Blockers: {3}" -f $state, $dbName, $sizeDisplay, $blockers) -ForegroundColor $color

            # Show issues/warnings for this DB
            if ($db.DatabaseAssessments -and $db.DatabaseAssessments.Count -gt 0) {
                $miIssues = $db.DatabaseAssessments | Where-Object {
                    $_.AppliesToMigrationTargetPlatform -eq "AzureSqlManagedInstance"
                }
                foreach ($issue in $miIssues) {
                    $issueColor = if ($issue.IssueCategory -eq "Issue") { "Red" } else { "DarkYellow" }
                    Write-Host "    [$($issue.IssueCategory)] $($issue.FeatureId)" -ForegroundColor $issueColor
                    if ($issue.MoreInformation) {
                        Write-Host "      $($issue.MoreInformation)" -ForegroundColor Gray
                    }
                }
            }

        }
        Write-Host " "

        Write-Host "  Per-Database Assessment (Azure SQL DB readiness)" -ForegroundColor Yellow
        Write-Host "  $('-' * 50)" -ForegroundColor Yellow

        foreach ($db in $databases) {
            $dbName = $db.Properties.Name
            $miReady = $db.TargetReadinesses.AzureSqlDatabase
            $state = $miReady.RecommendationStatus
            $blockers = $miReady.NumOfBlockerIssues

            $color = switch ($state) {
                "Ready"    { "Green" }
                "NotReady" { "Red" }
                default    { "Yellow" }
            }

            $sizeMB = $db.Properties.SizeMB
            $sizeDisplay = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 1)) GB" } else { "$sizeMB MB" }

            Write-Host ("  [{0,-9}] {1,-30} Size: {2,-10} Blockers: {3}" -f $state, $dbName, $sizeDisplay, $blockers) -ForegroundColor $color

            # Show issues/warnings for this DB
            if ($db.DatabaseAssessments -and $db.DatabaseAssessments.Count -gt 0) {
                $miIssues = $db.DatabaseAssessments | Where-Object {
                    $_.AppliesToMigrationTargetPlatform -eq "AzureSqlManagedInstance"
                }
                foreach ($issue in $miIssues) {
                    $issueColor = if ($issue.IssueCategory -eq "Issue") { "Red" } else { "DarkYellow" }
                    Write-Host "    [$($issue.IssueCategory)] $($issue.FeatureId)" -ForegroundColor $issueColor
                    if ($issue.MoreInformation) {
                        Write-Host "      $($issue.MoreInformation)" -ForegroundColor Gray
                    }
                }
            }
        
        }
        Write-Host " "

        Write-Host "  Per-Database Assessment (Azure SQL VM readiness)" -ForegroundColor Yellow
        Write-Host "  $('-' * 50)" -ForegroundColor Yellow

        foreach ($db in $databases) {
            $dbName = $db.Properties.Name
            $miReady = $db.TargetReadinesses.AzureSqlManagedInstance
            $state = "Ready"
            $blockers = 0

            $color = switch ($state) {
                "Ready"    { "Green" }
                "NotReady" { "Red" }
                default    { "Yellow" }
            }

            $sizeMB = $db.Properties.SizeMB
            $sizeDisplay = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 1)) GB" } else { "$sizeMB MB" }

            Write-Host ("  [{0,-9}] {1,-30} Size: {2,-10} Blockers: {3}" -f $state, $dbName, $sizeDisplay, $blockers) -ForegroundColor $color

            # Show issues/warnings for this DB
            if ($db.DatabaseAssessments -and $db.DatabaseAssessments.Count -gt 0) {
                $miIssues = $db.DatabaseAssessments | Where-Object {
                    $_.AppliesToMigrationTargetPlatform -eq "AzureSqlManagedInstance"
                }
                foreach ($issue in $miIssues) {
                    $issueColor = if ($issue.IssueCategory -eq "Issue") { "Red" } else { "DarkYellow" }
                    Write-Host "    [$($issue.IssueCategory)] $($issue.FeatureId)" -ForegroundColor $issueColor
                    if ($issue.MoreInformation) {
                        Write-Host "      $($issue.MoreInformation)" -ForegroundColor Gray
                    }
                }
            }
        }
        Write-Host " "
    }

    return $reportResult
}

# ============================================================================
# STEP 5: LIST MANAGED INSTANCES (TARGET)
# ============================================================================

function Get-ManagedInstances {
    <#
    .SYNOPSIS
        Lists Azure SQL Managed Instances in a subscription.

    .DESCRIPTION
        Retrieves all SQL Managed Instances, showing name, location, SKU,
        and domain name (FQDN). Use this to select the migration target.

        Defaults to the target subscription set in Connect-ArcMigration
        (-TargetSubscriptionId). Override by passing -SubscriptionId explicitly.

    .PARAMETER SubscriptionId
        Azure subscription ID to search for managed instances.
        Defaults to the target subscription from Connect-ArcMigration.

    .EXAMPLE
        $miList = Get-ManagedInstances -SubscriptionId "00000000-..."
        $mi = $miList | Out-GridView -PassThru -Title "Select target MI"

    .EXAMPLE
        # Uses the TargetSubscriptionId set during Connect-ArcMigration
        $miList = Get-ManagedInstances
    #>
    [CmdletBinding()]
    param(
        [string]$SubscriptionId = $script:TargetSubscriptionId
    )

    if (-not $SubscriptionId) {
        throw "SubscriptionId is required. Pass -SubscriptionId or set -TargetSubscriptionId in Connect-ArcMigration."
    }

    Write-StepHeader -StepNumber "5" -Title "List Managed Instances" `
        -Description "Find target Azure SQL Managed Instances for migration."

    $uri = "/subscriptions/$SubscriptionId/providers/Microsoft.Sql/managedInstances?api-version=$($script:ApiVersions.ManagedInstances)"
    Write-Verbose "Listing managed instances in subscription: $SubscriptionId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $instances = $response.Content.value

    if (-not $instances -or $instances.Count -eq 0) {
        Write-Warning "No SQL Managed Instances found in subscription $SubscriptionId."
        return @()
    }

    $results = $instances | ForEach-Object {
        [PSCustomObject]@{
            Name         = $_.name
            ResourceId   = $_.id
            Location     = $_.location
            State        = $_.properties.state
            FQDN         = $_.properties.fullyQualifiedDomainName
            SkuName      = $_.sku.name
            SkuTier      = $_.sku.tier
            VCores       = $_.sku.capacity
            StorageGB    = [math]::Round($_.properties.storageSizeInGB, 0)
            AdminLogin   = $_.properties.administratorLogin
        }
    }

    Write-Host "  Found $($results.Count) managed instance(s):" -ForegroundColor White
    Write-Host " "
    $results | Format-Table -Property Name, Location, State, SkuTier, VCores, StorageGB, FQDN -AutoSize | Out-String | Write-Verbose

    return $results
}

function Get-ManagedInstanceSku {
    <#
    .SYNOPSIS
        Gets the SKU details of a specific managed instance.

    .PARAMETER ManagedInstanceId
        Full ARM resource ID of the managed instance.

    .EXAMPLE
        $sku = Get-ManagedInstanceSku -ManagedInstanceId $mi.ResourceId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManagedInstanceId
    )

    Write-Verbose "Fetching MI SKU for: $ManagedInstanceId"

    $uri = "$ManagedInstanceId`?api-version=$($script:ApiVersions.ManagedInstanceSku)"
    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $mi = $response.Content

    $result = [PSCustomObject]@{
        Name         = $mi.name
        SkuName      = $mi.sku.name
        SkuTier      = $mi.sku.tier
        SkuFamily    = $mi.sku.family
        VCores       = $mi.sku.capacity
        StorageGB    = $mi.properties.storageSizeInGB
        FQDN         = $mi.properties.fullyQualifiedDomainName
        DomainName   = $mi.properties.fullyQualifiedDomainName
        PrincipalId  = $mi.identity.principalId
    }

    Write-ResultTable -Title "Managed Instance SKU" -Data ([ordered]@{
        "Name"       = $result.Name
        "SKU"        = "$($result.SkuTier) / $($result.SkuName) / $($result.SkuFamily)"
        "vCores"     = $result.VCores
        "Storage GB" = $result.StorageGB
        "FQDN"       = $result.FQDN
    })

    return $result
}

function Get-ManagedInstanceDatabases {
    <#
    .SYNOPSIS
        Lists databases on the target managed instance (for conflict detection).

    .PARAMETER ManagedInstanceId
        Full ARM resource ID of the managed instance.

    .EXAMPLE
        $miDbs = Get-ManagedInstanceDatabases -ManagedInstanceId $mi.ResourceId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManagedInstanceId
    )

    Write-Verbose "Fetching databases on MI: $ManagedInstanceId"

    $uri = "$ManagedInstanceId/databases?api-version=$($script:ApiVersions.ManagedInstanceDbs)"
    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $databases = $response.Content.value | ForEach-Object {
        [PSCustomObject]@{
            Name   = $_.name
            Status = $_.properties.status
            Id     = $_.id
        }
    }

    if ($databases.Count -gt 0) {
        Write-Host "  Existing databases on target MI:" -ForegroundColor Yellow
        $databases | Format-Table -Property Name, Status -AutoSize | Out-String | Write-Verbose
    }
    else {
        Write-Host "  No existing databases on target MI." -ForegroundColor Green
    }

    return $databases
}

# ============================================================================
# STEP 6: GET IP ADDRESSES (MI LINK METHOD)
# ============================================================================

function Get-ArcMachineIPAddresses {
    <#
    .SYNOPSIS
        Retrieves IP addresses from the Arc-connected machine.

    .DESCRIPTION
        Gets the network interface IP addresses from the Azure Arc Hybrid Compute
        machine resource. One IP is used as the listener URL for MI Link.

    .PARAMETER ArcMachineResourceId
        Full ARM resource ID of the Arc machine (Microsoft.HybridCompute/machines).

    .EXAMPLE
        $ips = Get-ArcMachineIPAddresses -ArcMachineResourceId "/subscriptions/.../machines/myMachine"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArcMachineResourceId
    )

    Write-StepHeader -StepNumber "6" -Title "Get IP Addresses" `
        -Description "Retrieve IP addresses from the Arc machine for MI Link listener."

    $uri = "$ArcMachineResourceId`?api-version=$($script:ApiVersions.HybridComputeMachines)"
    Write-Verbose "Fetching Arc machine details: $ArcMachineResourceId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $machine = $response.Content
    $ips = @()

    if ($machine.properties.networkProfile -and $machine.properties.networkProfile.networkInterfaces) {
        foreach ($nic in $machine.properties.networkProfile.networkInterfaces) {
            if ($nic.ipAddresses) {
                foreach ($ip in $nic.ipAddresses) {
                    $ips += [PSCustomObject]@{
                        Address    = $ip.address
                        Version    = $ip.ipAddressVersion
                        SubnetMask = $ip.subnet.addressPrefix
                    }
                }
            }
        }
    }

    if ($ips.Count -eq 0) {
        Write-Warning "No IP addresses found on Arc machine. You may need to specify the SQL Server IP manually."
    }
    else {
        Write-Host "  IP addresses found on Arc machine:" -ForegroundColor White
        $ips | Format-Table -Property Address, Version -AutoSize | Out-String | Write-Host
    }

    return $ips
}

# ============================================================================
# STEP 7: VALIDATE DATABASES (MI LINK METHOD)
# ============================================================================

function Invoke-MiLinkValidation {
    <#
    .SYNOPSIS
        Runs MI Link assessment validations on selected databases.

    .DESCRIPTION
        Performs database-level and network-level validation checks to determine
        if selected databases are ready for MI Link migration. Polls the
        long-running operation until complete.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID.

    .PARAMETER ManagedInstanceId
        Target managed instance ARM resource ID.

    .PARAMETER DatabaseNames
        Array of database names to validate.

    .PARAMETER SqlServerIP
        IP address of the SQL Server (from Get-ArcMachineIPAddresses).

    .PARAMETER AvailabilityGroupName
        Optional AG name. Auto-generated if not specified.

    .PARAMETER DistributedAvailabilityGroupName
        Optional DAG name. Auto-generated if not specified.

    .PARAMETER AssessmentCategories
        Array of assessment categories to run. Defaults to all.
            SqlInstance : Assessments of the given instance on the on-premise SQL Server (box).
            SqlInstanceDatabase : Assessments of the database(s) on the given instance on the on-premise SQL Server (box).
            ManagedInstance : Assessments of the Managed Instance.
            ManagedInstanceDatabase : Assessments of the database(s) on the Managed Instance.
            ManagedInstanceCrossValidation : Assessments that use data from both the Managed Instance and the given instance of the on-premise SQL Server (box) for the validations.
            Certificates : Assessments of the necessary certificates configuration.
            BoxToMiNetworkConnectivity : Assessment of network connectivity from the on-premise SQL Server (box) to the Managed Instance.
            MiToBoxNetworkConnectivity : Assessments of network connectivity from the Managed Instance to the on-premise SQL Server (box).
            DagCrossValidation : Assessments of the chosen Distributed Availability Group.
            SqlInstanceAg : Assessments of the chosen Availability Group.


    .EXAMPLE
        $validation = Invoke-MiLinkValidation -ResourceId $instance.id `
            -ManagedInstanceId $mi.ResourceId `
            -DatabaseNames @("AdventureWorks", "WideWorldImporters") `
            -SqlServerIP "10.0.0.5"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$ManagedInstanceId,
        [Parameter(Mandatory)][string[]]$DatabaseNames,
        [Parameter(Mandatory)][string]$SqlServerIP,
        [string]$AvailabilityGroupName = "",
        [string]$DistributedAvailabilityGroupName = "",
        [string[]]$AssessmentCategories = @("SqlInstance", "SqlInstanceDatabase", "ManagedInstance", "ManagedInstanceDatabase", "ManagedInstanceCrossValidation", "Certificates", "BoxToMiNetworkConnectivity", "MiToBoxNetworkConnectivity", "SqlInstanceAg", "DagCrossValidation")
    )

    Write-StepHeader -StepNumber "7" -Title "Validate Databases for MI Link" `
        -Description "Run compatibility and network checks before creating the link."

    # Build request body
    $body = @{
        azureManagedInstanceResourceId = $ManagedInstanceId
        azureManagedInstanceRole       = "Secondary"
        databaseNames                  = $DatabaseNames
        assessmentCategories           = $AssessmentCategories
        sqlServerIpAddress             = $SqlServerIP
    }

    if ($AvailabilityGroupName) {
        $body["availabilityGroupName"] = $AvailabilityGroupName
    }
    if ($DistributedAvailabilityGroupName) {
        $body["distributedAvailabilityGroupName"] = $DistributedAvailabilityGroupName
    }

    $uri = "$ResourceId/runManagedInstanceLinkAssessment?api-version=$($script:ApiVersions.ArcSqlActions)"
    Write-Verbose "Running MI Link assessment..."
    Write-Host "  Validating $($DatabaseNames.Count) database(s)..." -ForegroundColor White
    Write-Host "  Databases: $($DatabaseNames -join ', ')" -ForegroundColor Gray

    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    # Use Location-based polling for the assessment endpoint. The Azure-AsyncOperation
    # endpoint can time out server-side for long-running assessments ("Operation timeout,
    # previous status: RunningAssessmentForMiLink"), while the Location URL reliably
    # returns the final result when ready.
    Write-Host "  Polling for validation results..." -ForegroundColor Gray

    $pollUrl = $null
    if ($response.Headers.ContainsKey("Location")) {
        $pollUrl = $response.Headers["Location"]
        if ($pollUrl -is [array]) { $pollUrl = $pollUrl[0] }
        Write-Verbose "Polling via Location header (preferred for assessment)"
    }
    elseif ($response.Headers.ContainsKey("Azure-AsyncOperation")) {
        $pollUrl = $response.Headers["Azure-AsyncOperation"]
        if ($pollUrl -is [array]) { $pollUrl = $pollUrl[0] }
        Write-Verbose "Polling via Azure-AsyncOperation header (fallback)"
    }

    $result = $null
    if (-not $pollUrl) {
        Write-Warning "No polling header found. The operation may have completed synchronously."
        $result = $response.Content
    }
    else {
        $deadline = (Get-Date).AddMinutes(30)
        $attempt = 0

        while ((Get-Date) -lt $deadline) {
            $attempt++
            Start-Sleep -Seconds 2

            try {
                $pollResponse = Invoke-ArmRequest -Uri $pollUrl -Method GET
                $status = $pollResponse.Content.status
                if (-not $status -and $pollResponse.Content.properties) {
                    $status = $pollResponse.Content.properties.provisioningState
                }

                Write-Verbose "Poll attempt $attempt - Status: $status"
                if ($status) {
                    Write-Host "    Status: $status" -ForegroundColor Gray
                }

                # Terminal success states
                if ($status -in @("Succeeded", "MiLinkAssessmentSucceeded")) {
                    Write-Host "  Validation completed." -ForegroundColor Green
                    $result = $pollResponse.Content
                    break
                }
                elseif ($status -eq "Failed") {
                    $errorMsg = if ($pollResponse.Content.error) { $pollResponse.Content.error.message } else { "Unknown error" }
                    throw "Assessment failed: $errorMsg"
                }
                elseif ($status -eq "Canceled") {
                    throw "Assessment was canceled."
                }

                # Also check if the response already contains assessment results
                # (Location polling can return the full result directly)
                if ($pollResponse.Content.properties.statusHistory) {
                    $hasAssessment = $pollResponse.Content.properties.statusHistory |
                        Where-Object { $_.provisioningState -eq "MiLinkAssessmentSucceeded" }
                    if ($hasAssessment) {
                        Write-Host "  Assessment results received." -ForegroundColor Green
                        $result = $pollResponse.Content
                        break
                    }
                }
            }
            catch {
                if ($_.Exception.Message -match "Assessment (failed|canceled)") { throw }
                Write-Verbose "Poll attempt $attempt error: $($_.Exception.Message). Retrying..."
            }
        }

        if (-not $result) {
            throw "Validation timed out after 30 minutes."
        }
    }

    # Parse and display results
    if ($result -and $result.properties -and $result.properties.statusHistory) {
        $assessmentEntry = $result.properties.statusHistory |
            Where-Object { $_.provisioningState -eq "MiLinkAssessmentSucceeded" } |
            Select-Object -First 1

        if ($assessmentEntry -and $assessmentEntry.value -and $assessmentEntry.value.results) {
            $findings = $assessmentEntry.value.results

            Write-Host " "
            Write-Host "  Validation Results:" -ForegroundColor Yellow
            Write-Host "  $('-' * 50)" -ForegroundColor Yellow

            $passCount = 0
            $warnCount = 0
            $failCount = 0

            foreach ($finding in $findings) {
                $status = $finding.Status
                $color = switch ($status) {
                    "Success" { "Green"; $passCount++ }
                    "Warning" { "Yellow"; $warnCount++ }
                    "Failure" { "Red"; $failCount++ }
                    default   { "White" }
                }
                Write-Host ("  [{0,-8}] {1}" -f $status, $finding.Name) -ForegroundColor $color
                if ($finding.Information) {
                    Write-Host "             $($finding.Information)" -ForegroundColor Gray
                }
                if ($finding.FailingDbs -and $finding.FailingDbs.Count -gt 0) {
                    Write-Host "             Failing DBs: $($finding.FailingDbs -join ', ')" -ForegroundColor Red
                }
            }

            Write-Host " "
            Write-Host "  Summary: $passCount passed, $warnCount warnings, $failCount failures" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

            if ($failCount -gt 0) {
                Write-Warning "Some validations failed. Resolve the issues before creating the MI Link."
            }
        }
    }

    return $result
}

# ============================================================================
# STEP 8a: CREATE MI LINK
# ============================================================================

function New-MiLink {
    <#
    .SYNOPSIS
        Creates a Managed Instance Link between Arc SQL Server and Azure SQL MI.

    .DESCRIPTION
        Creates an Availability Group and Distributed Availability Group to replicate
        selected databases from the Arc-enabled SQL Server to the target managed instance.
        This is a long-running operation that progresses through several stages.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID (partner resource).

    .PARAMETER ManagedInstanceId
        Target managed instance ARM resource ID.

    .PARAMETER ManagedInstanceName
        Target managed instance name.

    .PARAMETER ManagedInstanceDomainName
        Target MI fully qualified domain name (FQDN).

    .PARAMETER DatabaseNames
        Array of database names to include in the link.

    .PARAMETER SqlServerIP
        IP address of the SQL Server for the listener URL.

    .PARAMETER AvailabilityGroupName
        Name for the AG. Auto-generated if not specified.

    .PARAMETER DistributedAvailabilityGroupName
        Name for the DAG. Auto-generated if not specified.

    .PARAMETER InstanceAvailabilityGroupName
        AG name on the MI side. Auto-generated if not specified.

    .EXAMPLE
        $link = New-MiLink -ResourceId $instance.id `
            -ManagedInstanceId $mi.ResourceId `
            -ManagedInstanceName $mi.Name `
            -ManagedInstanceDomainName $mi.FQDN `
            -DatabaseNames @("AdventureWorks") `
            -SqlServerIP "10.0.0.5"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$ManagedInstanceId,
        [Parameter(Mandatory)][string]$ManagedInstanceName,
        [Parameter(Mandatory)][string]$ManagedInstanceDomainName,
        [Parameter(Mandatory)][string[]]$DatabaseNames,
        [Parameter(Mandatory)][string]$SqlServerIP,
        [string]$AvailabilityGroupName,
        [string]$DistributedAvailabilityGroupName,
        [string]$InstanceAvailabilityGroupName
    )

    Write-StepHeader -StepNumber "8a" -Title "Create MI Link" `
        -Description "Establish Availability Group replication to Azure SQL MI."

    # Auto-generate names if not provided
    $timestamp = Get-Date -Format "yyyyMMddHHmm"
    if (-not $AvailabilityGroupName) {
        $AvailabilityGroupName = "AG_MiLink_$timestamp"
        Write-Verbose "Auto-generated AG name: $AvailabilityGroupName"
    }
    if (-not $DistributedAvailabilityGroupName) {
        $DistributedAvailabilityGroupName = "DAG_MiLink_$timestamp"
        Write-Verbose "Auto-generated DAG name: $DistributedAvailabilityGroupName"
    }
    if (-not $InstanceAvailabilityGroupName) {
        $InstanceAvailabilityGroupName = "${ManagedInstanceName}_AG_$timestamp"
        Write-Verbose "Auto-generated instance AG name: $InstanceAvailabilityGroupName"
    }

    # Extract subscription and resource group from MI ID
    $miParts = Format-ResourceIdParts -ResourceId $ManagedInstanceId

    Write-Host "  Configuration:" -ForegroundColor Yellow
    Write-ResultTable -Data ([ordered]@{
        "Databases"        = $DatabaseNames -join ", "
        "SQL Server IP"    = $SqlServerIP
        "Target MI"        = $ManagedInstanceName
        "AG Name"          = $AvailabilityGroupName
        "DAG Name"         = $DistributedAvailabilityGroupName
        "Instance AG Name" = $InstanceAvailabilityGroupName
    })

    if (-not $PSCmdlet.ShouldProcess("Create MI Link for databases: $($DatabaseNames -join ', ')")) {
        return
    }

    # Build ARM request body
    $body = @{
        availabilityGroup = @{
            availabilityGroupName = $AvailabilityGroupName
            replicas = @(
                @{
                    serverInstance    = $ResourceId
                    endpointUrl       = "TCP://ALL:0"
                    availabilityMode  = "SYNCHRONOUS_COMMIT"
                    failoverMode      = "MANUAL"
                    seedingMode       = "AUTOMATIC"
                }
            )
            databases = $DatabaseNames
        }
        distributedAvailabilityGroup = @{
            availabilityGroupName = $DistributedAvailabilityGroupName
            primaryAvailabilityGroup = @{
                availabilityGroup  = "$ResourceId/availabilityGroups/$AvailabilityGroupName"
                listenerUrl        = $SqlServerIP
                availabilityMode   = "ASYNCHRONOUS_COMMIT"
                failoverMode       = "MANUAL"
                seedingMode        = "AUTOMATIC"
            }
            secondaryAvailabilityGroup = @{
                availabilityGroup  = $ManagedInstanceId
                listenerUrl        = "tcp://${ManagedInstanceDomainName}:5022"
                availabilityMode   = "ASYNCHRONOUS_COMMIT"
                failoverMode       = "MANUAL"
                seedingMode        = "AUTOMATIC"
            }
        }
        miLinkConfiguration = @{
            instanceAvailabilityGroupName = $InstanceAvailabilityGroupName
        }
    }

    $uri = "$ResourceId/createManagedInstanceLink?api-version=$($script:ApiVersions.ArcSqlCreateLink)"

    Write-Host "  Creating MI Link... (this may take several minutes)" -ForegroundColor White

    # Status display map
    $statusMap = @{
        "Accepted"                            = "Starting"
        "ConnectingToAgent"                   = "Connecting to Arc agent"
        "CreatingDbmEndpoint"                 = "Creating source endpoint"
        "CreatingAvailabilityGroup"           = "Creating Availability Group"
        "ExchangingCertificates"              = "Exchanging security certificates"
        "JoiningDistributedAvailabilityGroup" = "Joining Distributed Availability Group"
        "Succeeded"                           = "Succeeded"
        "Failed"                              = "Failed"
    }

    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    $result = Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 30 `
        -OnStatusUpdate {
            param($status, $content)
            $displayStatus = if ($statusMap.ContainsKey($status)) { $statusMap[$status] } else { $status }
            Write-Host "    [$([DateTime]::Now.ToString('HH:mm:ss'))] $displayStatus" -ForegroundColor Cyan
        }

    Write-Host " "
    Write-Host "  MI Link created successfully!" -ForegroundColor Green
    Write-Host "  AG Name:  $AvailabilityGroupName" -ForegroundColor White
    Write-Host "  DAG Name: $DistributedAvailabilityGroupName" -ForegroundColor White
    Write-Host " "

    return [PSCustomObject]@{
        AvailabilityGroupName            = $AvailabilityGroupName
        DistributedAvailabilityGroupName = $DistributedAvailabilityGroupName
        InstanceAvailabilityGroupName    = $InstanceAvailabilityGroupName
        Databases                        = $DatabaseNames
        Success                          = $true
    }
}

# ============================================================================
# STEP 8b: LRS MIGRATION (ALTERNATIVE METHOD)
# ============================================================================

function Get-StorageAccounts {
    <#
    .SYNOPSIS
        Lists Azure Storage accounts in a subscription for LRS migration.

    .DESCRIPTION
        Defaults to the target subscription set in Connect-ArcMigration
        (-TargetSubscriptionId). Override by passing -SubscriptionId explicitly.

    .PARAMETER SubscriptionId
        Azure subscription ID to list storage accounts from.
        Defaults to the target subscription from Connect-ArcMigration.

    .EXAMPLE
        $storageAccounts = Get-StorageAccounts -SubscriptionId "00000000-..."

    .EXAMPLE
        # Uses the TargetSubscriptionId set during Connect-ArcMigration
        $storageAccounts = Get-StorageAccounts
    #>
    [CmdletBinding()]
    param(
        [string]$SubscriptionId = $script:TargetSubscriptionId
    )

    if (-not $SubscriptionId) {
        throw "SubscriptionId is required. Pass -SubscriptionId or set -TargetSubscriptionId in Connect-ArcMigration."
    }

    Write-StepHeader -StepNumber "8b.1" -Title "List Storage Accounts" `
        -Description "Find storage accounts for LRS backup location."

    $uri = "/subscriptions/$SubscriptionId/providers/Microsoft.Storage/storageAccounts?api-version=$($script:ApiVersions.StorageAccounts)"
    Write-Verbose "Listing storage accounts in subscription: $SubscriptionId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $accounts = $response.Content.value | ForEach-Object {
        $parts = Format-ResourceIdParts -ResourceId $_.id
        [PSCustomObject]@{
            Name          = $_.name
            ResourceId    = $_.id
            Location      = $_.location
            ResourceGroup = $parts.ResourceGroup
            Kind          = $_.kind
            SkuName       = $_.sku.name
        }
    }

    Write-Host "  Found $($accounts.Count) storage account(s):" -ForegroundColor White
    $accounts | Format-Table -Property Name, Location, Kind, SkuName -AutoSize | Out-String | Write-Verbose

    return $accounts
}

function Get-BlobContainers {
    <#
    .SYNOPSIS
        Lists blob containers in a storage account.

    .PARAMETER StorageAccountResourceId
        Full ARM resource ID of the storage account.

    .EXAMPLE
        $containers = Get-BlobContainers -StorageAccountResourceId $sa.ResourceId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StorageAccountResourceId
    )

    $uri = "$StorageAccountResourceId/blobServices/default/containers?api-version=$($script:ApiVersions.BlobContainers)"
    Write-Verbose "Listing blob containers for: $StorageAccountResourceId"

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $containers = $response.Content.value | ForEach-Object {
        [PSCustomObject]@{
            Name         = $_.name
            ResourceId   = $_.id
            PublicAccess = $_.properties.publicAccess
            LastModified = $_.properties.lastModified
        }
    }

    Write-Host "  Blob containers:" -ForegroundColor White
    $containers | Format-Table -Property Name, PublicAccess, LastModified -AutoSize | Out-String | Write-Host

    return $containers
}

function Test-ManagedIdentityRbac {
    <#
    .SYNOPSIS
        Checks if the managed instance has required RBAC roles on storage accounts.

    .DESCRIPTION
        Retrieves the MI's managed identity principal ID and checks its role
        assignments on each provided storage account. Reports any missing permissions.

    .PARAMETER ManagedInstanceId
        Full ARM resource ID of the managed instance.

    .PARAMETER StorageAccountResourceIds
        Array of storage account ARM resource IDs to check.

    .EXAMPLE
        $missing = Test-ManagedIdentityRbac -ManagedInstanceId $mi.ResourceId `
            -StorageAccountResourceIds @($sa.ResourceId)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManagedInstanceId,
        [Parameter(Mandatory)][string[]]$StorageAccountResourceIds
    )

    Write-StepHeader -StepNumber "8b.2" -Title "Check RBAC Permissions" `
        -Description "Verify MI managed identity has storage access."

    # Get MI principal ID
    $miUri = "$ManagedInstanceId`?api-version=$($script:ApiVersions.ManagedInstanceSku)"
    Write-Verbose "Fetching MI identity: $ManagedInstanceId"
    $miResponse = Invoke-ArmRequest -Uri $miUri -Method GET
    Write-Verbose ($miResponse.Content | ConvertTo-Json | Out-String)
    $principalId = $miResponse.Content.identity.principalId
    if (-not $principalId) {
        Write-Warning "Managed Instance does not have a system-assigned managed identity enabled."
        Write-Warning "Enable managed identity on the MI before proceeding with LRS migration."
        return $StorageAccountResourceIds
    }

    Write-Host "  MI Principal ID: $principalId" -ForegroundColor Gray

    $acceptableRoles = $script:StorageRoles.Values
    $missingRbac = @()

    foreach ($saId in $StorageAccountResourceIds) {
        $saName = ($saId -split "/")[-1]
        Write-Verbose "Checking RBAC for storage account: $saName"

        $roleUri = "$saId/providers/Microsoft.Authorization/roleAssignments?`$filter=principalId eq '$principalId'&api-version=$($script:ApiVersions.RoleAssignments)"
        $roleResponse = Invoke-ArmRequest -Uri $roleUri -Method GET

        $assignments = $roleResponse.Content.value
        $hasRole = $false
        
        Write-Verbose ($assignments | ConvertTo-Json | Out-String)

        foreach ($assignment in $assignments) {
            $roleDefId = ($assignment.properties.roleDefinitionId -split "/")[-1]
            if ($roleDefId -in $acceptableRoles) {
                $hasRole = $true
                Write-Verbose "Found acceptable role assignment: $($assignment.name) with role definition ID: $roleDefId"
                break
            }
        }

        if ($hasRole) {
            Write-Host "  [PASS] $saName - MI has storage access" -ForegroundColor Green
        }
        else {
            Write-Host "  [FAIL] $saName - MI is missing required storage RBAC role" -ForegroundColor Red
            $missingRbac += $saId
        }
    }

    Write-Host " "
    if ($missingRbac.Count -gt 0) {
        Write-Warning "$($missingRbac.Count) storage account(s) missing RBAC. Assign 'Storage Blob Data Reader' (or higher) to the MI's managed identity."
    }
    else {
        Write-Host "  All storage accounts have proper RBAC." -ForegroundColor Green
    }

    return $missingRbac
}

function New-DmsResource {
    <#
    .SYNOPSIS
        Creates an Azure Database Migration Service resource for LRS.

    .DESCRIPTION
        Defaults to the target subscription set in Connect-ArcMigration
        (-TargetSubscriptionId). Override by passing -SubscriptionId explicitly.

    .PARAMETER SubscriptionId
        Target subscription ID.
        Defaults to the target subscription from Connect-ArcMigration.

    .PARAMETER ResourceGroupName
        Target resource group name.

    .PARAMETER DmsResourceName
        Name for the DMS resource.

    .PARAMETER Location
        Azure region for the DMS resource.

    .EXAMPLE
        $dms = New-DmsResource -SubscriptionId "..." -ResourceGroupName "myRG" `
            -DmsResourceName "myDMS" -Location "eastus"

    .EXAMPLE
        # Uses the TargetSubscriptionId set during Connect-ArcMigration
        $dms = New-DmsResource -ResourceGroupName "myRG" -DmsResourceName "myDMS" -Location "eastus"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$SubscriptionId = $script:TargetSubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$DmsResourceName,
        [Parameter(Mandatory)][string]$Location
    )

    if (-not $SubscriptionId) {
        throw "SubscriptionId is required. Pass -SubscriptionId or set -TargetSubscriptionId in Connect-ArcMigration."
    }

    Write-StepHeader -StepNumber "8b.3" -Title "Create DMS Resource" `
        -Description "Create Database Migration Service for LRS migration."

    $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DataMigration/sqlMigrationServices/${DmsResourceName}?api-version=$($script:ApiVersions.DataMigrationService)"

    $body = @{
        location = $Location
        tags = @{
            createdBy = "ArcMigrationScript"
            createdOn = (Get-Date).ToString("o")
        }
    }

    if (-not $PSCmdlet.ShouldProcess("Create DMS resource '$DmsResourceName' in $Location")) {
        return
    }

    Write-Host "  Creating DMS resource: $DmsResourceName in $Location ..." -ForegroundColor White

    $response = Invoke-ArmRequest -Uri $uri -Method PUT -Body $body

    if ($response.StatusCode -in @(200, 201)) {
        # Check if async
        if ($response.Headers.ContainsKey("Azure-AsyncOperation")) {
            $result = Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 5
        }

        $dmsResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DataMigration/sqlMigrationServices/$DmsResourceName"
        Write-Host "  DMS resource created: $dmsResourceId" -ForegroundColor Green

        return [PSCustomObject]@{
            ResourceId = $dmsResourceId
            Name       = $DmsResourceName
            Location   = $Location
        }
    }
    else {
        throw "Failed to create DMS resource. Status: $($response.StatusCode)"
    }
}

function Start-LrsMigration {
    <#
    .SYNOPSIS
        Starts a database migration using Log Replay Service (LRS).

    .DESCRIPTION
        Creates a databaseMigrations resource on the target managed instance
        for each specified database, pointing to backups in blob storage.

    .PARAMETER ManagedInstanceId
        Target managed instance ARM resource ID.

    .PARAMETER ArcSqlServerResourceId
        Source Arc SQL Server instance resource ID.

    .PARAMETER Databases
        Array of hashtables, each containing:
        - SourceDatabaseName: Name of the source database
        - TargetDatabaseName: Name on the target MI (usually same)
        - StorageAccountResourceId: Storage account ARM resource ID
        - BlobContainerName: Name of the blob container
        - BlobFolderPath: Folder path within the container (optional)

    .PARAMETER DmsResourceId
        ARM resource ID of the DMS resource from New-DmsResource.

    .PARAMETER Location
        Target Azure region.

    .EXAMPLE
        Start-LrsMigration -ManagedInstanceId $mi.ResourceId `
            -ArcSqlServerResourceId $instance.id `
            -Databases @(@{
                SourceDatabaseName = "AdventureWorks"
                TargetDatabaseName = "AdventureWorks"
                StorageAccountResourceId = $sa.ResourceId
                BlobContainerName = "backups"
                BlobFolderPath = "AdventureWorks"
            }) `
            -DmsResourceId $dms.ResourceId `
            -Location "eastus"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ManagedInstanceId,
        [Parameter(Mandatory)][string]$ArcSqlServerResourceId,
        [Parameter(Mandatory)][hashtable[]]$Databases,
        [Parameter(Mandatory)][string]$DmsResourceId,
        [Parameter(Mandatory)][string]$Location
    )

    Write-StepHeader -StepNumber "8b.4" -Title "Start LRS Migration" `
        -Description "Begin data migration using Log Replay Service."

    $results = @()

    foreach ($db in $Databases) {
        $sourceDb = $db.SourceDatabaseName
        $targetDb = if ($db.TargetDatabaseName) { $db.TargetDatabaseName } else { $sourceDb }

        if (-not $PSCmdlet.ShouldProcess("Start migration for database: $sourceDb -> $targetDb")) {
            continue
        }

        Write-Host "  Starting migration: $sourceDb -> $targetDb ..." -ForegroundColor White

        $blobPath = $db.BlobContainerName
        if ($db.BlobFolderPath -and $db.BlobFolderPath -ne "/") {
            $blobPath = "$($db.BlobContainerName)/$($db.BlobFolderPath)"
        }
        
        $body = @{
            location = $Location
            properties = @{
                sourceDatabaseName = $sourceDb
                sqlServerInstanceId = $ArcSqlServerResourceId
                backupConfiguration = @{
                    sourceLocation = @{
                        #fileStorageType = "AzureBlob"
                        AzureBlob = @{
                            blobContainerName      = $blobPath
                            storageAccountResourceId = $db.StorageAccountResourceId
                            authType               = "ManagedIdentity"
                            identity               = @{ type = "SystemAssigned" }
                        }
                    }
                }
                migrationService = $DmsResourceId
                scope            = $ManagedInstanceId
            }
        }

        Write-Verbose "Request body for $sourceDb -> $targetDb : $(ConvertTo-Json $body -Depth 20)"

        $uri = "$ManagedInstanceId/providers/Microsoft.DataMigration/databaseMigrations/${targetDb}?api-version=$($script:ApiVersions.DataMigrationService)"

        try {
            $response = Invoke-ArmRequest -Uri $uri -Method PUT -Body $body

            Write-Host "    Migration started for $sourceDb" -ForegroundColor Green
            $results += [PSCustomObject]@{
                SourceDatabase = $sourceDb
                TargetDatabase = $targetDb
                Status         = "Started"
                Error          = $null
            }
        }
        catch {
            Write-Error "    Failed to start migration for ${sourceDb}: $($_.Exception.Message)"
            $results += [PSCustomObject]@{
                SourceDatabase = $sourceDb
                TargetDatabase = $targetDb
                Status         = "Failed"
                Error          = $_.Exception.Message
            }
        }
    }

    Write-Host " "
    Write-Host "  Migration Start Summary:" -ForegroundColor Yellow
    $results | Format-Table -Property SourceDatabase, TargetDatabase, Status -AutoSize | Out-String | Write-Host

    return $results
}

# ============================================================================
# STEP 9: MONITOR REPLICATION
# ============================================================================

function Get-MiLinkReplicationStatus {
    <#
    .SYNOPSIS
        Monitors MI Link replication status across all availability groups.

    .DESCRIPTION
        Fetches all availability groups on the Arc SQL Server that are linked
        to Azure SQL MI, and displays the synchronization state of each database.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID.

    .EXAMPLE
        $status = Get-MiLinkReplicationStatus -ResourceId $instance.id
        $status | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId
    )

    Write-StepHeader -StepNumber "9a" -Title "Monitor MI Link Replication" `
        -Description "Check synchronization state of databases replicated via MI Link."

    # Get all availability groups
    $uri = "$ResourceId/getAllAvailabilityGroups?api-version=$($script:ApiVersions.ArcSqlAvailabilityGroups)"
    Write-Verbose "Fetching availability groups..."

    $response = Invoke-ArmRequest -Uri $uri -Method POST

    $agList = $response.Content.value
    if (-not $agList -or $agList.Count -eq 0) {
        # Try polling if it's async
        if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("Location"))) {
            $agResult = Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 5
            $agList = $agResult.value
        }
    }

    if (-not $agList -or $agList.Count -eq 0) {
        Write-Warning "No availability groups found on this SQL Server instance."
        return @()
    }

    # Filter to MI-linked AGs
    $miLinkedAGs = $agList | Where-Object {
        $_.info -and $_.info.replicationPartnerType -eq "AzureSQLManagedInstance"
    }

    if ($miLinkedAGs.Count -eq 0) {
        Write-Warning "No availability groups linked to Azure SQL MI found."
        return @()
    }

    Write-Host "  Found $($miLinkedAGs.Count) MI-linked availability group(s):" -ForegroundColor White
    Write-Host " "

    $allDatabases = @()

    foreach ($ag in $miLinkedAGs) {
        $agName = $ag.info.availabilityGroupName
        $dagName = $ag.info.dag

        Write-Host "  Availability Group: $agName" -ForegroundColor Yellow
        Write-Host "  DAG: $dagName" -ForegroundColor Gray

        if ($ag.databases) {
            foreach ($db in $ag.databases) {
                $syncState = $db.synchronizationState
                $color = switch ($syncState) {
                    "SYNCHRONIZED"  { "Green" }
                    "SYNCHRONIZING" { "Cyan" }
                    "CREATING"      { "Yellow" }
                    "STALLED"       { "Red" }
                    default         { "White" }
                }

                $dbResult = [PSCustomObject]@{
                    AvailabilityGroup = $agName
                    DAGName           = $dagName
                    Database          = $db.databaseName
                    SyncState         = $syncState
                    SyncHealth        = $db.synchronizationHealth
                    ReplicaState      = $db.replicaState
                }
                $allDatabases += $dbResult

                Write-Host ("    [{0,-15}] {1}" -f $syncState, $db.databaseName) -ForegroundColor $color
            }
        }
        Write-Host " "
    }

    # Also get createdAt timestamps from the AG list
    $agListUri = "$ResourceId/availabilityGroups?api-version=$($script:ApiVersions.ArcSqlDatabases)"
    try {
        Write-Verbose "Fetching AG metadata for timestamps..."
        $agMetaResponse = Invoke-ArmRequest -Uri $agListUri -Method GET
        if ($agMetaResponse.Content.value) {
            foreach ($agMeta in $agMetaResponse.Content.value) {
                $matching = $allDatabases | Where-Object { $_.AvailabilityGroup -eq $agMeta.name }
                foreach ($m in $matching) {
                    $m | Add-Member -NotePropertyName "CreatedAt" -NotePropertyValue $agMeta.properties.createdAt -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        Write-Verbose "Could not fetch AG metadata: $($_.Exception.Message)"
    }

    return $allDatabases
}

function Get-MiLinkReplicaLag {
    <#
    .SYNOPSIS
        Gets replica lag telemetry for MI-linked databases.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID.

    .PARAMETER DatabaseNames
        Array of database names to check lag for.

    .EXAMPLE
        $lag = Get-MiLinkReplicaLag -ResourceId $instance.id -DatabaseNames @("db1")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string[]]$DatabaseNames
    )

    Write-StepHeader -StepNumber "9a.2" -Title "Replica Lag Telemetry" `
        -Description "Check replication lag for MI-linked databases."

    $body = @{
        datasetName     = "SecondaryReplicaLag"
        interval        = "PT1M"
        aggregationType = "Maximum"
        databaseNames   = $DatabaseNames
        startTime       = (Get-Date).AddMinutes(-5).ToUniversalTime().ToString("o")
    }

    $uri = "$ResourceId/getTelemetry?api-version=$($script:ApiVersions.ArcSqlTelemetry)"
    Write-Verbose "Fetching replica lag telemetry..."

    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    # Poll if async
    $result = $response.Content
    if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation"))) {
        $result = Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 2
    }

    if ($result -and $result.properties -and $result.properties.rows) {
        Write-Host "  Replica Lag Data:" -ForegroundColor Yellow
        Write-Host " "

        $columns = $result.properties.columns | ForEach-Object { $_.name }
        Write-Host ("  {0}" -f ($columns -join "  |  ")) -ForegroundColor Gray

        foreach ($row in $result.properties.rows) {
            Write-Host ("  {0}" -f ($row -join "  |  ")) -ForegroundColor White
        }
    }
    else {
        Write-Host "  No lag telemetry data available yet." -ForegroundColor Gray
    }

    return $result
}

function Get-LrsMigrationStatus {
    <#
    .SYNOPSIS
        Monitors LRS migration progress for all database migrations.

    .DESCRIPTION
        Lists all DMS migrations and shows current status for each database,
        including restore progress and pending backup files.

    .PARAMETER DmsResourceId
        ARM resource ID of the DMS resource.

    .PARAMETER ShowDetails
        Fetch expanded details for each migration.

    .EXAMPLE
        $status = Get-LrsMigrationStatus -DmsResourceId $dms.ResourceId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DmsResourceId,
        [switch]$ShowDetails
    )

    Write-StepHeader -StepNumber "9b" -Title "Monitor LRS Migration" `
        -Description "Check status of database migrations using Log Replay Service."

    $uri = "$DmsResourceId/listMigrations?api-version=$($script:ApiVersions.DataMigrationService)"
    Write-Verbose "Listing DMS migrations..."

    $response = Invoke-ArmRequest -Uri $uri -Method GET

    $migrations = $response.Content.value
    if (-not $migrations -or $migrations.Count -eq 0) {
        Write-Warning "No migrations found for this DMS resource."
        return @()
    }

    $results = $migrations | ForEach-Object {
        $statusColor = switch ($_.properties.migrationStatus) {
            "InProgress"       { "Cyan" }
            "ReadyForCutover"  { "Green" }
            "Succeeded"        { "Green" }
            "Failed"           { "Red" }
            "Canceling"        { "Yellow" }
            "Canceled"         { "Gray" }
            default            { "White" }
        }

        [PSCustomObject]@{
            SourceDatabase   = $_.properties.sourceDatabaseName
            MigrationStatus  = $_.properties.migrationStatus
            ProvisioningState = $_.properties.provisioningState
            StartTime        = $_.properties.startedOn
            MigrationId      = $_.id
            OperationId      = $_.properties.migrationOperationId
            StatusColor      = $statusColor
            ErrorCode        = $_.properties.migrationFailureErrorCode
            ErrorMessage     = $_.properties.migrationFailureErrorMessage
        }
    }

    Write-Host "  Migration Status:" -ForegroundColor Yellow
    Write-Host " "
    foreach ($r in $results) {
        $statusText = $r.MigrationStatus
        if ($r.ErrorMessage) { $statusText = "$statusText - $($r.ErrorMessage)" }
        Write-Host ("  [{0,-17}] {1}" -f $r.MigrationStatus, $r.SourceDatabase) -ForegroundColor $r.StatusColor
    }
    Write-Host " "

    # Fetch details if requested
    if ($ShowDetails) {
        foreach ($r in $results) {
            Write-Verbose "Fetching details for: $($r.SourceDatabase)"
            $detailUri = "$($r.MigrationId)?`$expand=MigrationStatusDetails&api-version=$($script:ApiVersions.DataMigrationService)"

            try {
                $detailResponse = Invoke-ArmRequest -Uri $detailUri -Method GET
                $detail = $detailResponse.Content

                Write-Host "  Details for $($r.SourceDatabase):" -ForegroundColor Cyan
                if ($detail.properties.migrationStatusDetails) {
                    $statusDetails = $detail.properties.migrationStatusDetails
                    Write-ResultTable -Data ([ordered]@{
                        "Migration State"     = $statusDetails.migrationState
                        "Full Backup Sets"    = $statusDetails.fullBackupSetInfo.listOfBackupFiles.Count
                        "Last Restored File"  = $statusDetails.lastRestoredFilename
                        "Pending Log Backups" = $statusDetails.pendingLogBackupsCount
                    })
                }
            }
            catch {
                Write-Verbose "Could not fetch details for $($r.SourceDatabase): $($_.Exception.Message)"
            }
        }
    }

    return $results
}

# ============================================================================
# STEP 10: CUTOVER (COMPLETE MIGRATION)
# ============================================================================

function Invoke-MiLinkCutover {
    <#
    .SYNOPSIS
        Performs MI Link cutover (failover) to complete the migration.

    .DESCRIPTION
        Triggers the failover of the MI Link for a specific availability group,
        making the managed instance the primary replica. This is a long-running
        operation that should be performed only after databases are fully synchronized.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID.

    .PARAMETER AvailabilityGroupName
        Name of the availability group to fail over.

    .PARAMETER ManagedInstanceId
        Target managed instance ARM resource ID.

    .PARAMETER Force
        Force the cutover even if databases are not fully synchronized.
        WARNING: This may result in data loss.

    .EXAMPLE
        Invoke-MiLinkCutover -ResourceId $instance.id `
            -AvailabilityGroupName "AG_MiLink_202501" `
            -ManagedInstanceId $mi.ResourceId
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$AvailabilityGroupName,
        [Parameter(Mandatory)][string]$ManagedInstanceId,
        [switch]$Force
    )

    Write-StepHeader -StepNumber "10a" -Title "MI Link Cutover" `
        -Description "Failover the MI Link to complete migration."

    if ($Force) {
        Write-Warning "FORCE mode enabled. This may result in data loss if databases are not fully synchronized."
    }

    Write-Host "  Availability Group: $AvailabilityGroupName" -ForegroundColor White
    Write-Host "  Target MI: $ManagedInstanceId" -ForegroundColor White
    Write-Host " "

    if (-not $PSCmdlet.ShouldProcess("Cutover AG '$AvailabilityGroupName' to managed instance")) {
        return
    }

    $body = @{
        managedInstanceId = $ManagedInstanceId
    }
    if ($Force) {
        $body["force"] = $true
    }

    $uri = "$ResourceId/availabilityGroups/$AvailabilityGroupName/failoverMiLink?api-version=$($script:ApiVersions.ArcSqlActions)"

    Write-Host "  Initiating cutover... (this may take several minutes)" -ForegroundColor Yellow

    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    $result = Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 30 `
        -OnStatusUpdate {
            param($status, $content)
            Write-Host "    [$([DateTime]::Now.ToString('HH:mm:ss'))] Status: $status" -ForegroundColor Cyan
        }

    Write-Host " "
    Write-Host "  Cutover completed successfully!" -ForegroundColor Green
    Write-Host "  The managed instance is now the primary replica." -ForegroundColor Green
    Write-Host " "

    return [PSCustomObject]@{
        AvailabilityGroup = $AvailabilityGroupName
        Status            = "Succeeded"
        Success           = $true
    }
}

function Invoke-MiLinkBatchCutover {
    <#
    .SYNOPSIS
        Performs cutover for multiple availability groups in parallel.

    .PARAMETER ResourceId
        Arc SQL Server instance resource ID.

    .PARAMETER Databases
        Array of objects with AgName and ManagedInstanceId properties.

    .PARAMETER Force
        Force cutover even if not fully synchronized.

    .EXAMPLE
        Invoke-MiLinkBatchCutover -ResourceId $instance.id `
            -Databases @(
                @{ AgName = "AG1"; ManagedInstanceId = $mi.ResourceId },
                @{ AgName = "AG2"; ManagedInstanceId = $mi.ResourceId }
            )
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][hashtable[]]$Databases,
        [switch]$Force
    )

    Write-StepHeader -StepNumber "10a.2" -Title "Batch MI Link Cutover" `
        -Description "Failover multiple MI Links in parallel."

    if (-not $PSCmdlet.ShouldProcess("Batch cutover for $($Databases.Count) availability group(s)")) {
        return
    }

    Write-Host "  Starting cutover for $($Databases.Count) AG(s)..." -ForegroundColor White

    $jobs = @()

    foreach ($db in $Databases) {
        $agName = $db.AgName
        $miId = $db.ManagedInstanceId

        $body = @{
            managedInstanceId = $miId
        }
        if ($Force) { $body["force"] = $true }

        $uri = "$ResourceId/availabilityGroups/$agName/failoverMiLink?api-version=$($script:ApiVersions.ArcSqlActions)"

        Write-Host "  Initiating cutover for AG: $agName ..." -ForegroundColor Cyan

        try {
            $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

            $jobs += [PSCustomObject]@{
                AgName      = $agName
                Headers     = $response.Headers
                Status      = "Submitted"
            }
        }
        catch {
            Write-Error "  Failed to submit cutover for ${agName}: $($_.Exception.Message)"
            $jobs += [PSCustomObject]@{
                AgName = $agName
                Headers = $null
                Status  = "Failed"
            }
        }
    }

    # Poll each job
    Write-Host " "
    Write-Host "  Polling cutover results..." -ForegroundColor Gray

    $results = @()
    foreach ($job in $jobs) {
        if ($job.Status -eq "Failed") {
            $results += [PSCustomObject]@{
                AvailabilityGroup = $job.AgName
                Status            = "Failed"
            }
            continue
        }

        try {
            $pollResult = Wait-AsyncOperation -ResponseHeaders $job.Headers -PollIntervalSeconds 5 -TimeoutMinutes 30
            Write-Host "  [Succeeded] $($job.AgName)" -ForegroundColor Green
            $results += [PSCustomObject]@{
                AvailabilityGroup = $job.AgName
                Status            = "Succeeded"
            }
        }
        catch {
            Write-Host "  [Failed] $($job.AgName): $($_.Exception.Message)" -ForegroundColor Red
            $results += [PSCustomObject]@{
                AvailabilityGroup = $job.AgName
                Status            = "Failed"
            }
        }
    }

    Write-Host " "
    $results | Format-Table -Property AvailabilityGroup, Status -AutoSize | Out-String | Write-Host

    return $results
}

function Remove-MiLink {
    <#
    .SYNOPSIS
        Deletes an MI Link (availability group link to MI).

    .PARAMETER AvailabilityGroupId
        ARM resource ID of the availability group to unlink.

    .EXAMPLE
        Remove-MiLink -AvailabilityGroupId "/subscriptions/.../availabilityGroups/AG1"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][string]$AvailabilityGroupId
    )

    if (-not $PSCmdlet.ShouldProcess("Delete MI Link: $AvailabilityGroupId")) {
        return
    }

    Write-Host "  Deleting MI Link: $AvailabilityGroupId ..." -ForegroundColor Yellow

    $uri = "$AvailabilityGroupId/deleteMiLink?api-version=$($script:ApiVersions.ArcSqlAvailabilityGroups)"
    $response = Invoke-ArmRequest -Uri $uri -Method POST

    if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("Location"))) {
        Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 10
    }

    Write-Host "  MI Link deleted." -ForegroundColor Green
}

function Invoke-LrsCutover {
    <#
    .SYNOPSIS
        Performs LRS cutover for one or more database migrations.

    .DESCRIPTION
        Triggers the cutover for LRS migrations when databases are in
        'ReadyForCutover' state. Each database is cut over independently.

    .PARAMETER Migrations
        Array of migration objects from Get-LrsMigrationStatus, each containing
        MigrationId and OperationId.

    .EXAMPLE
        $readyMigrations = $status | Where-Object { $_.MigrationStatus -eq "ReadyForCutover" }
        Invoke-LrsCutover -Migrations $readyMigrations
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][PSObject[]]$Migrations
    )

    Write-StepHeader -StepNumber "10b" -Title "LRS Cutover" `
        -Description "Complete LRS migrations for databases ready for cutover."

    $results = @()

    foreach ($migration in $Migrations) {
        $dbName = $migration.SourceDatabase
        $migrationId = $migration.MigrationId
        $operationId = $migration.OperationId

        if (-not $operationId) {
            Write-Warning "Migration for '$dbName' has no operation ID. Skipping."
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("Cutover database: $dbName")) {
            continue
        }

        Write-Host "  Cutting over: $dbName ..." -ForegroundColor Yellow

        $body = @{
            migrationOperationId = $operationId
        }

        $uri = "$migrationId/cutover?api-version=$($script:ApiVersions.DataMigrationService)"

        try {
            $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

            if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("Location"))) {
                Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 30
            }

            Write-Host "    [Succeeded] $dbName cutover complete" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Database = $dbName
                Status   = "Succeeded"
            }
        }
        catch {
            Write-Error "    [Failed] $dbName cutover failed: $($_.Exception.Message)"
            $results += [PSCustomObject]@{
                Database = $dbName
                Status   = "Failed"
            }
        }
    }

    Write-Host " "
    $results | Format-Table -Property Database, Status -AutoSize | Out-String | Write-Host

    return $results
}

function Stop-LrsMigration {
    <#
    .SYNOPSIS
        Cancels an in-progress LRS migration.

    .PARAMETER MigrationId
        The migration resource ID.

    .PARAMETER OperationId
        The migration operation ID.

    .EXAMPLE
        Stop-LrsMigration -MigrationId $migration.MigrationId -OperationId $migration.OperationId
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][string]$MigrationId,
        [Parameter(Mandatory)][string]$OperationId
    )

    if (-not $PSCmdlet.ShouldProcess("Cancel LRS migration: $MigrationId")) {
        return
    }

    Write-Host "  Canceling LRS migration..." -ForegroundColor Yellow

    $body = @{
        migrationOperationId = $OperationId
    }

    $uri = "$MigrationId/cancel?api-version=$($script:ApiVersions.DataMigrationService)"
    $response = Invoke-ArmRequest -Uri $uri -Method POST -Body $body

    if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("Location"))) {
        Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 10
    }

    Write-Host "  Migration canceled." -ForegroundColor Green
}

function Remove-LrsMigration {
    <#
    .SYNOPSIS
        Deletes an LRS migration resource.

    .PARAMETER MigrationId
        The migration resource ID.

    .EXAMPLE
        Remove-LrsMigration -MigrationId $migration.MigrationId
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)][string]$MigrationId
    )

    if (-not $PSCmdlet.ShouldProcess("Delete LRS migration: $MigrationId")) {
        return
    }

    Write-Host "  Deleting LRS migration resource..." -ForegroundColor Yellow

    $uri = "$MigrationId`?api-version=$($script:ApiVersions.DataMigrationService)"
    $response = Invoke-ArmRequest -Uri $uri -Method DELETE

    if ($response.Headers -and ($response.Headers.ContainsKey("Azure-AsyncOperation") -or $response.Headers.ContainsKey("Location"))) {
        Wait-AsyncOperation -ResponseHeaders $response.Headers -PollIntervalSeconds 5 -TimeoutMinutes 10
    }

    Write-Host "  Migration resource deleted." -ForegroundColor Green
}

# ============================================================================
# CONVENIENCE: FULL MIGRATION WORKFLOWS
# ============================================================================

function Show-MigrationCommands {
    <#
    .SYNOPSIS
        Displays the available migration commands and a suggested workflow.
    #>
    [CmdletBinding()]
    param()

    Write-Host " "
    Write-Host $("=" * 70) -ForegroundColor Cyan
    Write-Host "  Arc SQL Server to Azure SQL MI - Migration Commands" -ForegroundColor Cyan
    Write-Host $("=" * 70) -ForegroundColor Cyan
    Write-Host " "
    Write-Host "  AUTHENTICATION" -ForegroundColor Yellow
    Write-Host "    Connect-ArcMigration            Sign in (use -TargetSubscriptionId for cross-sub)" -ForegroundColor White
    Write-Host " "
    Write-Host "  DISCOVERY" -ForegroundColor Yellow
    Write-Host "    Get-ArcSqlServerInstance         Get SQL Server instance details" -ForegroundColor White
    Write-Host "    Get-ArcSqlDatabases              List databases on the SQL Server" -ForegroundColor White
    Write-Host "    Get-MigrationAssessmentReport    Fetch full migration assessment" -ForegroundColor White
    Write-Host "    Get-ManagedInstances              List target managed instances" -ForegroundColor White
    Write-Host "    Get-ManagedInstanceSku            Get MI SKU details" -ForegroundColor White
    Write-Host "    Get-ManagedInstanceDatabases      List databases on target MI" -ForegroundColor White
    Write-Host " "
    Write-Host "  MI LINK METHOD" -ForegroundColor Yellow
    Write-Host "    Get-ArcMachineIPAddresses         Get Arc machine IPs" -ForegroundColor White
    Write-Host "    Invoke-MiLinkValidation           Validate databases for MI Link" -ForegroundColor White
    Write-Host "    New-MiLink                        Create MI Link (start replication)" -ForegroundColor White
    Write-Host "    Get-MiLinkReplicationStatus       Monitor replication status" -ForegroundColor White
    Write-Host "    Get-MiLinkReplicaLag              Check replica lag telemetry" -ForegroundColor White
    Write-Host "    Invoke-MiLinkCutover              Cutover single AG" -ForegroundColor White
    Write-Host "    Invoke-MiLinkBatchCutover         Cutover multiple AGs" -ForegroundColor White
    Write-Host "    Remove-MiLink                     Delete MI Link" -ForegroundColor White
    Write-Host " "
    Write-Host "  LRS METHOD" -ForegroundColor Yellow
    Write-Host "    Get-StorageAccounts               List storage accounts" -ForegroundColor White
    Write-Host "    Get-BlobContainers                List blob containers" -ForegroundColor White
    Write-Host "    Test-ManagedIdentityRbac          Check MI RBAC on storage" -ForegroundColor White
    Write-Host "    New-DmsResource                   Create DMS resource" -ForegroundColor White
    Write-Host "    Start-LrsMigration                Start LRS migration" -ForegroundColor White
    Write-Host "    Get-LrsMigrationStatus            Monitor LRS migration" -ForegroundColor White
    Write-Host "    Invoke-LrsCutover                 Cutover LRS migration" -ForegroundColor White
    Write-Host "    Stop-LrsMigration                 Cancel LRS migration" -ForegroundColor White
    Write-Host "    Remove-LrsMigration               Delete LRS migration resource" -ForegroundColor White
    Write-Host " "
    Write-Host "  HELP" -ForegroundColor Yellow
    Write-Host "    Show-MigrationCommands            Show this help" -ForegroundColor White
    Write-Host " "
    Write-Host "  CROSS-SUBSCRIPTION SUPPORT" -ForegroundColor Yellow
    Write-Host "    When the target MI is in a different subscription, pass" -ForegroundColor Gray
    Write-Host "    -TargetSubscriptionId to Connect-ArcMigration. Target-side" -ForegroundColor Gray
    Write-Host "    commands (Get-ManagedInstances, Get-StorageAccounts," -ForegroundColor Gray
    Write-Host "    New-DmsResource) will default to the target subscription." -ForegroundColor Gray
    Write-Host "    Both subscriptions must be in the same Azure AD tenant." -ForegroundColor Gray
    Write-Host " "
    Write-Host "  Use -Verbose with any command for detailed diagnostic logging." -ForegroundColor Gray
    Write-Host "  Use Get-Help `<CommandName`> -Full for detailed usage info." -ForegroundColor Gray
    Write-Host " "
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# When dot-sourced, all functions become available in the session.
# When run directly, show the available commands.
if ( $MyInvocation.InvocationName -ne "." ) {
    Show-MigrationCommands
}
