#Requires -Version 3.0

Param(
    [Parameter(Mandatory=$True)]
    [string]
    $FileName,

    [Parameter(Mandatory=$True)]
    [string]
    $CfCliPath,

    [Parameter()]
    [string]
    $HasThumbPrint
)

#stop the script on first error
$ErrorActionPreference = 'Stop'


#******************************************************************************
#test passing variables from json to script
#******************************************************************************


$Configuration = Get-Content -Raw -Path "$PSScriptRoot/cloudfoundry/$FileName.json" | ConvertFrom-Json

$CompanyTag = $Configuration.CompanyTag
$LocationTag = $Configuration.LocationTag
$EnvironmentTag = $Configuration.EnvironmentTag
$ProjectTag = $Configuration.ProjectTag
$ComponentTag = $Configuration.ComponentTag
$SubscriptionId = $Configuration.SubscriptionId
$ServicePrincipalName = $Configuration.ServicePrincipalName
$ClientId = $Configuration.ClientId
$DirectoryId = $Configuration.DirectoryId
$CfAppname = $Configuration.CfAppname
$LogEventLevel = $Configuration.LogEventLevel


#******************************************************************************
#login into azure using cert and app registration
#******************************************************************************


#login into azure
if ($HasThumbPrint) { 
    $certSubject = "CN=$ServicePrincipalName"
    $thumbprint = (Get-ChildItem cert:\CurrentUser\My\ | Where-Object {$_.Subject -match $certSubject }).Thumbprint
    Write-Host "Got thumbprint from certificate: $thumbprint"
    Login-AzureRmAccount -ServicePrincipal -CertificateThumbprint $thumbprint -ApplicationId $ClientId -TenantId $DirectoryId
} else {
    Login-AzureRmAccount;
}

#set subscriptionid
Set-AzureRmContext -SubscriptionId $SubscriptionId


#******************************************************************************
#prepare everything
#******************************************************************************


#naming of resources
$keyVaultName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-vt"


#******************************************************************************
#script body
#******************************************************************************


#get values from keyvault
#Write-Host "Get values from $KeyVaultName."
#$iotHubServiceConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubServiceConnectionString).SecretValueText

#go into the cloud foundry directory
cd $CfCliPath

#setting environment tag for possible use
Write-Host "Set ENVIRONMENT_TAG."
./cf.exe set-env $CfAppname ENVIRONMENT_TAG $EnvironmentTag

Write-Host "Set LOG_EVENT_LEVEL."
./cf.exe set-env $CfAppname LOG_EVENT_LEVEL $LogEventLevel


#Write-Host "Set CUSTOMCONNSTR_IOT_HUB."
#./cf.exe set-env $CfAppname CUSTOMCONNSTR_IOT_HUB $iotHubServiceConnectionString

#setting application key for possible use
#$appInsightsInstrumentationKey = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName appInsightsInstrumentationKey).SecretValueText
#Write-Host "Set APPLICATION_INSIGHTS_KEY."
#./cf.exe set-env $CfAppname APPLICATION_INSIGHTS_KEY $appInsightsInstrumentationKey