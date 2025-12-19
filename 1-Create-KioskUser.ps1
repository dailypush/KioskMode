#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a local kiosk user account for Windows 10 Pro kiosk mode.

.DESCRIPTION
    This script creates a restricted local user account that will be used for kiosk mode.
    The account is created as a standard user (non-administrator) with a password.

.NOTES
    Must be run as Administrator.
    Compatible with Windows 10 Pro.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser",
    
    [Parameter(Mandatory=$false)]
    [string]$KioskUserFullName = "Kiosk Mode User",
    
    [Parameter(Mandatory=$false)]
    [string]$KioskUserDescription = "Restricted kiosk account for Chrome and Scanner",
    
    [Parameter(Mandatory=$false)]
    [SecureString]$Password
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
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Main script
try {
    Write-Log "Starting kiosk user creation process..."
    
    # Check if script is running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    # Check if user already exists
    $existingUser = Get-LocalUser -Name $KioskUserName -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Log "User '$KioskUserName' already exists. Skipping creation." "WARNING"
        Write-Host "`nUser already exists. If you want to recreate it, delete it first using:" -ForegroundColor Yellow
        Write-Host "Remove-LocalUser -Name '$KioskUserName'" -ForegroundColor Yellow
        exit 0
    }
    
    # Get password if not provided
    if (-not $Password) {
        Write-Host "`nEnter password for kiosk user '$KioskUserName':" -ForegroundColor Cyan
        $Password = Read-Host -AsSecureString
        Write-Host "Confirm password:" -ForegroundColor Cyan
        $PasswordConfirm = Read-Host -AsSecureString
        
        # Convert to plain text for comparison
        $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordConfirm)
        $PlainPassword1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
        $PlainPassword2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
        
        if ($PlainPassword1 -ne $PlainPassword2) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
            throw "Passwords do not match"
        }
        
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR2)
    }
    
    # Create the local user account
    Write-Log "Creating local user account: $KioskUserName"
    $newUser = New-LocalUser -Name $KioskUserName `
                            -Password $Password `
                            -FullName $KioskUserFullName `
                            -Description $KioskUserDescription `
                            -PasswordNeverExpires `
                            -UserMayNotChangePassword
    
    Write-Log "User '$KioskUserName' created successfully"
    
    # Verify the user is not in Administrators group
    $adminGroup = Get-LocalGroup -Name "Administrators"
    $adminMembers = Get-LocalGroupMember -Group $adminGroup
    if ($adminMembers.Name -contains "$env:COMPUTERNAME\$KioskUserName") {
        Write-Log "Removing '$KioskUserName' from Administrators group" "WARNING"
        Remove-LocalGroupMember -Group "Administrators" -Member $KioskUserName -ErrorAction SilentlyContinue
    }
    
    # Ensure user is in Users group
    $usersGroup = Get-LocalGroup -Name "Users"
    $usersMembers = Get-LocalGroupMember -Group $usersGroup
    if ($usersMembers.Name -notcontains "$env:COMPUTERNAME\$KioskUserName") {
        Write-Log "Adding '$KioskUserName' to Users group"
        Add-LocalGroupMember -Group "Users" -Member $KioskUserName
    }
    
    Write-Log "User account setup completed successfully" "SUCCESS"
    Write-Host "`n[SUCCESS] Kiosk user account created successfully!" -ForegroundColor Green
    Write-Host "  Username: $KioskUserName" -ForegroundColor Cyan
    Write-Host "  Full Name: $KioskUserFullName" -ForegroundColor Cyan
    Write-Host "  Group: Users (Standard User)" -ForegroundColor Cyan
    Write-Host "`nNext step: Configure AssignedAccess XML and deploy configuration" -ForegroundColor Yellow
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Host "`n[ERROR] Error creating kiosk user: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
