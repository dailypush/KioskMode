#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a Logoff shortcut for the kiosk user.

.DESCRIPTION
    This script creates a "Logoff" shortcut on the Public Desktop or the Kiosk User's Desktop.
    This allows the user to sign out easily since the Start menu is restricted.

.PARAMETER KioskUserName
    Name of the kiosk user account.

.NOTES
    Must be run as Administrator.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KioskUserName = "KioskUser"
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "Creating Logoff shortcut..." -ForegroundColor Cyan
    
    # Define shortcut properties
    $targetPath = "$env:SystemRoot\System32\shutdown.exe"
    $arguments = "/l"
    $iconPath = "$env:SystemRoot\System32\shell32.dll"
    $iconIndex = 27 # Standard shutdown/logoff icon
    
    # Determine location: Public Desktop (visible to all) or User Desktop
    # Using Public Desktop ensures it's visible even if the user profile isn't fully created yet
    $shortcutPath = "$env:PUBLIC\Desktop\Logoff.lnk"
    
    # Create the shortcut
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = $arguments
    $shortcut.IconLocation = "$iconPath,$iconIndex"
    $shortcut.Description = "Sign out of Kiosk Mode"
    $shortcut.Save()
    
    Write-Host "  [OK] Logoff shortcut created at: $shortcutPath" -ForegroundColor Green
    
    # Also try to copy to user's desktop if profile exists
    $userProfile = "$env:SystemDrive\Users\$KioskUserName"
    if (Test-Path $userProfile) {
        $userDesktop = Join-Path $userProfile "Desktop"
        if (Test-Path $userDesktop) {
            Copy-Item -Path $shortcutPath -Destination $userDesktop -Force
            Write-Host "  [OK] Copied to user desktop: $userDesktop" -ForegroundColor Green
        }
    }
    
} catch {
    Write-Host "  [ERROR] Failed to create shortcut: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
