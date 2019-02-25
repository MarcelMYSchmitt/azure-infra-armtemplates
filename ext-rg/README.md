'Arm templates folder'  
All our arm templates for creating components. 
For every component we have a seperate infrastructure arm template.
Concerning keyvault and secrets stored there, we have just one arm template. 

'environments folder'  
For every possible resource group and all the azure services within we are using a seperate json file. It contains all relevant parameter which will be used in our script. 

'Create-Infrastructure.ps1'  
Root script for creating our infrastructure in Azure. It loads all files which it needs (arm templates, json environment file and powershell commands).

'Common-Functions.ps1'  
Script with common functions which are used in our Create-Infrastructure.ps1 script.


Authentication and Deployment in Web App    
When we deploy our web app arm template everything gets preconfigured, application settings, connection strings and the authentication settings, too (as far as we want).  
What is still missing concerning the auth settings is the 'Reply Url' which we have to define in the Azure AD for the service principal. 
There we have to add the new url for the right callback of the AD.

So don't forget after deploying the app in a new resource group to add the url  'https://<<CompanyTag>>-<<LocationTag>>-<<EnvironmentTag>>-<ProjectTag>-s-<<ComponentTag>>.azurewebsites.net/.auth/login/aad/callback'  
in Azure AD -> App Registration -> <<ServicePrincipalName>> -> Settings -> Reply Urls!