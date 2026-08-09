<#
.SYNOPSIS
    Installs IIS (Web-Server role) with common management tools and
    drops a simple landing page so you can verify the deployment.
#>

# Install IIS and management tools
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# Optional: common IIS sub-features (ASP.NET, static content, etc.)
Install-WindowsFeature -Name Web-Asp-Net45, Web-Net-Ext45, Web-Static-Content, Web-Http-Redirect -IncludeAllSubFeature

# Install the IIS URL Rewrite module — required so web.config can redirect
# unmatched routes to index.html for Angular's client-side router.
$rewriteMsiUrl  = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
$rewriteMsiPath = "C:\rewrite_amd64_en-US.msi"

Write-Output "Installing IIS URL Rewrite module..."
Invoke-WebRequest -Uri $rewriteMsiUrl -OutFile $rewriteMsiPath -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$rewriteMsiPath`" /qn /norestart" -Wait
Remove-Item $rewriteMsiPath -Force

# Write a simple verification page
$html = @"
<html>
<head><title>IIS Deployed via Terraform</title></head>
<body>
<h1>IIS installed successfully via Custom Script Extension</h1>
<p>Server name: $env:COMPUTERNAME</p>
<p>Deployed: $(Get-Date)</p>
</body>
</html>
"@

Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

# Make sure the World Wide Web Publishing Service is running and set to auto-start
Set-Service -Name W3SVC -StartupType Automatic
Start-Service -Name W3SVC
