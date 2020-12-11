<#
.Synopsis
  Author: vsmolinski
  12/4/2020
  Automate the N4 Supervisor host installation process
.Description
  Open a Remote Desktop Connection with the server.
  Copy and paste the n4-super-installer zip file from your computer to the server.
  Unzip the installer on your Windows user's desktop.
  Open the Windows Start Menu and type powershell, then select Run As Administrator.
  Change the command prompt to the new folder's directory (..\n4-super-installer) and run the script.
.Example
  Run the script from the installer folder in your Desktop
  cd "$env:homedrive$env:homepath\Desktop\n4-super-installer";
  Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\installer.ps1
.Example
  Run the script from C:\
  cd "C:\n4-super-installer";
  Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\installer.ps1
.Example
  Clear the event log before running so you can track the events in eventvwr.msc in real time.
  cd "C:\n4-super-installer";
  Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\installer.ps1
#>

# variables and constants
$errorBase = "[ERROR] " + (Get-Date -Format "MM/dd/yyyy HH:mm:ss");
$infoBase = "[INFO] " + (Get-Date -Format "MM/dd/yyyy HH:mm:ss");
$ctrlDir = "C:\Controls Software";
$setupPaths = Get-ChildItem -Path .\assets\installers -Filter *.exe; 

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

  if (Test-Path -Path C:\secpol.cfg) {
    Remove-Item -Path C:\secpol.cfg -Force
  }

  if ($enable) {
    SecEdit.exe /export /cfg C:\secpol.cfg
    (Get-Content -Path C:\secpol.cfg).Replace("AuditProcessTracking = 0", "AuditProcessTracking = 1") | 
      Out-File C:\secpol.cfg
    SecEdit.exe /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
    Remove-Item -Force -Path C:\secpol.cfg
  } else {
    SecEdit.exe /export /cfg C:\secpol.cfg
    (Get-Content -Path C:\secpol.cfg).Replace("AuditProcessTracking = 1", "AuditProcessTracking = 0") | 
    Out-File C:\secpol.cfg
    SecEdit.exe /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY
    Remove-Item -Force -Path C:\secpol.cfg
  }
}
function run-setup {
  param (
    [Parameter(Mandatory = $true)] [string] $setupPath,
    [Parameter(Mandatory = $true)] [string] $filterExpression
  )
  start-process -filepath $setupPath
  Start-Sleep -s 1
  # n4-super-installer\assets\installers\3-NetFx64.exe
  # n4-super-installer\assets\installers\BonjourPSSetup.exe
  $proc = get-process -ProcessName $filterExpression 
  log-step -msg "$infoBase Scanning for the setup process"
  Write-Host "Process ID found: "$proc[0].Id

  while ($proc.Length -gt 0) {
    Start-Sleep -Seconds 5
    $proc = get-process -ProcessName $filterExpression
  }
    
  Start-Sleep -s 1
  $evEnd = Get-EventLog -LogName Security -InstanceId 4689 -Newest 1
  $instanceId = [convert]::ToString($evEnd.InstanceId)
  $index = [convert]::ToString($evEnd.Index)
  $repStrs = $evEnd[0] | Select-Object -Property ReplacementStrings
  $processID = [convert]::ToInt64($repStrs.ReplacementStrings[5], 16)
  $processName = $repStrs.ReplacementStrings[6]
  log-step -msg $infoBase" Windows Event verification"
  Write-Host "Event Instance Id: $instanceId"
  Write-Host "Event index: $index"
  Write-Host "Name: "$processName
  Write-Host "PID: "$processID
}

# LOGIC
if (Test-Path -Path $ctrlDir) {
  ## the Controls Software folder exists, delete to start install process from scratch
  log-step -msg $infoBase" C:\Controls Software exists...deleting..."
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
    audit-process -enable $true

    ### Copy the installer folder to the proper location
    log-step -msg "$infoBase copying script files to $ctrlDir..."
    Copy-Item -Path (Get-Location) -Destination $ctrlDir -Recurse -Force

    ### Start running install setups | can't run the Support Pack until the Workbench is licensed.
    foreach ($p in $setupPaths) {
      run-setup -setupPath $p.FullName -filterExpression *Distech*
    }

    # variables and constants after install setups
    $n4Name = ($setupPaths[3].Name -split " ")[($setupPaths[3].Name -split " ").Length - 1];
    $n4Version = $n4Name.Trim('v', '.', 'e', 'x', 'e');
    $majorRev = $n4Version.Substring(0, 3);

    ## Copy license file to the new N4 license folder in the Niagara install directory
    try {
      $licenseFile = "licenses\Distech.license"
      $partialLicensePath = "EC-Net4-", $n4Version, "\security\licenses" -join ""
      $absoluteLicensePath = Join-Path -Path "C:\Niagara" -ChildPath $partialLicensePath

      Copy-Item -Path $licenseFile -Destination $absoluteLicensePath -Force
      log-step -msg $infoBase" Copied license file to its proper location in the Niagara license folder..."
    } catch {
      log-step -msg "$errorBase Failed to copy license over: $PSItem...!"
    }

    ## Copy Niagara Jar Modules
    try {
      $jars = Get-ChildItem -Path .\assets\jars
      $partialN4JarPath = "EC-Net4-", $n4Version, "\modules" -join ""
      $absoluteN4JarPath = Join-Path -Path "C:\Niagara" -ChildPath $partialN4JarPath

      foreach ($jar in $jars) {
        Copy-Item -Path $jar.FullName -Destination $absoluteN4JarPath -Force
      }
      log-step -msg $infoBase" Copied all the jars to their proper location in the Niagara modules folder..."
    } catch {
      log-step -msg "$errorBase Failed to copy jars over: $PSItem...!"
    }

    ## Make all the Distech shortchuts available to all users
    try {    
      $partialShorcutPath = "Microsoft\Windows\Start Menu\Programs"
      $usrShortcutPath = Join-Path -Path $env:APPDATA -ChildPath $partialShorcutPath
      $allUsrShortcutPath = Join-Path -Path $env:AllUSERSPROFILE -ChildPath $partialShorcutPath
      $startMenuShortcutFiles = Get-ChildItem -Path $usrShortcutPath

      log-step -msg $infoBase" scanning start menu shortcut files"
      foreach ($f in $startMenuShortcutFiles) {
        if (($f.FullName).contains("EC-Net")) {
          Write-Host $f.Name
          Copy-Item -Path $f.FullName -Destination $allUsrShortcutPath
        }
      }
      log-step -msg $infoBase" copied all shortcut files from the installation user shortcut folder to the all-users one..."
    } catch {
      log-step -msg "$errorBase Failed to copy shortcuts over: $PSItem...!"
    }

    ## Edit the nre.properties files
    <#
      C:\Niagara\EC-Net4.9.0.60\defaults\nre.properties
      C:\Users\User\Niagara4.9\distech\etc\nre.properties
      C:\ProgramData\Niagara4.9\distech\etc
    #>
    try {
      $partialNrePath = "EC-Net4-", $n4Version, "\defaults\nre.properties" -join "";
      $absoluteNrePath = Join-Path -Path "C:\Niagara" -ChildPath $partialNrePath;
      $usrNrePath = Join-Path -Path "$env:homedrive\$env:homepath" -ChildPath "Niagara$majorRev\distech\etc\nre.properties";
      $allusrNrePath = Join-Path -Path $env:allusersprofile -ChildPath "Niagara$majorRev\distech\etc\nre.properties";
  
      if (Test-Path $absoluteNrePath) {
        try {
          Copy-Item -Path $absoluteNrePath -Destination assets -Force -ErrorAction Stop
          Rename-Item -Path assets\nre.properties -NewName "nre_backup.properties"
          log-step -msg $infoBase" backed-up nre.properties to .\assets\nre_backup.properties"
      
          log-step -msg $infoBase" scanning nre.properties"
          Get-Content -Path $absoluteNrePath
      
          (Get-content -Path $absoluteNrePath).Replace("station.java.options=-Dfile.encoding=UTF-8 -Xss512K -Xmx1024M", "station.java.options=-Dfile.encoding=UTF-8 -Xss512K -Xmx2G") |
          Out-File $absoluteNrePath

          Copy-Item -Path $absoluteNrePath -Destination $usrNrePath -Force
          Copy-Item -Path $absoluteNrePath -Destination $allusrNrePath -Force
            
          Get-Content -Path $absoluteNrePath
        } catch {
          log-step -msg "$errorBase Failed to edit nre.properties file: $PSItem...!"
        }
      } else {
        log-step -msg "$errorBase $absoluteNrePath could not be found...!"
      }
    } catch {
      log-step -msg "$errorBase failed to edit $absoluteNrePath - $PSItem"
    }

    ## Set the process tracking audit policy back to default
    audit-process -enable $false

    ## Re-align security execution policy with strict security requirements.
    Set-ExecutionPolicy Restricted -Scope Process -Force

  }
  else {
    log-step $errorBase" The 'D:\' volume does not exist, contact your local controls engineer for assistance"
  }
}