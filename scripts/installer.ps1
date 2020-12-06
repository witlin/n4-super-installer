<#

#>

# variables and constants
$errorBase = "[ERROR] " + (Get-Date -Format "MM/dd/yyyy HH:mm:ss")
$infoBase = "[INFO] " + (Get-Date -Format "MM/dd/yyyy HH:mm:ss")
$ctrlDir = "C:\Controls Software"
$setupPaths = Get-ChildItem -Path .\assets\installers -Filter *.exe 

# functions
function log-step {
  param (
    [parameter (Mandatory = $true)]
    [string] $msg
  )
  Write-Host $msg
}
function audit-process {
  param (
    [Parameter(Mandatory = $false)]
    [bool] $enable = $true
  )
  if ($enable) {
    if (Test-Path -Path C:\secpol.cfg) {
      Remove-Item -Path C:\secpol.cfg -Force
      SecEdit.exe /export /cfg C:\secpol.cfg
      (Get-Content -Path C:\secpol.cfg).Replace("AuditProcessTracking = 0", "AuditProcessTracking = 1") | 
      Out-File C:\secpol.cfg
      SecEdit.exe /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
      Remove-Item -Force -Path C:\secpol.cfg
    }
    else {
      SecEdit.exe /export /cfg C:\secpol.cfg
      (Get-Content -Path C:\secpol.cfg).Replace("AuditProcessTracking = 1", "AuditProcessTracking = 0") | 
      Out-File C:\secpol.cfg
      SecEdit.exe /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
      Remove-Item -Force -Path C:\secpol.cfg
    }
  }
}
function run-setup {
  param (
    [Parameter(Mandatory = $true)] [string] $setupPath,
    [Parameter(Mandatory = $true)] [string] $filterExpression
  )
  start-process -filepath $setupPath
  Start-Sleep -s 1
  $proc = get-process -ProcessName $filterExpression
  log-step -msg $infoBase" Scanning for the setup process"
  Write-Host "Process ID found: "$proc[0].Id

  while ($proc.Length -gt 0) {
    Start-Sleep -Seconds 3
    $proc = get-process -ProcessName $filterExpression
  }
  
  Start-Sleep -s 1
  $evEnd = Get-EventLog -LogName Security -InstanceId 4689 -Newest 200
  foreach ($ev in $evEnd) {
    $repStrs = $evEnd[0] | Select-Object -Property ReplacementStrings
    $processName = $repStrs.ReplacementStrings[6]
    if ($processName.contains($filterExpression)) {
      Write-Host $processName
    }
  }

  $repStrs = $evEnd[0] | Select-Object -Property ReplacementStrings
  $processID = [convert]::ToInt64($repStrs.ReplacementStrings[5], 16)
  $processName = $repStrs.ReplacementStrings[6]
  log-step -msg $infoBase" Windows Event verification"
  Write-Host "Name: "$processName
  Write-Host "PID: "$processID
}

# LOGIC
if (Test-Path -Path $ctrlDir) {
  ## the Controls Software folder exists, delete to start install process from scratch
  log-step -msg $infoBase" D:\Controls Software exists...deleting..."
  Remove-Item -Path $ctrlDir -Force -Recurse

}
else {
  log-step $infoBase" C:\Controls Software does not exist..."

  if (Test-Path -Path "C:\") {
    
    ### D:\ volume exists on disk, create the Controls Software folder.
    New-Item -Path "C:\" -Name "Controls Software" -ItemType "directory"
    log-step -msg $infoBase" created directory at "$ctrlDir

    ### Enable audit process tracking local security policy
    log-step -msg $infoBase" Enabling the audit process tracking local security policy..."
    audit-process

    ### Copy the installer folder to the proper location
    Copy-Item -Path (Get-Location) -Destination $ctrlDir -Recurse -Force

    ### Start running install setups
    foreach ($p in $setupPaths) {
      run-setup -setupPath $p.FullName -filterExpression *Distech*
    }

    # variables and constants after install setups
    $licenseFile = "licenses\Distech.license"
    $n4Name = ($setupPaths[1].Name -split " ")[($setupPaths[1].Name -split " ").Length - 1]
    $n4Version = $n4Name.Trim('v', '.', 'e', 'x', 'e')
    $majorRev = $n4Version.Substring(0, 3)
    $partialLicensePath = "EC-Net4-", $n4Version, "\security\licenses" -join ""
    $absoluteLicensePath = Join-Path -Path "C:\Niagara" -ChildPath $partialLicensePath
    $jars = Get-ChildItem -Path .\assets\jars
    $partialN4JarPath = "EC-Net4-", $n4Version, "\modules" -join ""
    $absoluteN4JarPath = Join-Path -Path "C:\Niagara" -ChildPath $partialN4JarPath
    $partialNrePath = "\Niagara", $majorRev, "\distech\etc\nre.properties" -join ""
    $absoluteNrePath = Join-Path -Path $env:AllUSERSPROFILE -ChildPath $partialNrePath
    $partialShorcutPath = "Microsoft\Windows\Start\Menu\Programs"
    $usrShortcutPath = Join-Path -Path $env:APPDATA -ChildPath $partialShorcutPath
    $allUsrShortcutPath = Join-Path -Path $env:AllUSERSPROFILE -ChildPath $partialShorcutPath
    $startMenuShortcutFiles = Get-ChildItem -Path $usrShortcutPath

    ## Copy license file to the new N4 license folder in the Niagara install directory
    Copy-Item -Path $licenseFile -Destination $absoluteLicensePath -Force
    log-step -msg $infoBase" Copied license file to its proper location in the Niagara license folder..."

    ## Copy Niagara Jar Modules
    foreach ($jar in $jars) {
      Copy-Item -Path $jar.FullName -Destination $absoluteN4JarPath -Force
    }
    log-step -msg $infoBase" Copied all the jars to their proper location in the Niagara modules folder..."

    ## Make all the Distech shortchuts available to all users
    log-step -msg $infoBase" scanning start menu shortcut files"
    foreach ($f in $startMenuShortcutFiles) {
      if (($f.FullName).contains("EC-Net")) {
        Write-Host $f.Name
        Copy-Item -Path $f.FullName -Destination $allUsrShortcutPath
      }
    }

    ## Edit the nre.properties file
    Copy-Item -Path $absoluteNrePath -Destination assets -Force
    Rename-Item -Path assets\nre.properties -NewName "nre_backup.properties"
    log-step -msg $infoBase" backed-up nre.properties to .\assets\nre_backup.properties"

    log-step -msg $infoBase" scanning nre.properties"
    Get-Content -Path $absoluteNrePath

    (Get-content -Path $absoluteNrePath).Replace("station.java.options=-Dfile.encoding=UTF-8 -Xss512K -Xmx1024M", "station.java.options=-Dfile.encoding=UTF-8 -Xss512K -Xmx2G") |
    Out-File $absoluteNrePath
      
    Get-Content -Path $absoluteNrePath
      
    log-step -msg $infoBase" copied all shortcut files from the installation user shortcut folder to the all-users one..."

    ## Set the process tracking audit policy back to default
    audit-process -enable $false

    ## Re-align security execution policy with strict security requirements.
    Set-ExecutionPolicy Restricted

  }
  else {
    log-step $errorBase" The 'D:\' volume does not exist, contact your local controls engineer for assistance"
  }
}