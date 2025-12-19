# Windows 10 Pro Kiosk Mode Setup

Automated PowerShell scripts for configuring Windows 10 Pro in kiosk mode with restricted access to Chrome browser and a check scanner application using AssignedAccess and AllowedApps list.

## Overview

This solution creates a locked-down Windows 10 Pro environment where users can only access:
- Google Chrome browser
- Check scanner application
- Windows File Explorer (restricted to specific folders)

The configuration uses Windows AssignedAccess with multi-app kiosk mode, which automatically generates AppLocker policies to enforce application restrictions.

## Requirements

- **Windows 10 Pro** version 1709 (build 16299) or later
- **Administrator privileges** on the local machine
- **PowerShell 5.1** or later
- Google Chrome installed (or will be installed)
- Check scanner application installed

## Quick Start

### Option 1: Automated Deployment (Recommended)

Run the master deployment script as Administrator:

```powershell
.\Deploy-KioskMode.ps1
```

This will:
1. Perform pre-flight checks
2. Prompt for scanner app path
3. Create kiosk user account
4. Deploy AssignedAccess configuration
5. Validate the setup

### Option 2: Step-by-Step Manual Deployment

1. **Create Kiosk User Account**
   ```powershell
   .\1-Create-KioskUser.ps1
   ```
   Creates a restricted local user account named "KioskUser"

2. **Edit Configuration File**
   
   Open `KioskConfig.xml` and update the scanner app path:
   ```xml
   <App DesktopAppPath="C:\Path\To\Your\ScannerApp.exe" />
   ```

3. **Deploy Configuration**
   ```powershell
   .\2-Deploy-KioskConfig.ps1
   ```
   Applies the AssignedAccess configuration

4. **Validate Setup**
   ```powershell
   .\3-Validate-KioskConfig.ps1
   ```
   Verifies the configuration was applied correctly

## Files Included

| File | Description |
|------|-------------|
| `Deploy-KioskMode.ps1` | Master orchestrator script |
| `1-Create-KioskUser.ps1` | Creates the kiosk user account |
| `2-Deploy-KioskConfig.ps1` | Deploys AssignedAccess configuration |
| `3-Validate-KioskConfig.ps1` | Validates the kiosk setup |
| `4-Remove-KioskConfig.ps1` | Removes kiosk configuration (rollback) |
| `KioskConfig.xml` | AssignedAccess configuration file |
| `README.md` | This file |

## Configuration

### Customizing Allowed Applications

Edit `KioskConfig.xml` to add or remove allowed applications:

```xml
<AllowedApps>
    <!-- Chrome -->
    <App DesktopAppPath="%ProgramFiles%\Google\Chrome\Application\chrome.exe" />
    
    <!-- Your scanner app -->
    <App DesktopAppPath="C:\Program Files\ScannerApp\scanner.exe" />
    
    <!-- Add more apps as needed -->
    <App DesktopAppPath="%windir%\system32\notepad.exe" />
</AllowedApps>
```

### Customizing File Access

Modify the File Explorer restrictions in `KioskConfig.xml`:

```xml
<rs5:FileExplorerNamespaceRestrictions>
    <v5:AllowedNamespace Name="Downloads"/>
    <v5:AllowedNamespace Name="Documents"/>
    <!-- Add more folders as needed -->
</rs5:FileExplorerNamespaceRestrictions>
```

Available namespace options:
- `Downloads`
- `Documents`
- `Pictures`
- `Desktop`
- `Music`
- `Videos`

### Changing the Kiosk User Name

To use a different username:

```powershell
.\Deploy-KioskMode.ps1 -KioskUserName "CustomUser"
```

Or edit all scripts and XML to replace "KioskUser" with your preferred name.

## Testing

1. **Sign out** from your current Windows session
2. **Log in** as the kiosk user (default: "KioskUser")
3. Verify that:
   - Only Chrome, Scanner app, and File Explorer are accessible
   - Start menu only shows allowed applications
   - File Explorer only shows allowed folders
   - System settings and Control Panel are inaccessible
   - Task Manager and other system tools are blocked

## Troubleshooting

### Multi-App Kiosk Not Working

**Issue**: Windows 10 Pro has limited support for programmatic multi-app kiosk deployment.

**Solutions**:
1. **Manual Configuration** (Recommended for Windows 10 Pro):
   - Open Settings > Accounts > Other users
   - Under "Set up assigned access", click "Get started"
   - Choose the KioskUser account
   - Select apps manually

2. **Windows Configuration Designer**:
   - Install from Microsoft Store
   - Create provisioning package with `KioskConfig.xml`
   - Apply the package

3. **Upgrade to Windows 10 Enterprise/Education** for full MDM support

### Application Identity Service Not Running

```powershell
Start-Service -Name AppIDSvc
Set-Service -Name AppIDSvc -StartupType Automatic
```

### Chrome Not Found

Install Google Chrome before deploying:
```powershell
# Download and install Chrome manually, or use:
# winget install Google.Chrome
```

### Scanner App Path Issues

Ensure the path in `KioskConfig.xml` matches the actual installation location:
```powershell
# Find the scanner app
Get-ChildItem "C:\Program Files" -Recurse -Filter "scanner*.exe"
```

## Removing Kiosk Mode

### Option 1: Keep User Account

```powershell
.\4-Remove-KioskConfig.ps1
```

### Option 2: Remove Everything

```powershell
.\4-Remove-KioskConfig.ps1 -RemoveUser -ClearAppLocker
```

After removal, **restart the computer** to ensure all changes take effect.

## Important Notes

### Windows 10 Pro Limitations

- **Multi-app kiosk** programmatic deployment has limited support on Windows 10 Pro
- May require **manual configuration** via Settings app
- **Enterprise/Education editions** have better MDM support
- Consider using **Windows Configuration Designer** for provisioning packages

### Security Considerations

- The kiosk user has **standard user privileges** (not administrator)
- AppLocker policies prevent running unauthorized applications
- File Explorer access is restricted to specific folders
- System settings and administrative tools are blocked
- Consider additional network restrictions if needed

### Maintenance

- **Windows Updates**: The kiosk user cannot install updates; manage from admin account
- **Application Updates**: Chrome and scanner app updates require admin privileges
- **Monitoring**: Check `KioskSetup.log` for deployment and operation logs
- **Backup**: Keep a copy of `KioskConfig.xml` for disaster recovery

## Advanced Usage

### Custom Start Menu Layout

Export your current Start menu layout:
```powershell
Export-StartLayout -Path C:\StartLayout.xml
```

Include it in `KioskConfig.xml`:
```xml
<StartLayout>
    <![CDATA[
        <!-- Paste exported layout here -->
    ]]>
</StartLayout>
```

### Auto-Login Configuration

For full kiosk experience, configure auto-login:

```xml
<Configs>
    <Config>
        <AutoLogonAccount>KioskUser</AutoLogonAccount>
        <DefaultProfile Id="{GUID}"/>
    </Config>
</Configs>
```

**Warning**: This removes login security. Only use in controlled environments.

### Chrome Kiosk Mode

Launch Chrome in kiosk mode with a specific URL by creating a shortcut or startup script:

```powershell
# Create startup script for kiosk user
$startupScript = @"
Start-Process "chrome.exe" -ArgumentList "--kiosk https://yourwebapp.com"
"@

# Save to kiosk user's startup folder
# Requires customization based on your needs
```

## Support and Documentation

### Log Files

All operations are logged to `KioskSetup.log` in the script directory.

### Microsoft Documentation

- [Set up a multi-app kiosk](https://docs.microsoft.com/en-us/windows/configuration/lock-down-windows-10-to-specific-apps)
- [AssignedAccess CSP](https://docs.microsoft.com/en-us/windows/client-management/mdm/assignedaccess-csp)
- [AppLocker Overview](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-defender-application-control/applocker/applocker-overview)

### Script Parameters

All scripts support `-Help` for detailed parameter information:

```powershell
Get-Help .\Deploy-KioskMode.ps1 -Detailed
```

## License

These scripts are provided as-is for educational and deployment purposes.

## Version History

- **v1.0** - Initial release with AssignedAccess multi-app kiosk support
  - User creation
  - XML configuration
  - Deployment automation
  - Validation and rollback scripts

## Author

Created for Windows 10 Pro kiosk mode deployment with Chrome and scanner application access.
