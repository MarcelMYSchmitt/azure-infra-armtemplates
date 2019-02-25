#Requires -Version 3.0

#****************************************************************************************************************************************************
#
# Small script for creating a service principal in azure active directory.
# Script generates also a secret key entry in service principal and add the required resource adress for windows azure active directory.
# Besides with the last command a reply url will be added to the service principal (for securing our web app with authentication).
#
#****************************************************************************************************************************************************


#$ServicePrincipalName = '<<ServicePrincipalName>>'
#$SubscriptionId = '<<SubscriptionId>>'
#$WebAppUrl = "https://<<CompanyTag>>-<<LocationTag>>-<<EnvironmentTag>>-<<ProjectTag>>.azurewebsites.net"


Param (
    [parameter(Mandatory=$true)]
    [String]
	$ServicePrincipalName,
	
	[parameter(Mandatory=$true)]
    [String]
	$SubscriptionId,
	
	[parameter(Mandatory=$true)]
    [String]
	$WebAppUrl
)


#login into azure
Login-AzureRmAccount
Connect-AzureAD

#set right subscription
Set-AzureRmContext -SubscriptionId $SubscriptionId
Write-Host "Using ServicePrincipalId ' $SubscriptionId' for creating new ServicePrincipal '$ServicePrincipalName'."

#create serviceprincipal and password
$SecureStringPassword = ConvertTo-SecureString -String "password123" -AsPlainText -Force
$IdentifierUri = 'https://'+$ServicePrincipalName
$newServicePrincipal = New-AzureRmADApplication -DisplayName $ServicePrincipalName -HomePage https://<<DefaultWebPage.com>> -IdentifierUris $IdentifierUri -Password $SecureStringPassword

#give access to windows azure active directory 
$req = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
$req.ResourceAccess = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList "311a71cc-e848-46a1-bdf8-97ff7156d8e6","Scope"
$req.ResourceAppId = "00000002-0000-0000-c000-000000000000"
Set-AzureADApplication -ObjectId $newServicePrincipal.ObjectId -RequiredResourceAccess $req

#set reply url for new webapp
$FallBackUrl = $WebAppUrl+"/.auth/login/aad/callback"
Set-AzureADApplication -ObjectId $newServicePrincipal.ObjectId -ReplyUrls $FallBackUrl