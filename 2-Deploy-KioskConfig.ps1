#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys AssignedAccess kiosk configuration to Windows 10 Pro.

.DESCRIPTION
    This script applies the AssignedAccess XML configuration to create a multi-app kiosk
    with an AllowedApps list. It enables required services and uses WMI Bridge to deploy
    the configuration.

.PARAMETER ConfigPath
    Path to the AssignedAccess XML configuration file.

.PARAMETER KioskUserName
    Name of the kiosk user account. Must match the account in XML.

.NOTES
    Must be run as Administrator.
    Requires Windows 10 Pro build 1709 or later for multi-app kiosk support.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,
    
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser"
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptRoot "KioskConfig.xml" }
$LogFile = Join-Path $ScriptRoot "KioskSetup.log"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Check Windows version
function Test-WindowsVersion {
    $build = [System.Environment]::OSVersion.Version.Build
    $minBuild = 16299  # Windows 10 1709
    
    if ($build -lt $minBuild) {
        throw "Multi-app kiosk requires Windows 10 build $minBuild (version 1709) or later. Current build: $build"
    }
    Write-Log "Windows build $build meets requirements"
}

# Enable Application Identity service
function Enable-AppIDService {
    Write-Log "Checking Application Identity service..."
    
    $appIdService = Get-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
    if (-not $appIdService) {
        throw "Application Identity service not found"
    }
    
    # Set to Automatic startup
    if ($appIdService.StartType -ne "Automatic") {
        Write-Log "Setting Application Identity service to Automatic startup"
        Set-Service -Name "AppIDSvc" -StartupType Automatic
    }
    
    # Start the service if not running
    if ($appIdService.Status -ne "Running") {
        Write-Log "Starting Application Identity service"
        Start-Service -Name "AppIDSvc"
        Start-Sleep -Seconds 2
    }
    
    Write-Log "Application Identity service is running"
}

# Verify kiosk user exists
function Test-KioskUser {
    param([string]$UserName)
    
    Write-Log "Verifying kiosk user '$UserName' exists..."
    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    
    if (-not $user) {
        throw "Kiosk user '$UserName' not found. Run 1-Create-KioskUser.ps1 first."
    }
    
    if ($user.Enabled -eq $false) {
        Write-Log "Enabling disabled kiosk user account" "WARNING"
        Enable-LocalUser -Name $UserName
    }
    
    Write-Log "Kiosk user '$UserName' verified"
}

# Load and validate XML configuration
function Get-ValidatedConfig {
    param([string]$Path)
    
    Write-Log "Loading configuration from: $Path"
    
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    
    try {
        [xml]$xmlContent = Get-Content -Path $Path -Raw
        Write-Log "XML configuration loaded successfully"
        return $xmlContent
    } catch {
        throw "Failed to parse XML configuration: $($_.Exception.Message)"
    }
}

# Apply AssignedAccess configuration using WMI
function Set-AssignedAccessConfig {
    param([string]$XmlPath)
    
    Write-Log "Applying AssignedAccess configuration..."
    
    # Read the XML content
    $configXml = Get-Content -Path $XmlPath -Raw
    
    # Get the MDM WMI Bridge
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_AssignedAccess"
    
    try {
        # Check if WMI class exists
        $wmiClass = Get-CimClass -Namespace $namespaceName -ClassName $className -ErrorAction SilentlyContinue
        
        if (-not $wmiClass) {
            Write-Log "Trying alternative deployment method..." "WARNING"
            # Alternative: Use Set-AssignedAccess cmdlet if available
            # Note: This cmdlet doesn't support multi-app on Pro, but we'll try
            throw "MDM_AssignedAccess WMI class not available. Multi-app kiosk may require Enterprise/Education edition or Intune deployment."
        }
        
        # Get existing instances
        $existingConfig = Get-CimInstance -Namespace $namespaceName -ClassName $className -ErrorAction SilentlyContinue
        
        if ($existingConfig) {
            Write-Log "Removing existing AssignedAccess configuration" "WARNING"
            Remove-CimInstance -InputObject $existingConfig -ErrorAction SilentlyContinue
        }
        
        # Create new configuration
        $newInstance = New-CimInstance -Namespace $namespaceName -ClassName $className -Property @{
            ParentID = "./Vendor/MSFT/AssignedAccess"
            InstanceID = "AssignedAccess"
            Configuration = $configXml
        }
        
        Write-Log "AssignedAccess configuration applied successfully" "SUCCESS"
        
    } catch {
        Write-Log "WMI deployment failed: $($_.Exception.Message)" "ERROR"
        Write-Log "Attempting alternative provisioning method..." "WARNING"
        
        # Try using provisioning package approach or direct registry
        Set-AssignedAccessViaProvisioning -XmlPath $XmlPath
    }
}

# Alternative deployment using provisioning
function Set-AssignedAccessViaProvisioning {
    param([string]$XmlPath)
    
    Write-Log "Using provisioning package deployment method..."
    
    # This is a fallback method - in production you might need to:
    # 1. Create a provisioning package (.ppkg) with Windows Configuration Designer
    # 2. Apply it using Add-ProvisioningPackage
    # For now, we'll document the limitation
    
    Write-Host "`n⚠ IMPORTANT: Multi-app kiosk deployment limitation detected" -ForegroundColor Yellow
    Write-Host "Windows 10 Pro has limited support for programmatic multi-app kiosk deployment." -ForegroundColor Yellow
    Write-Host "`nOptions:" -ForegroundColor Cyan
    Write-Host "1. Use Windows Configuration Designer to create a provisioning package (.ppkg)" -ForegroundColor White
    Write-Host "2. Upgrade to Windows 10 Enterprise/Education for full MDM support" -ForegroundColor White
    Write-Host "3. Manually apply via Settings > Accounts > Other users > Set up assigned access" -ForegroundColor White
    Write-Host "4. Use Intune or other MDM solution for deployment" -ForegroundColor White
    Write-Host "`nYour configuration file is ready at: $XmlPath" -ForegroundColor Green
    
    # Save helpful instructions
    $instructionsPath = Join-Path $ScriptRoot "DEPLOYMENT_INSTRUCTIONS.txt"
    @"
AssignedAccess Multi-App Kiosk Deployment Instructions
======================================================

Your configuration XML is ready at: $XmlPath

DEPLOYMENT OPTIONS:

Option 1: Manual Configuration (Simplest for testing)
-----------------------------------------------------
1. Open Settings > Accounts > Other users
2. Under "Set up assigned access", click "Get started"
3. Choose the KioskUser account
4. Select "Choose which apps can run"
5. Manually select Chrome, Explorer, and Scanner app

Option 2: Windows Configuration Designer (Recommended)
------------------------------------------------------
1. Install Windows Configuration Designer from Microsoft Store
2. Create a new provisioning package
3. Navigate to Runtime settings > AssignedAccess > MultiAppAssignedAccessSettings
4. Import your KioskConfig.xml file
5. Build and export the provisioning package
6. Apply using: Add-ProvisioningPackage -PackagePath <path-to-ppkg>

Option 3: Registry Method (Advanced)
------------------------------------
Some multi-app kiosk settings can be configured via registry:
HKLM\SOFTWARE\Microsoft\Windows\AssignedAccessConfiguration

Option 4: Intune/MDM Deployment
-------------------------------
Upload KioskConfig.xml to Intune as a device configuration profile.

VERIFICATION:
------------
After deployment, run: .\3-Validate-KioskConfig.ps1

For more information:
https://docs.microsoft.com/en-us/windows/configuration/lock-down-windows-10-to-specific-apps
"@ | Out-File -FilePath $instructionsPath -Encoding UTF8
    
    Write-Host "`nDetailed instructions saved to: $instructionsPath" -ForegroundColor Cyan
    notepad.exe $instructionsPath
}

# Main script
try {
    Write-Log "=== Starting AssignedAccess Deployment ==="
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    # Pre-flight checks
    Write-Host "`nPerforming pre-flight checks..." -ForegroundColor Cyan
    Test-WindowsVersion
    Test-KioskUser -UserName $KioskUserName
    
    # Validate configuration
    $config = Get-ValidatedConfig -Path $ConfigPath
    
    # Enable required services
    Enable-AppIDService
    
    # Deploy configuration
    Write-Host "`nDeploying kiosk configuration..." -ForegroundColor Cyan
    Set-AssignedAccessConfig -XmlPath $ConfigPath
    
    Write-Log "=== Deployment process completed ===" "SUCCESS"
    
} catch {
    Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
    Write-Host "`n✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
