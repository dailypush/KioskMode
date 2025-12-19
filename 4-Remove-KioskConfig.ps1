#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes AssignedAccess kiosk configuration and optionally deletes the kiosk user.

.DESCRIPTION
    This script performs a complete rollback of the kiosk configuration:
    - Removes AssignedAccess configuration
    - Clears AppLocker policies (optional)
    - Optionally deletes the kiosk user account
    - Restores normal Windows access

.PARAMETER RemoveUser
    If specified, also deletes the kiosk user account.

.PARAMETER ClearAppLocker
    If specified, clears AppLocker policies.

.PARAMETER KioskUserName
    Name of the kiosk user account.

.NOTES
    Must be run as Administrator.
    Use with caution - this will remove all kiosk restrictions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$RemoveUser,
    
    [Parameter(Mandatory=$false)]
    [switch]$ClearAppLocker,
    
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser"
)

# Script configuration
$ErrorActionPreference = "Stop"
$LogFile = Join-Path $PSScriptRoot "KioskSetup.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Remove AssignedAccess configuration
function Remove-AssignedAccessConfig {
    Write-Log "Removing AssignedAccess configuration..."
    
    try {
        # Try using Clear-AssignedAccess cmdlet
        $existingConfig = Get-AssignedAccess -ErrorAction SilentlyContinue
        if ($existingConfig) {
            Write-Log "Found AssignedAccess configuration, removing..."
            Clear-AssignedAccess -ErrorAction SilentlyContinue
            Write-Log "AssignedAccess cleared via cmdlet" "SUCCESS"
        }
        
        # Try removing via WMI/MDM
        $namespaceName = "root\cimv2\mdm\dmmap"
        $className = "MDM_AssignedAccess"
        $mdmConfig = Get-CimInstance -Namespace $namespaceName -ClassName $className -ErrorAction SilentlyContinue
        
        if ($mdmConfig) {
            Write-Log "Found MDM AssignedAccess configuration, removing..."
            Remove-CimInstance -InputObject $mdmConfig -ErrorAction SilentlyContinue
            Write-Log "MDM AssignedAccess configuration removed" "SUCCESS"
        }
        
        if (-not $existingConfig -and -not $mdmConfig) {
            Write-Log "No AssignedAccess configuration found to remove" "WARNING"
        }
        
    } catch {
        Write-Log "Error removing AssignedAccess: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Clear AppLocker policies
function Clear-AppLockerPolicies {
    Write-Log "Clearing AppLocker policies..."
    
    try {
        # Create an empty policy
        $emptyPolicy = @"
<AppLockerPolicy Version="1">
    <RuleCollection Type="Exe" EnforcementMode="NotConfigured" />
    <RuleCollection Type="Msi" EnforcementMode="NotConfigured" />
    <RuleCollection Type="Script" EnforcementMode="NotConfigured" />
    <RuleCollection Type="Dll" EnforcementMode="NotConfigured" />
    <RuleCollection Type="Appx" EnforcementMode="NotConfigured" />
</AppLockerPolicy>
"@
        
        # Save to temp file
        $tempPolicyFile = Join-Path $env:TEMP "EmptyAppLockerPolicy.xml"
        $emptyPolicy | Out-File -FilePath $tempPolicyFile -Encoding UTF8
        
        # Apply empty policy
        Set-AppLockerPolicy -XmlPolicy $tempPolicyFile -ErrorAction SilentlyContinue
        Remove-Item -Path $tempPolicyFile -Force -ErrorAction SilentlyContinue
        
        Write-Log "AppLocker policies cleared" "SUCCESS"
        
    } catch {
        Write-Log "Error clearing AppLocker: $($_.Exception.Message)" "WARNING"
    }
}

# Remove kiosk user account
function Remove-KioskUserAccount {
    param([string]$UserName)
    
    Write-Log "Removing kiosk user account '$UserName'..."
    
    try {
        $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
        
        if ($user) {
            # Check if user is currently logged in
            $loggedInUsers = query user 2>$null | Select-String $UserName
            if ($loggedInUsers) {
                Write-Log "User '$UserName' is currently logged in. Please log them out first." "ERROR"
                throw "Cannot remove user while they are logged in"
            }
            
            Remove-LocalUser -Name $UserName
            Write-Log "User account '$UserName' removed successfully" "SUCCESS"
        } else {
            Write-Log "User account '$UserName' not found" "WARNING"
        }
        
    } catch {
        Write-Log "Error removing user: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Stop Application Identity service (optional)
function Stop-AppIDService {
    Write-Log "Checking Application Identity service..."
    
    try {
        $appIdService = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        if ($appIdService -and $appIdService.Status -eq "Running") {
            Write-Log "Stopping Application Identity service..."
            Stop-Service -Name "AppIDSvc" -Force -ErrorAction SilentlyContinue
            
            # Set back to Manual startup
            Set-Service -Name "AppIDSvc" -StartupType Manual -ErrorAction SilentlyContinue
            Write-Log "Application Identity service stopped and set to Manual" "SUCCESS"
        }
    } catch {
        Write-Log "Error stopping AppIDSvc: $($_.Exception.Message)" "WARNING"
    }
}

# Main script
try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Kiosk Configuration Removal" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    Write-Log "=== Starting Kiosk Configuration Removal ==="
    
    # Confirm action
    Write-Host "This will remove the kiosk configuration and restore normal Windows access." -ForegroundColor Yellow
    if ($RemoveUser) {
        Write-Host "User account '$KioskUserName' will also be DELETED." -ForegroundColor Yellow
    }
    if ($ClearAppLocker) {
        Write-Host "AppLocker policies will be cleared." -ForegroundColor Yellow
    }
    
    $confirmation = Read-Host "`nAre you sure you want to continue? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Cancelled by user" -ForegroundColor Yellow
        exit 0
    }
    
    # Step 1: Remove AssignedAccess configuration
    Write-Host "`n[1/4] Removing AssignedAccess configuration..." -ForegroundColor Cyan
    Remove-AssignedAccessConfig
    
    # Step 2: Clear AppLocker policies (if requested)
    if ($ClearAppLocker) {
        Write-Host "`n[2/4] Clearing AppLocker policies..." -ForegroundColor Cyan
        Clear-AppLockerPolicies
    } else {
        Write-Host "`n[2/4] Skipping AppLocker removal (use -ClearAppLocker to remove)" -ForegroundColor Gray
    }
    
    # Step 3: Stop Application Identity service
    Write-Host "`n[3/4] Stopping Application Identity service..." -ForegroundColor Cyan
    Stop-AppIDService
    
    # Step 4: Remove user account (if requested)
    if ($RemoveUser) {
        Write-Host "`n[4/4] Removing kiosk user account..." -ForegroundColor Cyan
        Remove-KioskUserAccount -UserName $KioskUserName
    } else {
        Write-Host "`n[4/4] Keeping user account (use -RemoveUser to delete)" -ForegroundColor Gray
    }
    
    Write-Log "=== Kiosk Configuration Removal Completed ===" "SUCCESS"
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Removal Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  • AssignedAccess configuration removed" -ForegroundColor White
    if ($ClearAppLocker) {
        Write-Host "  • AppLocker policies cleared" -ForegroundColor White
    }
    if ($RemoveUser) {
        Write-Host "  • Kiosk user account deleted" -ForegroundColor White
    } else {
        Write-Host "  • Kiosk user account retained (can be removed manually)" -ForegroundColor White
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  • Restart the computer to ensure all changes take effect" -ForegroundColor White
    Write-Host "  • Normal Windows access should be restored" -ForegroundColor White
    
    if (-not $RemoveUser) {
        Write-Host "`nTo manually remove the user account later, run:" -ForegroundColor Yellow
        Write-Host "  Remove-LocalUser -Name '$KioskUserName'" -ForegroundColor Gray
    }
    
} catch {
    Write-Log "Removal failed: $($_.Exception.Message)" "ERROR"
    Write-Host "`n[ERROR] Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPartial removal may have occurred. Check the log file: $LogFile" -ForegroundColor Yellow
    exit 1
}
