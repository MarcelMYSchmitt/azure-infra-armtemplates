#Requires -Version 3.0

Param(
    [Parameter(Mandatory=$True)]
    [string]
    $FileName,

    [Parameter()]
    [string]
    $HasThumbPrint
)

# stop the script on first error
$ErrorActionPreference = 'Stop'


#******************************************************************************
#dependencies
#******************************************************************************

. "$PSScriptRoot/Common-Functions.ps1"


#******************************************************************************
#test passing variables from json to script
#******************************************************************************


$Configuration = Get-Content -Raw -Path "$PSScriptRoot/environments/$FileName.json" | ConvertFrom-Json

$CompanyTag = $Configuration.CompanyTag
$LocationTag = $Configuration.LocationTag
$EnvironmentTag = $Configuration.EnvironmentTag
$ProjectTag = $Configuration.ProjectTag
$ComponentTag = $Configuration.ComponentTag
$LogEventLevel = $Configuration.LogEventLevel
$ServicePrincipalName = $Configuration.ServicePrincipalName
$ClientId = $Configuration.ClientId
$DirectoryId = $Configuration.DirectoryId
$SubscriptionId = $Configuration.SubscriptionId
$AzureAdClusterIssuer = $Configuration.AzureAdClusterIssuer

#******************************************************************************
#login into azure using cert and app registration
#******************************************************************************


if ($HasThumbPrint) { 
    $certSubject = "CN=$ServicePrincipalName"
    $thumbprint = (Get-ChildItem cert:\CurrentUser\My\ | Where-Object {$_.Subject -match $certSubject }).Thumbprint
    Write-Host "Got thumbprint from certificate: $thumbprint"
    Login-AzureRmAccount -ServicePrincipal -CertificateThumbprint $thumbprint -ApplicationId $ClientId -TenantId $DirectoryId
} else {
    Login-AzureRmAccount;
}

#select subscription
Write-Host "Selecting subscription: $SubscriptionId";
Select-AzureRmSubscription -SubscriptionID $SubscriptionId;


#******************************************************************************
#prepare everything for script
#******************************************************************************


#at the moment we only allow 'ne' and 'we' as locations
if ($LocationTag -eq "we") {
    $ResourceGroupLocation = "West Europe"
} 
elseif ($LocationTag -eq "ne"){
    $LocationTag = "ne"
    $ResourceGroupLocation = "North Europe"
} else {
    Write-Host "Only 'we' and 'ne' are supported for location tags, default value is 'we'!"
    $ResourceGroupLocation = "West Europe"
    $LocationTag = "we"
}

#naming of resources
$sprefix="s"
$ResourceGroupName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-$sprefix-$ComponentTag-rg"
$KeyVaultName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-$sprefix-$ComponentTag-vt"

$AcrName = "$CompanyTag$LocationTag$EnvironmentTag$ProjectTag"+"acr"
$DockerRegistryUsername = $AcrName
$DockerRegistryUrl = $AcrName+".azurecr.io"

$RemoteKeyVaultName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-vt"
$AppInsightsName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-$sprefix-$ComponentTag-insights"


#******************************************************************************
#script body
#******************************************************************************


CreateResourceGroupIfNotPresent -ResourceGroupName $ResourceGroupName -ResourceGroupLocation $ResourceGroupLocation -LocationTag $LocationTag
CreateKeyVaultIfNotPresent -KeyVaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ResourceGroupLocation $ResourceGroupLocation -LocationTag $LocationTag -ServicePrincipalToAuthorize $ServicePrincipalName

#create application insights
Write-Host "Going to create application insights."
$appInsightsParameters = New-Object -TypeName Hashtable
$appInsightsParameters["appInsightsName"] = $AppInsightsName
$appInsightsParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.appinsights.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $appInsightsParametersTemplateFile -TemplateParameters $appInsightsParameters

#write keys to key vault 
Write-Host "Going to store all secrets in key vault."
$secretsParameters = New-Object -TypeName Hashtable
$secretsParameters["CompanyTag"] = $CompanyTag
$secretsParameters["EnvironmentTag"] = $EnvironmentTag
$secretsParameters["LocationTag"] = $LocationTag
$secretsParameters["ProjectTag"] = $ProjectTag
$secretsParameters["ComponentTag"] = $ComponentTag
$secretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.keyvault.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $secretsTemplateFile -TemplateParameters $secretsParameters

#get values from key vault
Write-Host "Reading secrets from key vaults."
$AppInsightsInstrumentationKey = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName appInsightsInstrumentationKey).SecretValueText
$dockerRegistryPassword = (Get-AzureKeyVaultSecret -VaultName $RemoteKeyVaultName -SecretName dockerRegistryPassword).SecretValueText

Write-Host "Got secrets from key vault."
Write-Host "========================================================"
Write-Host "AppInsightsInstrumentationKey=$AppInsightsInstrumentationKey"
Write-Host "========================================================"

#create web app container 
Write-Host "Going to create the web app."
$appParameters = New-Object -TypeName Hashtable
$appParameters["CompanyTag"] = $CompanyTag
$appParameters["EnvironmentTag"] = $EnvironmentTag
$appParameters["LocationTag"] = $LocationTag
$appParameters["ProjectTag"] = $ProjectTag
$appParameters["ComponentTag"] = $ComponentTag
$appParameters["AppServiceStorage"] = $False
$appParameters["DockerRegistryUrl"] = $DockerRegistryUrl
$appParameters["DockerRegistryUsername"] = $DockerRegistryUsername
$appParameters["DockerRegistryPassword"] = $dockerRegistryPassword
$appParameters["LogEventLevel"] = $LogEventLevel
$appParameters["ApplicationInsightsKey"] = $AppInsightsInstrumentationKey
$appParameters["ClientId"] = $ClientId
$appParameters["AzureAdClusterIssuer"] = $AzureAdClusterIssuer
$appParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.webapp.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $appParametersTemplateFile -TemplateParameters $appParameters