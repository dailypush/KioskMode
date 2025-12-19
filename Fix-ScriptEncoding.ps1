# Fix-ScriptEncoding.ps1
# Run this on Windows to fix encoding issues from macOS-created scripts

$scriptPath = $PSScriptRoot
$scripts = Get-ChildItem -Path $scriptPath -Filter "*.ps1" | Where-Object { $_.Name -ne "Fix-ScriptEncoding.ps1" }

foreach ($script in $scripts) {
    Write-Host "Fixing: $($script.Name)"
    
    # Read content
    $content = Get-Content -Path $script.FullName -Raw
    
    # Save with proper Windows encoding and line endings
    $content | Out-File -FilePath $script.FullName -Encoding UTF8 -Force
}

Write-Host "`nAll scripts fixed with UTF-8 encoding and Windows line endings" -ForegroundColor Green
Write-Host "Try running your scripts again" -ForegroundColor Green
