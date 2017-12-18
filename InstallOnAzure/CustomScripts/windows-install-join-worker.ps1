[CmdletBinding()]

# Modify the $DockerEngineURI with the latest link from https://docs.docker.com/engine/installation/windows/docker-ee/#use-a-script-to-install-docker-ee

Param(
  [switch] $SkipEngineUpgrade,
  [string] $ArtifactPath = ".",
  [string] $DockerEngineURI = "https://download.docker.com/components/engine/windows-server/17.06/docker-17.06.2-ee-6.zip",
  [string] $USERNAME,
  [string] $PASSWORD,
  [string] $UCPURI,
  [string] $DTRURI,
  [string] $SWARMMGRIP
)

#Variables
$Date = Get-Date -Format "yyyy-MM-dd HHmmss"
$DockerPath = "C:\Program Files\Docker"
$DockerDataPath = "C:\ProgramData\Docker"
$UserDesktopPath = "C:\Users\Default\Desktop"


function Install-LatestDockerEngine () {

    #Get Docker Engine from Master Builds

    Invoke-WebRequest -UseBasicparsing -Uri $DockerEngineURI -OutFile docker.zip

    #Get Docker Engine

    Expand-Archive -Path docker.zip -Force

    #Replace Docker Engine

    Stop-Service docker
    Copy-Item ".\docker\docker\dockerd.exe" "$DockerPath\dockerd.exe" -Force
    Copy-Item ".\docker\docker\docker.exe" "$DockerPath\docker.exe" -Force
    Start-Service docker

}



function Join-Swarm ()
{

    # UCP Rest API detail is here : https://docs.docker.com/datacenter/ucp/2.2/reference/api/#/

    # Get the required images to configure the local engine

    docker image pull docker/ucp-agent-win:2.2.2
    docker image pull docker/ucp-dsinfo-win:2.2.2

    # Execute the local node configuration

    docker container run --rm docker/ucp-agent-win:2.2.2 windows-script | powershell -noprofile -noninteractive -command 'Invoke-Expression -Command $input'

    # Deactivate HTTPS cert check to allow REST access to UCP with self signed cert

    Write-Host "Deactivating Cert validation"
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

    # Login to UCP to get an authentication token

    Write-Host "Authenticating against UCP"
    $postParams = @{username="$USERNAME";password="$PASSWORD"}
    $JSON = $postParams | convertto-json
    $result = Invoke-WebRequest -UseBasicparsing -Uri https://$UCPURI/auth/login -Method POST -Body $JSON | ConvertFrom-Json
    $Token=$result.auth_token

    # Retrieve the SWARM information to get the join token for workers

    Write-Host "Get Swarm Information"
    $header =  @{Authorization="Bearer $Token"}
    $swarm_info = Invoke-WebRequest -UseBasicparsing -Uri https://$UCPURI/swarm -Method GET -Headers $header | ConvertFrom-Json
    $WORKER_Join_Token = $swarm_info.JoinTokens.Worker

    # Join the node to UCP

    Write-Host "Join the worker to UCP"
    docker swarm join --token $WORKER_Join_Token $SWARMMGRIP

}


function Customize-User-Desktop ()
{
#    Install-Module Image2Docker -Force
#    Import-Module Image2Docker -Force

    # Download the DTR certificate to install it and trust it (to allow docker login commands)

    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $webClient = new-object System.Net.WebClient
    $webClient.DownloadFile( "https://$DTRURI/ca", "$UserDesktopPath\dtrca.crt" )

    Import-Certificate "$UserDesktopPath\dtrca.crt" -CertStoreLocation Cert:\LocalMachine\AuthRoot

    # Copy some additionnal files in the user desktop

    Copy-Item ".\copy_certs.ps1" "$UserDesktopPath\copy_certs.ps1" -Force
    Copy-Item ".\MTA-Commands.txt" "$UserDesktopPath\MTA-Commands.txt" -Force

#    Move-Item ".\ws2016.vhd" "$UserDesktopPath\ws2016.vhd" -Force
}


function Install-Keyboards ()
{
     New-Item -Path "$UserDesktopPath\keyboard-french-mac" -ItemType Directory -Force
     Expand-Archive -Path keyboard-french-mac.zip -DestinationPath "$UserDesktopPath\keyboard-french-mac" -Force
     Start-Process -FilePath "$UserDesktopPath\keyboard-french-mac\setup.exe" -ArgumentList "/a"
}


#Start Script

$ErrorActionPreference = "Stop"

try
{
    Start-Transcript -path "$UserDesktopPath\configure-worker $Date.log" -append

    Set-ExecutionPolicy Unrestricted -Force

    Write-Host "ArtifactPath = $ArtifactPath"
    Write-Host "DockerEngineURI = $DockerEngineURI"
    Write-Host "USERNAME = $USERNAME"
    Write-Host "UCPURI = $UCPURI"
    Write-Host "DTRURI = $DTRURI"
    Write-Host "SWARMMGRIP = $SWARMMGRIP"

    Write-Host "Install additional Keyboards"
    Install-Keyboards

    Write-Host "Upgrading Docker Engine"
    Install-LatestDockerEngine

    Write-Host "Join the Swarm cluster"
    Join-Swarm

    Write-Host "Customize the user desktop"
    Customize-User-Desktop

    Stop-Transcript
}
catch
{
    Write-Error $_
}
