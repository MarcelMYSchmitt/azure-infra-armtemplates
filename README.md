General:
We are going to create two resource groups with different azure services which belong together. One use case could be to have core services in the first resource group and extra services (like for testing) in the second one.

First resource group we will have following services:  
- DPS
- IotHub
- Service Bus Namespace with Service Bus Queue (and SAS policies)
- Key Vault
- Azure Functions with Application Insights and Storage Account (and App Service Plan) 
- Container Registry
- Storage Account
- Application Insights

Second resource group we will have following services: 
- Key Vault
- Web App Container (with App Service Plan)
- Application Insights


Why two resource groups at all?
As long as we are going to use Azure Functions with a Windows Service Plan, we cannot deploy our web app container with linux in the same resource group. That's not possible. For more informations go to: https://docs.microsoft.com/de-de/azure/app-service/containers/app-service-linux-intro#limitations


How to use:
- Create both resource groups manually.
  Use following naming convention: 'CompanyTag-LocationTag-EnvironmentTag-ProjectTag-rg' and 'CompanyTag-LocationTag-EnvironmentTag-ProjectTag-s-rg'
  By having this we are independent from fixed naming conventions.
  The 's' in the second resource group says that it's the second one belonging to the first one. 
- Create service principal in youre azure ad and create a key. We use the key later in our infrastructure script. 
- Add the new service principal as contributor to your resource groups.
- Use 'createAndApplyServicePrincipalCertificate.ps1' to create a certificate. By using this certificate you do not have to login everytime into  azure. Besides you can use it on your build server.
- Change parameters in 'environments/ct-lt-et-pt.json' to your naming convention above, add the missing variables like ClientId and ClientSecret (which you get from azure ad for example). Rename the file to 'CompanyTag-LocationTag-EnvironmentTag-ProjectTag.json'. For every environment stage, location area or project you will have another json-file. 



In all arm templates such as the powershell script there is no hard coded stuff. All things which can be changed anytime (as far and as long as we want) are declared in a separate environment json-file.  
General naming convention: 'CompanyTag-LocationTag-EnvironmentTag-ProjectTag.json'  
The file gets loaded at the beginning of the script, if we want to change the loaded script we can pass the name as argument in the concerning build server or locally. 




Setting environment variables in Cloud Foundry:
There is a seperate script for reading secrets from our key vault and setting the environment variables in Cloud Foundry. Concerning the handling it's the same like for the other scripts.

-> for environment variables we need three arguments: FileName, CfCliPath, HasThumbPrint

'HasThumbPrint' is just a parameter we set in our build server, we do not use it locally. All the parameters are also stored in specific json-files.
The CfCliPath is needed to point to the cf installation folder (which can dffer on every agent we have on our build server). 






For more information go into the subfolder, there you can find more README files. 