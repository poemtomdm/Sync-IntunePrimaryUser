Param(
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret,
    [Parameter(Mandatory=$false)] [switch]$DryRun
)

# Authentication
$SecSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential($ClientId, $SecSecret)

Write-Host "Connecting to Microsoft Graph" -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Creds

# Helper for Pagination
Function Get-GraphData {
    Param($Uri)
    $Results = @()
    while ($Uri) {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri
        $Results += $Response.value
        $Uri = $Response.'@odata.nextLink'
    }
    return $Results
}

# Data Collection (Strictly Windows)
Write-Host "Retrieving Windows devices..." -ForegroundColor Yellow
$Filter = "operatingSystem eq 'Windows'"
$allDevices = Get-GraphData -Uri "beta/deviceManagement/managedDevices?`$filter=$Filter"

# Sync Loop
$SyncReport = @()
foreach ($device in $allDevices) {
    $intuneId = $device.id
    $deviceName = $device.deviceName
    $currentPrimaryUserId = $device.userId
    
    # Identify last logged on user (Last entry in the collection)
    $lastUserEntry = $device.usersLoggedOn | Select-Object -Last 1
    $lastLoggedOnUserId = $lastUserEntry.userId

    # Skip if no user found or if already correct
    if ($null -eq $lastLoggedOnUserId -or $lastLoggedOnUserId -eq $currentPrimaryUserId) {
        continue 
    }

    # Fetch User Details for the log
    try {
        $userInfo = Invoke-MgGraphRequest -Method GET -Uri "beta/users/$lastLoggedOnUserId"
        $newUserName = $userInfo.displayName
    } catch {
        Write-Warning "Could not retrieve user info for ID: $lastLoggedOnUserId"
        continue
    }

    Write-Host "MISMATCH: $deviceName -> Target Primary: $newUserName" -ForegroundColor Yellow

    if (-not $DryRun) {
            # Update the Primary User relationship
            $uri = "beta/deviceManagement/managedDevices('$intuneId')/users/`$ref"
            $body = @{ "@odata.id" = "https://graph.microsoft.com/beta/users/$lastLoggedOnUserId" }
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json"
            
            $SyncReport += [pscustomobject]@{
                DeviceName = $deviceName
                Previous   = $device.userDisplayName
                NewPrimary = $newUserName
                Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm"
            }
        }
        else {
        Write-Host "[DRY RUN] Would update $deviceName to $newUserName" -ForegroundColor Gray
    }
}
# Reporting
if ($SyncReport.Count -gt 0) {
    $FileName = "PrimaryUserSync_$(Get-Date -Format 'yyyyMMdd_HHmm').json"
    $SyncReport | ConvertTo-Json | Out-File -FilePath "$PSScriptRoot/$FileName"
    Write-Host "Process finished. Results saved to: $FileName" -ForegroundColor Green
} else {
    Write-Host "No Windows devices required synchronization." -ForegroundColor Gray
}