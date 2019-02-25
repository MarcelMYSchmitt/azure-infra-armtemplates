'Arm templates folder'  
All our arm templates for creating components. 
For every component we have a seperate infrastructure and key vault arm template. 

'environments folder'  
For every possible resource group and all the azure services within we are using a seperate json file. It contains all relevant parameter which will be used in our script. 

'Create-Infrastructure.ps1'  
Root script for creating our infrastructure in Azure. It loads all files which it needs (arm templates, json environment file and powershell commands).

'Common-Functions.ps1'  
Script with common functions which are used in our Create-Infrastructure.ps1 script. 

'Create-Env-Variables.ps1'  
Script for setting all relevant environment variables in CloudFoundry for our app.
For setting variables we need to logins, one in Azure and the other one in CloudFoundry.
- You can find the login statement for azure inside of the the script.
- The login statement four cloudfoundry could be defined as part of your build steps in your corresponding Tool (AzureDevOps, TeamCity, Jenkins..)

If you want to use this script locally you have to login into cf before using the script. Because of of path Issues of the CF CLI (every location - locally or remote - could have another Path to the CLI), we are going to pass the location of th cf.exe to the script.
So at first you have to find out where you installed cloud foundry (normally something like 'C:\Program Files\Cloud Foundry').

