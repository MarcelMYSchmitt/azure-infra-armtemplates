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
                Write-Host "Giving $ServicePrincipalToAuthorize access to $KeyVaultName."
                $ServicePrincipalName='https://'+$ServicePrincipalToAuthorize
                Set-AzureRmKeyVaultAccessPolicy -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ServicePrincipalName $ServicePrincipalName -PermissionsToKeys list,decrypt,sign,get,unwrapKey -PermissionsToSecrets list,get
            }
    } else {
        Write-Host "Key vault already exists"
    }
}

Function DeployTemplate([string]$ResourceGroupName, [string]$TemplateFileFullPath, [Hashtable]$TemplateParameters, [switch]$ValidateOnly) {
    if ($ValidateOnly) {
		Write-Host 'TemplateFileFullPath 1 = ' @($TemplateFileFullPath);
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

