#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Master deployment script for Windows 10 Pro Kiosk Mode setup.

.DESCRIPTION
    Orchestrates the complete kiosk mode deployment process:
    1. Creates kiosk user account
    2. Validates configuration files
    3. Deploys AssignedAccess configuration
    4. Validates deployment
    5. Provides next steps and documentation

.PARAMETER KioskUserName
    Name for the kiosk user account (default: KioskUser)

.PARAMETER ScannerAppPath
    Full path to the scanner application executable

.PARAMETER SkipUserCreation
    Skip user creation if account already exists

.PARAMETER AutomaticMode
    Run without interactive prompts (use defaults)

.NOTES
    Must be run as Administrator on Windows 10 Pro.
    
.EXAMPLE
    .\Deploy-KioskMode.ps1
    
.EXAMPLE
    .\Deploy-KioskMode.ps1 -KioskUserName "CheckScanner" -ScannerAppPath "C:\Scanner\app.exe"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser",
    
    [Parameter(Mandatory=$false)]
    [string]$ScannerAppPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipUserCreation,
    
    [Parameter(Mandatory=$false)]
    [switch]$AutomaticMode
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot
$LogFile = Join-Path $ScriptRoot "KioskSetup.log"

# Color scheme
$ColorHeader = "Cyan"
$ColorSuccess = "Green"
$ColorError = "Red"
$ColorWarning = "Yellow"
$ColorInfo = "White"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

# Header display
function Show-Header {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor $ColorHeader
    Write-Host $Title -ForegroundColor $ColorHeader
    Write-Host "========================================`n" -ForegroundColor $ColorHeader
}

# Step display
function Show-Step {
    param([int]$Number, [int]$Total, [string]$Description)
    Write-Host "[$Number/$Total] $Description..." -ForegroundColor $ColorHeader
}

# Pre-flight checks
function Test-Prerequisites {
    Write-Log "Performing pre-flight checks..."
    
    # Check Administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    Write-Host "  [OK] Running as Administrator" -ForegroundColor $ColorSuccess
    
    # Check Windows version
    $build = [System.Environment]::OSVersion.Version.Build
    $minBuild = 16299  # Windows 10 1709
    if ($build -lt $minBuild) {
        throw "Multi-app kiosk requires Windows 10 build $minBuild (version 1709) or later. Current: $build"
    }
    Write-Host "  [OK] Windows 10 build $build (meets requirements)" -ForegroundColor $ColorSuccess
    
    # Check required files
    $requiredFiles = @(
        "1-Create-KioskUser.ps1",
        "2-Deploy-KioskConfig.ps1",
        "3-Validate-KioskConfig.ps1",
        "4-Remove-KioskConfig.ps1",
        "5-Create-LogoffShortcut.ps1",
        "KioskConfig.xml"
    )
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $ScriptRoot $file
        if (-not (Test-Path $filePath)) {
            throw "Required file not found: $file"
        }
    }
    Write-Host "  [OK] All required files present" -ForegroundColor $ColorSuccess
    
    Write-Log "Pre-flight checks passed"
}

# Update XML configuration with scanner app path
function Update-XMLConfiguration {
    param([string]$ScannerPath)
    
    if (-not $ScannerPath) {
        return
    }
    
    Write-Log "Updating XML configuration with scanner app path: $ScannerPath"
    
    $xmlPath = Join-Path $ScriptRoot "KioskConfig.xml"
    
    try {
        # Read XML as text and replace the placeholder path
        $xmlContent = Get-Content -Path $xmlPath -Raw -Encoding UTF8
        $placeholderPath = "C:\Program Files\ScannerApp\scanner.exe"
        
        # Escape backslashes for replacement
        $escapedPlaceholder = [regex]::Escape($placeholderPath)
        
        if ($xmlContent -match $escapedPlaceholder) {
            $xmlContent = $xmlContent -replace $escapedPlaceholder, [regex]::Escape($ScannerPath)
            $xmlContent | Out-File -FilePath $xmlPath -Encoding UTF8 -NoNewline
            Write-Host "  [OK] XML configuration updated with scanner path" -ForegroundColor $ColorSuccess
            Write-Log "XML updated successfully"
        } else {
            Write-Host "  [WARN] Scanner placeholder not found in XML. Update KioskConfig.xml manually." -ForegroundColor $ColorWarning
            Write-Log "Scanner placeholder not found in XML" "WARNING"
        }
    } catch {
        Write-Host "  [ERROR] Failed to update XML: $($_.Exception.Message)" -ForegroundColor $ColorError
        Write-Log "XML update error: $($_.Exception.Message)" "ERROR"
    }
}

# Main deployment orchestration
try {
    # Display banner
    Clear-Host
    Show-Header "Windows 10 Pro Kiosk Mode Deployment"
    
    Write-Host "This script will set up a kiosk mode environment with:" -ForegroundColor $ColorInfo
    Write-Host "  - Restricted user account: $KioskUserName" -ForegroundColor $ColorInfo
    Write-Host "  - Allowed apps: Chrome, Scanner app, File Explorer" -ForegroundColor $ColorInfo
    Write-Host "  - AppLocker policies for application restriction" -ForegroundColor $ColorInfo
    
    if (-not $AutomaticMode) {
        Write-Host "`nPress Enter to continue or Ctrl+C to cancel..." -ForegroundColor $ColorWarning
        Read-Host
    }
    
    Write-Log "=== Kiosk Mode Deployment Started ==="
    Write-Log "User: $KioskUserName"
    if ($ScannerAppPath) {
        Write-Log "Scanner App: $ScannerAppPath"
    }
    
    # STEP 0: Pre-flight checks
    Show-Header "Step 0: Pre-flight Checks"
    Test-Prerequisites
    
    # STEP 1: Gather scanner app information
    if (-not $ScannerAppPath) {
        Show-Header "Step 1: Scanner Application Configuration"
        
        Write-Host "Please provide the full path to your check scanner application executable." -ForegroundColor $ColorInfo
        Write-Host "Example: C:\Program Files\ScannerApp\scanner.exe`n" -ForegroundColor Gray
        
        if (-not $AutomaticMode) {
            $ScannerAppPath = Read-Host "Scanner app path (or press Enter to configure later)"
            
            if ($ScannerAppPath -and (Test-Path $ScannerAppPath)) {
                Write-Host "  [OK] Scanner app found: $ScannerAppPath" -ForegroundColor $ColorSuccess
            } elseif ($ScannerAppPath) {
                Write-Host "  [WARN] Scanner app not found at specified path" -ForegroundColor $ColorWarning
                Write-Host "  You can update KioskConfig.xml manually later" -ForegroundColor $ColorWarning
            } else {
                Write-Host "  [INFO] Scanner app will need to be configured manually in KioskConfig.xml" -ForegroundColor $ColorInfo
            }
        }
    }
    
    # Update XML if scanner path provided
    if ($ScannerAppPath) {
        Update-XMLConfiguration -ScannerPath $ScannerAppPath
    }
    
    # STEP 2: Create kiosk user
    if (-not $SkipUserCreation) {
        Show-Header "Step 2: Create Kiosk User Account"
        
        $existingUser = Get-LocalUser -Name $KioskUserName -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Host "  [INFO] User '$KioskUserName' already exists. Skipping creation." -ForegroundColor $ColorInfo
            Write-Log "User already exists, skipping creation"
        } else {
            Write-Host "Creating user account '$KioskUserName'..." -ForegroundColor $ColorInfo
            
            # Call user creation script
            $userScript = Join-Path $ScriptRoot "1-Create-KioskUser.ps1"
            & $userScript -KioskUserName $KioskUserName
            
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                throw "User creation failed with exit code $LASTEXITCODE"
            }
            
            Write-Host "  [OK] User account created successfully" -ForegroundColor $ColorSuccess
        }
    } else {
        Write-Host "`nStep 2: Skipped (user creation)" -ForegroundColor Gray
    }
    
    # STEP 3: Deploy configuration
    Show-Header "Step 3: Deploy AssignedAccess Configuration"
    Write-Host "Deploying kiosk configuration..." -ForegroundColor $ColorInfo
    
    $deployScript = Join-Path $ScriptRoot "2-Deploy-KioskConfig.ps1"
    & $deployScript -KioskUserName $KioskUserName
    
    Write-Host "  [OK] Configuration deployment completed" -ForegroundColor $ColorSuccess
    
    # STEP 3.5: Create Logoff Shortcut
    Show-Header "Step 3.5: Create Logoff Shortcut"
    Write-Host "Creating logoff shortcut for usability..." -ForegroundColor $ColorInfo
    
    $shortcutScript = Join-Path $ScriptRoot "5-Create-LogoffShortcut.ps1"
    & $shortcutScript -KioskUserName $KioskUserName
    
    # STEP 4: Validation
    Show-Header "Step 4: Validate Configuration"
    Write-Host "Validating kiosk setup..." -ForegroundColor $ColorInfo
    
    $validateScript = Join-Path $ScriptRoot "3-Validate-KioskConfig.ps1"
    & $validateScript -KioskUserName $KioskUserName
    
    # STEP 5: Summary and next steps
    Show-Header "[SUCCESS] Deployment Complete!"
    
    Write-Host "Kiosk mode has been configured successfully!`n" -ForegroundColor $ColorSuccess
    
    Write-Host "Configuration Summary:" -ForegroundColor $ColorHeader
    Write-Host "  - Kiosk User: $KioskUserName" -ForegroundColor $ColorInfo
    Write-Host "  - Allowed Apps: Chrome, Scanner app, File Explorer" -ForegroundColor $ColorInfo
    Write-Host "  - File Access: Downloads folder (configurable in XML)" -ForegroundColor $ColorInfo
    Write-Host "  - Log File: $LogFile" -ForegroundColor $ColorInfo
    
    Write-Host "`nNext Steps:" -ForegroundColor $ColorHeader
    Write-Host "  1. Review KioskConfig.xml and update scanner app path if needed" -ForegroundColor $ColorInfo
    Write-Host "  2. Install Chrome browser if not already installed" -ForegroundColor $ColorInfo
    Write-Host "  3. Install scanner application software" -ForegroundColor $ColorInfo
    Write-Host "  4. Sign out and log in as '$KioskUserName' to test kiosk mode" -ForegroundColor $ColorInfo
    Write-Host "  5. Verify only allowed applications are accessible" -ForegroundColor $ColorInfo
    
    Write-Host "`nImportant Notes:" -ForegroundColor $ColorWarning
    Write-Host "  - Windows 10 Pro has limited programmatic multi-app kiosk deployment" -ForegroundColor $ColorWarning
    Write-Host "  - You may need to configure via Settings > Accounts > Assigned Access" -ForegroundColor $ColorWarning
    Write-Host "  - See DEPLOYMENT_INSTRUCTIONS.txt for alternative deployment methods" -ForegroundColor $ColorWarning
    
    Write-Host "`nUseful Commands:" -ForegroundColor $ColorHeader
    Write-Host "  Validate config:  .\3-Validate-KioskConfig.ps1" -ForegroundColor Gray
    Write-Host "  Remove kiosk:     .\4-Remove-KioskConfig.ps1" -ForegroundColor Gray
    Write-Host "  Remove with user: .\4-Remove-KioskConfig.ps1 -RemoveUser" -ForegroundColor Gray
    
    Write-Log "=== Deployment Completed Successfully ==="
    
} catch {
    Show-Header "[ERROR] Deployment Failed"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor $ColorError
    Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
    
    Write-Host "`nTroubleshooting:" -ForegroundColor $ColorWarning
    Write-Host "  - Check the log file: $LogFile" -ForegroundColor $ColorInfo
    Write-Host "  - Ensure you're running as Administrator" -ForegroundColor $ColorInfo
    Write-Host "  - Verify Windows 10 Pro version 1709 or later" -ForegroundColor $ColorInfo
    Write-Host "  - Run individual scripts manually to isolate the issue" -ForegroundColor $ColorInfo
    
    exit 1
}
