# Graph Permissions Cheat Sheet

## Summary
This document goes over how to add Graph permissions via PowerShell using the Graph module. It deliberately does NOT use the deprecated AzureAD module.

## Assigning Graph API permissions (scopes) to a Managed Identity

### 1. Connect to Graph
    Connect-MgGraph -NoWelcome -Scopes "AppRoleAssignment.ReadWrite.All", "Directory.Read.All"

### 2. Add permissions
    $graphAppId = "00000003-0000-0000-c000-000000000000" #This is globally unique, do not change

    #Uncomment/modify according to which permissions you need
    $permissions = @(
    #"Directory.ReadWrite.All"
    #"Group.ReadWrite.All"
    #"GroupMember.ReadWrite.All"
    #"User.ReadWrite.All"
    #"RoleManagement.ReadWrite.Directory"
    )

    $managedIdentity = "Name of Managed Identity"
    
    $sp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
    $msi = Get-MgServicePrincipal -Filter "displayName eq '$managedIdentity'"
    
    $appRoles = $sp.AppRoles | Where-Object {($_.Value -in $permissions) -and ($_.AllowedMemberTypes -contains "Application")}
    $appRoles | ForEach-Object {
        $appRoleAssignment = @{
            "PrincipalId" = $msi.Id
            "ResourceId" = $sp.Id
            "AppRoleId" = $_.Id
        }
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appRoleAssignment.PrincipalId -BodyParameter $appRoleAssignment -Verbose
    }

---

## Assigning Graph API permissions (scopes) and Exchange Online role to Managed Identity

### 1. Connect to Graph
    Connect-MgGraph -Scopes AppRoleAssignment.ReadWrite.All,Application.Read.All,RoleManagement.ReadWrite.Directory

### 2. Get Managed Identity
    $MI_ID = (Get-MgServicePrincipal -Filter "DisplayName eq '<Your Display Name Here>'").id

### 3. Delegate Exchange.ManageAsApp API permissions to the Managed Identity
    $AppRoleID = "dc50a0fb-09a3-484d-be87-e023b12c6440" #Exchange.ManageAsApp API permission
    $ResourceID = (Get-MgServicePrincipal -Filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'").Id #Office 365 Exchange Online resource in Microsoft Entra ID
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MI_ID -PrincipalId $MI_ID -AppRoleId $AppRoleID -ResourceId $ResourceID

### 4. Assign Exchange permissions to the Managed Identity
    $AppRoleID = (Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq 'Exchange Recipient Administrator'").Id
    # More permissions, may be needed/easier in some instances.
    # $AppRoleID = (Get-MgRoleManagementDirectoryRoleDefinition -Filter "DisplayName eq 'Exchange Administrator'").id
    New-MgRoleManagementDirectoryRoleAssignment -PrincipalId $MI_ID -RoleDefinitionId $AppRoleID -DirectoryScopeId "/"

### 5. Assign Graph API permissions

    #Graph API permissions to set
    $oPermissions = @(
    "User.Read.All"
    )

    #Static App ID for Graph, don't change
    $GraphAppId = "00000003-0000-0000-c000-000000000000"
    $oGraphSpn = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"

    #Get the app roles for the permissions
    $oAppRole = $oGraphSpn.AppRole | Where-Object {($_.Value -in $oPermissions) -and ($_.AllowedMemberType -contains "Application")}

    #Add the roles
    foreach($AppRole in $oAppRole){
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MI_ID -PrincipalId $MI_ID -AppRoleId $AppRole.ID -ResourceId $oGraphSpn.id
    }

### Microsoft Documentation

https://learn.microsoft.com/en-us/powershell/exchange/connect-exo-powershell-managed-identity?view=exchange-ps#step-4-grant-the-exchangemanageasapp-api-permission-for-the-managed-identity-to-call-exchange-online

