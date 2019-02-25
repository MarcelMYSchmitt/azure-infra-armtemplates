Login-AzureRmAccount

$ApplicationId = "<<<our applicationId here>>"
$CertSubject = "CN=<<ServicePrincipalName>>"

Remove-AzureRmADAppCredential -ApplicationId $ApplicationId -All

$cert = New-SelfSignedCertificate -CertStoreLocation "cert:\CurrentUser\My" -Subject $CertSubject -KeySpec KeyExchange -HashAlgorithm "SHA256" -NotAfter (Get-Date).AddYears(100)
$keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())

New-AzureRmADAppCredential -ApplicationId $applicationId -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore

