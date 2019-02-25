#Requires -Version 3.0

Function CreateResourceGroupIfNotPresent([string]$ResourceGroupName, [string]$ResourceGroupLocation) {
    $resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if(!$resourceGroup) {
        Write-Host "Creating resource group '$ResourceGroupName' in location '$ResourceGroupLocation'";
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Tag @{owner="<<TeamName>>"}
    } else {
        Write-Host "Using existing resource group '$ResourceGroupName'"
    }
}

Function CreateKeyVaultIfNotPresent([string]$KeyVaultName, [string]$ResourceGroupName, [string]$ResourceGroupLocation, [string]$ServicePrincipalToAuthorize) {
    # due to different problems with ARM templates and key vaults, an actually easier way of creating them is using powershell directly
    # (less bugs, direct assignment of creating user as admin etc.)
    $keyVault = Get-AzureRmKeyVault -VaultName $KeyVaultName -ErrorAction SilentlyContinue
    if (-not $keyVault) {
        New-AzureRmKeyVault -VaultName $KeyVaultName  `
            -ResourceGroupName $ResourceGroupName  `
            -Location $ResourceGroupLocation `
            -EnabledForDeployment `
            -EnabledForTemplateDeployment
        
        if ($ServicePrincipalToAuthorize) {
            Write-Host "Giving read/write access to '$ServicePrincipalToAuthorize'"
            $ServicePrincipalName='https://'+$ServicePrincipalToAuthorize
            Set-AzureRmKeyVaultAccessPolicy -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ServicePrincipalName $ServicePrincipalName -PermissionsToKeys list,decrypt,sign,get,unwrapKey -PermissionsToSecrets list,get
        }
    } else {
        Write-Host "Key vault already exists"
    }
}

Function DeployTemplate([string]$ResourceGroupName, [string]$TemplateFileFullPath, [Hashtable]$TemplateParameters, [switch]$ValidateOnly) {
    if ($ValidateOnly) {
		Write-Host 'TemplateFileFullPath = ' @($TemplateFileFullPath);
        $ErrorMessages = Format-ValidationOutput (Test-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                            -TemplateFile $TemplateFileFullPath `
                            @TemplateParameters)
        if ($ErrorMessages) {
            Write-Host '', 'Validation returned the following errors:', @($ErrorMessages), '', 'Template is invalid.'
            throw 'Template validation failed'
        } else {
            Write-Host '', 'Template is valid.'
        }
    }
    else {
		Write-Host 'TemplateFileFullPath ' @($TemplateFileFullPath);
		Write-Host 'ResourceGroupName ' @($ResourceGroupName);	
        $TemplateFileName = Split-Path $TemplateFileFullPath -leaf
		Write-Host 'TemplateFileName ' @($TemplateFileName);
        $DeploymentName = $TemplateFileName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm') 
		Write-Host 'DeploymentName ' @($DeploymentName);
        New-AzureRmResourceGroupDeployment -Name $DeploymentName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -TemplateFile $TemplateFileFullPath `
                                           @TemplateParameters `
                                           -Force -Verbose `
                                           -ErrorVariable ErrorMessages
        if ($ErrorMessages) {
            Write-Host '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
            throw 'Template deployment failed'
        }
    }
}

Function CallDPSEndpoint([string]$DirectoryId, [string]$SubscriptionId, [string]$ClientId, [string]$ClientSecret, [string]$ResourceGroupName, [string]$DpsName) {
    $result = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$DirectoryId/oauth2/token?api-version=1.0" -Method Post -Body @{"grant_type" = "client_credentials"; "resource" = "https://management.core.windows.net/"; "client_id" = "$ClientId"; "client_secret" = "$ClientSecret" }
    $token=$result.access_token

    $Headers=@{
        'authorization'="Bearer $token"
        'host'="management.azure.com"
        'contentype'='application/json'
    }
    
    $BaseUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Devices/provisioningServices/$DpsName"
    $CompleteUrl = $BaseUrl+"?api-version=2017-11-15"

    $response = Invoke-RestMethod  -Uri $CompleteUrl  -Headers $Headers -Method GET 
    
    if ($response.properties.idScope) {
        return $response.properties.idScope
    } else {
        throw 'ScopeId is null or not available.'
    }
}

function Get-AuthorisationHeaderValue($ResourceGroupName, $FunctionAppName){
 
    $publishingCredentials = Get-PublishingProfileCredentials $ResourceGroupName $FunctionAppName
 
    return ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))
}
 
function Get-PublishingProfileCredentials($ResourceGroupName, $FunctionAppName){
 
    $resourceType = "Microsoft.Web/sites/config"
    $resourceName = "$FunctionAppName/publishingcredentials"
 
    $publishingCredentials = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName -Action list -ApiVersion 2015-08-01 -Force
 
    return $publishingCredentials
}

function Get-MasterAPIKey($AuthorisationToken, $FunctionAppName ){
 
    $apiUrl = "https://$FunctionAppName.scm.azurewebsites.net/api/functions/admin/masterkey"
    $result = Invoke-RestMethod -Uri $apiUrl -Headers @{"Authorization"=$AuthorisationToken;"If-Match"="*"} 
     
    return $result
}

Function CallAzureContainerRegistryCredentialsEndpoint([string]$ResourceGroupName, [string]$AcrName) {
    Write-Host 'Try to get docker registry password.'
    $response = Get-AzureRmContainerRegistryCredential -ResourceGroupName $ResourceGroupName -Name $AcrName

    if ($response.Password) {
        return $response.Password
    } else {
        throw 'Password is null or not available.'
    }
}