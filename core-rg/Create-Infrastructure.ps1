#Requires -Version 3.0

Param(
    [Parameter(Mandatory=$True)]
    [string]
    $FileName,

    [Parameter(Mandatory=$True)]
    [string]
    $ClientSecret,

    [Parameter()]
    [string]
    $HasThumbPrint
)

#stop the script on first error
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
$SubscriptionId = $Configuration.SubscriptionId
$ServicePrincipalName = $Configuration.ServicePrincipalName
$ClientId = $Configuration.ClientId
$DirectoryId = $Configuration.DirectoryId
$ServiceBusQueueName = $Configuration.ServiceBusQueueName
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
#prepare everything
#******************************************************************************

#at the moment we only allow 'ne' and 'we' as locations
if ($LocationTag -eq "we") {
    $ResourceGroupLocation = "West Europe"
    $LocationTag = "we"
    $HubLocation = "westeurope"
} 
elseif ($LocationTag -eq "ne"){
    $LocationTag = "ne"
    $ResourceGroupLocation = "North Europe"
    $HubLocation = "northeurope"
} else {
    Write-Host "Only 'we' and 'ne' are supported for location tags, default value is 'we'!"
    $ResourceGroupLocation = "West Europe"
    $LocationTag = "we"
    $HubLocation = "westeurope"
}

#naming of resources
$ResourceGroupName="$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-rg"
$KeyVaultName="$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-vt"
$IotHubName="$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-iothub"
$DpsName="$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-$ComponentTag"
$ServiceBusNamespaceName="$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-sbns"
$AcrName = "$CompanyTag$LocationTag$EnvironmentTag$ProjectTag"+"acr"


#******************************************************************************
#script body
#******************************************************************************


CreateResourceGroupIfNotPresent -ResourceGroupName $ResourceGroupName -ResourceGroupLocation $ResourceGroupLocation -LocationTag $LocationTag
CreateKeyVaultIfNotPresent -KeyVaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ResourceGroupLocation $ResourceGroupLocation -LocationTag $LocationTag -ServicePrincipalToAuthorize $ServicePrincipalName

#create service bus
Write-Host "Going to create service bus queue."
$serviceBusParameters = New-Object -TypeName Hashtable
$serviceBusParameters["ServiceBusQueueName"] = $ServiceBusQueueName
$serviceBusParameters["ServiceBusNamespaceName"] = $ServiceBusNamespaceName
$serviceBusTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.servicebus.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $serviceBusTemplateFile -TemplateParameters $serviceBusParameters

#add service bus queue connection strings to key vault 
Write-Host "Going to add service bus queue connection strings to key vault."
$serviceBusSecretsParameters = New-Object -TypeName Hashtable
$serviceBusSecretsParameters["CompanyTag"] = $CompanyTag
$serviceBusSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$serviceBusSecretsParameters["LocationTag"] = $LocationTag
$serviceBusSecretsParameters["ProjectTag"] = $ProjectTag
$serviceBusSecretsParameters["ServiceBusQueueName"] = $ServiceBusQueueName
$serviceBusSecretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.servicebus.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $serviceBusSecretsTemplateFile -TemplateParameters $serviceBusSecretsParameters

#read service bus queue send connection string from key vault 
Write-Host "Reading service bus send connection string from key vault."
$ServiceBusQueueSendConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName ServiceBusQueueSendConnectionString).SecretValueText

#create iothub
Write-Host "Going to create iothub."
$iotHubParameters = New-Object -TypeName Hashtable
$iotHubParameters["IotHubName"] = $IotHubName
$iotHubParameters["HubLocation"] = $HubLocation
$iotHubParameters["SubscriptionId"] = $SubscriptionId
$iotHubParameters["ServiceBusQueueSendConnectionString"] = $ServiceBusQueueSendConnectionString
$iotHubParameters["ServiceBusQueueName"] = $ServiceBusQueueName
$iotHubParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.iothub.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $iotHubParametersTemplateFile -TemplateParameters $iotHubParameters

#add iothub manage connection string to key vault 
Write-Host "Going to add iothub manage connection string to key vault."
$iotHubSecretsParameters = New-Object -TypeName Hashtable
$iotHubSecretsParameters["CompanyTag"] = $CompanyTag
$iotHubSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$iotHubSecretsParameters["LocationTag"] = $LocationTag
$iotHubSecretsParameters["ProjectTag"] = $ProjectTag
$iotHubSecretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.iothub.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $iotHubSecretsTemplateFile -TemplateParameters $iotHubSecretsParameters

#read iot hub connection string from key vault 
Write-Host "Reading iot hub connection string from key vault."
$IotHubOwnerConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubOwnerConnectionString).SecretValueText

#create dps 
Write-Host "Going to create dps."
$dpsParameters = New-Object -TypeName Hashtable
$dpsParameters["IotHubName"] = $IotHubName
$dpsParameters["ProvisioningServiceName"] = $DpsName
$dpsParameters["HubLocation"] = $HubLocation
$dpsParameters["IotHubOwnerConnectionString"] = $IotHubOwnerConnectionString
$dpsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.dps.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $dpsTemplateFile -TemplateParameters $dpsParameters

#get the scope id of the dps
Write-Host "Calling DPS for DpsScopeId."
$DpsScopeId = CallDPSEndpoint -DirectoryId $DirectoryId -SubscriptionId $SubscriptionId -ClientId $ClientId -ClientSecret $ClientSecret -ResourceGroupName $ResourceGroupName -DpsName $DpsName

#add dps manage connection string to key vault 
Write-Host "Going to add dps manage connection string to key vault."
$dpsSecretsParameters = New-Object -TypeName Hashtable
$dpsSecretsParameters["CompanyTag"] = $CompanyTag
$dpsSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$dpsSecretsParameters["LocationTag"] = $LocationTag
$dpsSecretsParameters["ProjectTag"] = $ProjectTag
$dpsSecretsParameters["DpsScopeId"] = $DpsScopeId
$dpsSecretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.dps.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $dpsSecretsTemplateFile -TemplateParameters $dpsSecretsParameters

#read iot hub connection string from key vault 
Write-Host "Reading dps manage connection string from key vault."
$DpsManageConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName dpsManageConnectionString).SecretValueText

#create azure function
Write-Host "Going to create azure function with consumption plan, application insights and storage account."
$dpsFunctionParameters = New-Object -TypeName Hashtable
$dpsFunctionParameters["CompanyTag"] = $CompanyTag
$dpsFunctionParameters["EnvironmentTag"] = $EnvironmentTag
$dpsFunctionParameters["ComponentTag"] = $ComponentTag
$dpsFunctionParameters["LocationTag"] = $LocationTag
$dpsFunctionParameters["ProjectTag"] = $ProjectTag
$dpsFunctionParameters["DpsManageConnectionString"] = $DpsManageConnectionString
$dpsFunctionParameters["ClientId"] = $ClientId
$dpsFunctionParameters["AzureAdClusterIssuer"] = $AzureAdClusterIssuer
$dpsFunctionTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.dpsfunction.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $dpsFunctionTemplateFile -TemplateParameters $dpsFunctionParameters

#get the master host key of the function
$FunctionAppName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-$ComponentTag-func"
$accessToken = Get-AuthorisationHeaderValue $ResourceGroupName $FunctionAppName
$adminCode = Get-MasterAPIKey $accessToken $FunctionAppName

#add function master host key to key vault 
Write-Host "Going to add function master host key to key vault to key vault."
$functionsSecretsParameters = New-Object -TypeName Hashtable
$functionsSecretsParameters["CompanyTag"] = $CompanyTag
$functionsSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$functionsSecretsParameters["LocationTag"] = $LocationTag
$functionsSecretsParameters["ProjectTag"] = $ProjectTag
$functionsSecretsParameters["DeviceProvisioningFunctionsKey"] = $adminCode.Masterkey
$functionsSecretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.dpsfunction.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $functionsSecretsTemplateFile -TemplateParameters $functionsSecretsParameters

#create azure container registry
Write-Host "Going to create azure container registry."
$acrParameters = New-Object -TypeName Hashtable
$acrParameters["acrName"] = $AcrName
$acrParameters["acrSku"] = "Basic"
$acrParameters["acrAdminUserEnabled"] = $True
$acrParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.acr.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $acrParametersTemplateFile -TemplateParameters $acrParameters

#get docker registry password
$DockerRegistryPassword = CallAzureContainerRegistryCredentialsEndpoint -ResourceGroupName $ResourceGroupName -AcrName $AcrName

#add azure container registry password to key vault
Write-Host "Going to add azure container registry password to key vault."
$acrSecretsParameters = New-Object -TypeName Hashtable
$acrSecretsParameters["CompanyTag"] = $CompanyTag
$acrSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$acrSecretsParameters["LocationTag"] = $LocationTag
$acrSecretsParameters["ProjectTag"] = $ProjectTag
$acrSecretsParameters["DockerRegistryPassword"] = $DockerRegistryPassword
$acrSecretsParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.acr.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $acrSecretsParametersTemplateFile -TemplateParameters $acrSecretsParameters


$StorageAccountName="$CompanyTag$LocationTag$EnvironmentTag$ProjectTag"+"stor"
$AppInsightsName = "$CompanyTag-$LocationTag-$EnvironmentTag-$ProjectTag-insights"

#create storage account 
Write-Host "Going to create storage account."
$storageParameters = New-Object -TypeName Hashtable
$storageParameters["storageAccountName"] = $StorageAccountName
$storageTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.storage.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $storageTemplateFile -TemplateParameters $storageParameters

#add storage account connection string in keyvault
Write-Host "Going to add storage account connection string to key vault."
$storageSecretsParameters = New-Object -TypeName Hashtable
$storageSecretsParameters["CompanyTag"] = $CompanyTag
$storageSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$storageSecretsParameters["LocationTag"] = $LocationTag
$storageSecretsParameters["ProjectTag"] = $ProjectTag
$storageSecretsTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.storage.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $storageSecretsTemplateFile -TemplateParameters $storageSecretsParameters

#create application insights 
Write-Host "Going to create application insights."
$appInsightsParameters = New-Object -TypeName Hashtable
$appInsightsParameters["appInsightsName"] = $AppInsightsName
$appInsightsParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/infrastructure.appinsights.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $appInsightsParametersTemplateFile -TemplateParameters $appInsightsParameters

#add application insights instrumentation key to key vault
Write-Host "Going to add application insights instrumentation key to key vault."
$appInsightsSecretsParameters = New-Object -TypeName Hashtable
$appInsightsSecretsParameters["CompanyTag"] = $CompanyTag
$appInsightsSecretsParameters["EnvironmentTag"] = $EnvironmentTag
$appInsightsSecretsParameters["LocationTag"] = $LocationTag
$appInsightsSecretsParameters["ProjectTag"] = $ProjectTag
$appInsightsSecretsParametersTemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "./armtemplates/keyvault.appinsights.json"))
DeployTemplate -ResourceGroupName $ResourceGroupName -TemplateFileFullPath $appInsightsSecretsParametersTemplateFile -TemplateParameters $appInsightsSecretsParameters


#******************************************************************************
#testing output from keyvault 
#******************************************************************************


#get values from key vault 
Write-Host "Reading all secrets from key vault."
$dockerRegistryPassword = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName dockerRegistryPassword).SecretValueText
$deviceProvisioningFunctionsKey = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName deviceProvisioningFunctionsKey).SecretValueText
$dpsScopeIdString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName dpsScopeIdString).SecretValueText
$dpsManageConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName dpsManageConnectionString).SecretValueText
$iotHubOwnerConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubOwnerConnectionString).SecretValueText
$iotHubEndpointConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubEndpointConnectionString).SecretValueText
$iotHubServiceConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubServiceConnectionString).SecretValueText
$iotHubSasServicePrimaryKey = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName iotHubSasServicePrimaryKey).SecretValueText
$serviceBusQueueListenConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName serviceBusQueueListenConnectionString).SecretValueText
$serviceBusQueueSendConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName serviceBusQueueSendConnectionString).SecretValueText
$serviceBusQueueManageConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName serviceBusQueueSendConnectionString).SecretValueText

#keys genererated from templates part, as long as not used let commented out
$storageConnectionString = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName storageConnectionString).SecretValueText
$appInsightsInstrumentationKey = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName appInsightsInstrumentationKey).SecretValueText


Write-Host "Got secrets from key vault."
Write-Host "========================================================"
Write-Host "dockerRegistryPassword=$dockerRegistryPassword"
Write-Host "deviceProvisioningFunctionsKey=$deviceProvisioningFunctionsKey"
Write-Host "dpsScopeIdString=$dpsScopeIdString"
Write-Host "dpsManageConnectionString=$dpsManageConnectionString"
Write-Host "iotHubOwnerConnectionString=$iotHubOwnerConnectionString"
Write-Host "iotHubEndpointConnectionString=$iotHubEndpointConnectionString"
Write-Host "iotHubServiceConnectionString=$iotHubServiceConnectionString"
Write-Host "iotHubSasServicePrimaryKey=$iotHubSasServicePrimaryKey"
Write-Host "serviceBusQueueListenConnectionString=$serviceBusQueueListenConnectionString"
Write-Host "serviceBusQueueSendConnectionString=$serviceBusQueueSendConnectionString"
Write-Host "serviceBusQueueManageConnectionString=$serviceBusQueueManageConnectionString"
Write-Host "storageConnectionString=$storageConnectionString"
Write-Host "appInsightsInstrumentationKey=$appInsightsInstrumentationKey"
Write-Host "========================================================"