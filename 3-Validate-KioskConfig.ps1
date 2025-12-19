#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Validates the AssignedAccess kiosk configuration.

.DESCRIPTION
    This script checks if the kiosk configuration was applied correctly by:
    - Verifying AssignedAccess configuration exists
    - Checking AppLocker policies were generated
    - Testing Application Identity service status
    - Providing diagnostic information

.NOTES
    Must be run as Administrator.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser"
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$LogFile = Join-Path $ScriptRoot "KioskSetup.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Color-coded output
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Pass", "Fail", "Warning", "Info")]
        [string]$Status
    )
    
    $symbol = switch ($Status) {
        "Pass"    { "[PASS]"; $color = "Green" }
        "Fail"    { "[FAIL]"; $color = "Red" }
        "Warning" { "[WARN]"; $color = "Yellow" }
        "Info"    { "[INFO]"; $color = "Cyan" }
    }
    
    Write-Host "$symbol $Message" -ForegroundColor $color
    Write-Log "$Status : $Message"
}

# Main validation
try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Kiosk Configuration Validation" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $allPassed = $true
    
    # 1. Check Administrator privileges
    Write-Host "[1] Administrator Privileges" -ForegroundColor Yellow
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Status "Running as Administrator" -Status Pass
    } else {
        Write-Status "Not running as Administrator" -Status Fail
        $allPassed = $false
    }
    
    # 2. Check kiosk user account
    Write-Host "`n[2] Kiosk User Account" -ForegroundColor Yellow
    $kioskUser = Get-LocalUser -Name $KioskUserName -ErrorAction SilentlyContinue
    if ($kioskUser) {
        Write-Status "User '$KioskUserName' exists" -Status Pass
        if ($kioskUser.Enabled) {
            Write-Status "User account is enabled" -Status Pass
        } else {
            Write-Status "User account is disabled" -Status Fail
            $allPassed = $false
        }
    } else {
        Write-Status "User '$KioskUserName' not found" -Status Fail
        $allPassed = $false
    }
    
    # 3. Check Application Identity service
    Write-Host "`n[3] Application Identity Service" -ForegroundColor Yellow
    $appIdService = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if ($appIdService) {
        if ($appIdService.Status -eq "Running") {
            Write-Status "AppIDSvc is running" -Status Pass
        } else {
            Write-Status "AppIDSvc is not running (Status: $($appIdService.Status))" -Status Fail
            $allPassed = $false
        }
        
        if ($appIdService.StartType -eq "Automatic") {
            Write-Status "AppIDSvc set to Automatic startup" -Status Pass
        } else {
            Write-Status "AppIDSvc not set to Automatic (Type: $($appIdService.StartType))" -Status Warning
        }
    } else {
        Write-Status "Application Identity service not found" -Status Fail
        $allPassed = $false
    }
    
    # 4. Check for AssignedAccess configuration
    Write-Host "`n[4] AssignedAccess Configuration" -ForegroundColor Yellow
    try {
        # Try to get configuration using Get-AssignedAccess cmdlet
        $assignedAccess = Get-AssignedAccess -ErrorAction SilentlyContinue
        if ($assignedAccess) {
            Write-Status "AssignedAccess configuration found" -Status Pass
            Write-Host "   User: $($assignedAccess.User)" -ForegroundColor Gray
            if ($assignedAccess.AppUserModelId) {
                Write-Host "   App: $($assignedAccess.AppUserModelId)" -ForegroundColor Gray
            }
        } else {
            Write-Status "No AssignedAccess configuration found" -Status Warning
            Write-Status "Multi-app kiosk may not be detected by Get-AssignedAccess cmdlet" -Status Info
        }
        
        # Check WMI/MDM configuration
        $namespaceName = "root\cimv2\mdm\dmmap"
        $className = "MDM_AssignedAccess"
        $mdmConfig = Get-CimInstance -Namespace $namespaceName -ClassName $className -ErrorAction SilentlyContinue
        
        if ($mdmConfig) {
            Write-Status "MDM AssignedAccess configuration found" -Status Pass
        } else {
            Write-Status "MDM AssignedAccess configuration not found" -Status Info
            Write-Status "Multi-app kiosk may require manual configuration" -Status Info
        }
        
    } catch {
        Write-Status "Error checking AssignedAccess: $($_.Exception.Message)" -Status Warning
    }
    
    # 5. Check AppLocker policies
    Write-Host "`n[5] AppLocker Policies" -ForegroundColor Yellow
    try {
        $applockerPolicy = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
        
        if ($applockerPolicy) {
            $ruleCollections = $applockerPolicy.RuleCollections
            $totalRules = 0
            
            foreach ($collection in $ruleCollections) {
                $ruleCount = ($collection | Measure-Object).Count
                if ($ruleCount -gt 0) {
                    $totalRules += $ruleCount
                    Write-Host "   $($collection.RuleCollectionType): $ruleCount rules" -ForegroundColor Gray
                }
            }
            
            if ($totalRules -gt 0) {
                Write-Status "AppLocker policies active ($totalRules total rules)" -Status Pass
            } else {
                Write-Status "AppLocker policies exist but no rules found" -Status Warning
            }
        } else {
            Write-Status "No AppLocker policies found" -Status Warning
            Write-Status "Policies may be configured but not yet effective" -Status Info
        }
        
    } catch {
        Write-Status "Error checking AppLocker: $($_.Exception.Message)" -Status Warning
    }
    
    # 6. Check for common kiosk applications
    Write-Host "`n[6] Application Availability" -ForegroundColor Yellow
    
    # Check Chrome
    $chromePaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    
    $chromeFound = $false
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            Write-Status "Chrome found: $path" -Status Pass
            $chromeFound = $true
            break
        }
    }
    
    if (-not $chromeFound) {
        Write-Status "Chrome not found in standard locations" -Status Warning
        Write-Status "Install Chrome or update XML configuration with correct path" -Status Info
    }
    
    # Check for scanner app (generic check)
    Write-Status "Scanner app: Verify manually in XML configuration" -Status Info
    
    # 7. Configuration files
    Write-Host "`n[7] Configuration Files" -ForegroundColor Yellow
    $configPath = Join-Path $ScriptRoot "KioskConfig.xml"
    if (Test-Path $configPath) {
        Write-Status "KioskConfig.xml exists" -Status Pass
    } else {
        Write-Status "KioskConfig.xml not found" -Status Fail
        $allPassed = $false
    }
    
    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    if ($allPassed) {
        Write-Host "[SUCCESS] All critical checks passed!" -ForegroundColor Green
        Write-Host "`nNext Steps:" -ForegroundColor Cyan
        Write-Host "1. Sign out and log in as '$KioskUserName' to test kiosk mode" -ForegroundColor White
        Write-Host "2. Verify only allowed apps are accessible" -ForegroundColor White
        Write-Host "3. Test Chrome and Scanner app functionality" -ForegroundColor White
    } else {
        Write-Host "[ERROR] Some critical checks failed!" -ForegroundColor Red
        Write-Host "`nReview the errors above and:" -ForegroundColor Yellow
        Write-Host "1. Re-run .\1-Create-KioskUser.ps1 if user is missing" -ForegroundColor White
        Write-Host "2. Re-run .\2-Deploy-KioskConfig.ps1 to apply configuration" -ForegroundColor White
        Write-Host "3. Check the log file: $LogFile" -ForegroundColor White
    }
    
    # Additional diagnostic info
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Diagnostic Information" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Computer Name: $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "Windows Version: $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
    Write-Host "Build: $([System.Environment]::OSVersion.Version.Build)" -ForegroundColor Gray
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "Log File: $LogFile`n" -ForegroundColor Gray
    
} catch {
    Write-Host "`n[ERROR] Validation error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "Validation error: $($_.Exception.Message)" "ERROR"
    exit 1
}
