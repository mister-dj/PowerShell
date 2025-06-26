<#
Written by Don Morgan
This module allows interacting with HubSpot's API via native PowerShell cmdlets/objects

Note: this is written to use the v3 HubSpot API
#>

########## Begin Internal functions ##########
#Main internal function that handles calling the API
function InvokeHubSpotApi {
    param(
        [Parameter(Mandatory = $true)]
        [validatePattern('/.*')] #Require the endpoint start with a slash, e.g. '/account-info/v3/details'
        [string]$Endpoint,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Get","Post","Delete","Patch")]
        [string]$Method = "get",
        [Parameter(Mandatory = $false)]
        $Body
    )

    if($Env:HubSpotApiVerbosity){
        Write-Host "Invoking API call with endpoint: $Endpoint" -ForegroundColor Yellow
    }

    #Make sure the ENV is already set for the API token and auth headers
    if($null -eq $Env:HubSpotApiKey -or $null -eq $env:HubSpotApiUrl){
        throw 'please run the "Connect-HubSpotApi" cmdlet first'
    }

    $ApiKey =  $Env:HubSpotApiKey
    $BaseUri =  $Env:HubSpotApiUrl

    $Uri = $BaseUri + $Endpoint

    $Headers = @{
        "Content-Type" = "application/json"
        "accept" = "application/json"
        "Authorization" = "Bearer $ApiKey"
    }

    #We'll see if pagination with a body for any method turns up any bugs lol
    if($Body){
        if($Env:HubSpotApiVerbosity){
            $BodyString = $Body.ToString()
            Write-Host "API query body: `n $BodyString" -ForegroundColor Yellow
        }

        $response = Invoke-RestMethod $Uri -Method $Method -Headers $Headers -Body $Body
        
        #If response is paginated, keep getting all pages
        if($response.paging.next.link){
            if($Env:HubSpotApiVerbosity){
                Write-Host "API query result has pagination" -ForegroundColor Yellow
            }

            $result = $response.results

            while($response.paging.next.link){
                $nextPageUri = $response.paging.next.link
                $response = Invoke-RestMethod $nextPageUri -Method $Method -Headers $Headers -Body $Body
                $result += $response.results
            }
        }
        #if no pagination, just return the response
        else{
            $result = $response
        }
    }
    else{
        $response = Invoke-RestMethod $Uri -Method $Method -Headers $Headers

        if($response.paging.next.link){
            if($Env:HubSpotApiVerbosity){
                Write-Host "API query result has pagination" -ForegroundColor Yellow
            }

            $result = $response.results

            while($response.paging.next.link){
                $nextPageUri = $response.paging.next.link
                $response = Invoke-RestMethod $nextPageUri -Method $Method -Headers $Headers
                $result += $response.results
            }
        }
        else{
            $result = $response
        }
    }
    
    return $result
}

#Used for generating properly formatted UTC timestamps for hs_timestamp. Example: 2021-11-12T15:48:22Z
function GetHubSpotTimeStamp {
    $Timestamp = [DateTime]::UtcNow.ToString('u')
    Return $Timestamp.Replace(' ','T')
}

#Used for debugging
function Set-HubSpotApiVerbosity {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("None","Verbose","11")]
        $VerboseLevel
    )

    if($VerboseLevel -eq "Verbose"){
        $Env:HubSpotApiVerbosity = "Verbose"
    }
    elseif($VerboseLevel -eq "11"){
        $Env:HubSpotApiVerbosity = "Verbose"
        $VerbosePreference = 'Continue'
    }
    else{
        $Env:HubSpotApiVerbosity = $null
        $VerbosePreference = 'SilentlyContinue'
    }
}
########## End Internal Functions ##########
function Connect-HubSpotApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiKey
    )

    $BaseApiUrl = "https://api.hubapi.com"

    #Build headers with auth token and content type
    $Headers = @{
        "Content-Type" = "application/json"
        "accept" = "application/json"
        "Authorization" = "Bearer $ApiKey"
    }

    #Using this API endpoint to test the connection
    $AccountEndpoint = "/account-info/v3/details"

    $Uri = $BaseApiUrl + $AccountEndpoint
    $response = Invoke-RestMethod $Uri -Method Get -Headers $Headers

    $AccountNumber = $response.portalId

    if($null -ne $AccountNumber){
        #Set environment variables for reuse in other cmdlets
        $Env:HubSpotApiKey = $ApiKey
        $Env:HubSpotApiUrl = $BaseApiUrl
        Write-Host -ForegroundColor Green "Connected to account id $AccountNumber"
    }
}
function Get-HubSpotPipeline {
    <#
    .SYNOPSIS
        Gets pipelines from HubSpot
    
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/pipelines
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Deal")]
        [string]$Type
    )

    $Endpoint = "/crm/v3/pipelines/$Type"

    $Req = InvokeHubSpotApi -Endpoint $Endpoint
    Return $Req.results  
}
function Remove-HubSpotPipeline {
    <#
    .SYNOPSIS
        Deletes a pipeline from HubSpot

    .EXAMPLE
        Remove-HubSpotPipeline -Type Deal -Id 12345
    
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/pipelines#delete-a-pipeline
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Deal")]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Id,
        #Force deletion doesn't check if there are records in the pipeline before deleting, use with caution
        [Parameter(Mandatory = $false)]
        [switch]$ForceDelete
    )

    $Endpoint = "/crm/v3/pipelines/$Type/$Id"

    if($ForceDelete){
        $Endpoint += "?validateReferencesBeforeDelete=false"
        Write-Host -ForegroundColor Yellow "Caution: this parameter may leave orphaned objects"
    }
    else{
        $Endpoint += "?validateReferencesBeforeDelete=true"
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Method Delete
    Return $Req
}
function Get-HubSpotDeal {
    <#
    .SYNOPSIS
        Gets deals from HubSpot.
    .DESCRIPTION
        Gets either all deals, or a specific deal by Id from HubSpot.
        Returns some basic properties by default, but you can include a list of properties to include. For a list of properties, see 'Get-HubSpotProperty -Object Deals'
    .EXAMPLE
        #Specific properties to retrieve
        $PropertiesArray =@(
                "hs_deal_stage_probability",
                "hs_forecast_probability",
                "hs_manual_forecast_category",
                "dealtype",
                "dealstage",
                "amount",
                "createDate",
                "closeDate",
                "hs_closed_won_date"
        )
        $Properties = $PropertiesArray -join ','    
        Get-HubSpotDeal -Id "23008365181" -Properties $Properties

        #Get all deals
        Get-HubSpotDeal
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/objects/deals
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Properties = $null
    )

    $Endpoint = "/crm/v3/objects/deals"

    if($Id){
        $Endpoint += "/$Id"
    }
    if($Properties){
        $Endpoint += "?properties=$Properties"
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint
    Return $Req
    
}
function New-HubSpotDeal {
    <#
    .SYNOPSIS
        Creates a new deal in HubSpot.
    .DESCRIPTION
        Creates a new deal in HubSpot with given properties which are passed as a JSON object.
    .EXAMPLE
        #Create new deal
        $Properties =@{
            properties = @{
            "pipeline" = $PipelineId
            "dealstage" = $StageId
            "dealname" = "Test Dealio"
            }
        } | ConvertTo-Json
        New-HubSpotDeal -PropertiesObject $PropertiesObject
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/objects/deals#create-deals
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$PropertiesObject
    )

    $Endpoint = "/crm/v3/objects/deals"

    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $PropertiesObject -Method Post
    Return $Req
}
function Set-HubSpotDeal {
    <#
    .SYNOPSIS
        Updates properties on a deal in HubSpot.
    .DESCRIPTION
        Updates a deal in HubSpot with given properties which are passed as a JSON object.
    .EXAMPLE
        #Update a deal
        $Properties =@{
            properties = @{
            "pipeline" = $PipelineId
            "dealstage" = $StageId
            "dealname" = "Test Dealio"
            }
        } | ConvertTo-Json
        Set-HubSpotDeal -PropertiesObject $PropertiesObject -Id 12345678
    .LINK
        https://developers.hubspot.com/docs/reference/api/crm/objects/deals#patch-%2Fcrm%2Fv3%2Fobjects%2Fdeals%2F%7Bdealid%7D
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [object]$PropertiesObject
    )

    $Endpoint = "/crm/v3/objects/deals/$Id"

    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $PropertiesObject -Method Patch
    Return $Req
}
function Get-HubSpotProperty {
    <#
    .SYNOPSIS
        Gets a list of properties for a given object type.
    .DESCRIPTION
        Gets a list of properties for a given object type.
        This command is useful for getting a list of properties and their internal names for use in other commands such as New-HubSpotDeal.
    .EXAMPLE
        #Get all properties for Deals
        Get-HubSpotProperty -Object "Deals"
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/using-object-apis#retrieve-records
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Object,
        [Parameter(Mandatory = $false)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [switch]$Sensitive
    )

    if($Name){
        $Endpoint = "/crm/v3/properties/$Object/$Name"
    }
    else{
        $Endpoint = "/crm/v3/properties/$Object"
    } 

    #https://developers.hubspot.com/docs/reference/api/crm/sensitive-data#manage-sensitive-data
    if($Sensitive){
        $Endpoint += "?dataSensitivity=sensitive"
    }
    
    $Req = InvokeHubSpotApi -Endpoint $Endpoint
    Return $Req.results
}
function Get-HubSpotCompany {
    <#
    .SYNOPSIS
        Gets companies from HubSpot.
    .DESCRIPTION
        Gets either all companies or a specific company by Id from HubSpot.

        Returns some basic properties by default, but you can include a list of properties to include.
    .EXAMPLE
        #Get all companies    
        Get-HubSpotCompany -All

        #Get a specific company
        Get-HubSpotCompany -Id "23528570115"
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/objects/companies
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Properties = $null
    )

    $Endpoint = "/crm/v3/objects/companies"

    if($Id){
        $Endpoint += "/$Id"
    }
    if($Properties){
        $Endpoint += "?properties=$Properties"
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint

    Return $Req
}
function Set-HubSpotCompany {
    <#
    .SYNOPSIS
        Updates a company in HubSpot.

    .DESCRIPTION
        Updates a company's properties with new values. Input for PropertiesObject should be a JSON formatted object (hashtable) with only the properties/values you want to update.

    .EXAMPLE
        $JsonFormattedObject = @{
            Name = $NewName
            Phone = $NewPhone
        } | ConvertTo-Json
        Set-HubSpotCompany -Id 12345678 -PropertiesObject $JsonFormattedObject

    .LINK
        https://developers.hubspot.com/docs/reference/api/crm/objects/companies#patch-%2Fcrm%2Fv3%2Fobjects%2Fcompanies%2F%7Bcompanyid%7D
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [object]$PropertiesObject
    )

    $Endpoint = "/crm/v3/objects/companies/$Id"

    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $PropertiesObject -Method Patch

    #Successful update will return the company (same as Get-HubSpotCompany)
    if(-not $Req.id){
        Write-Error "Failed to update company"
    }
}
function Get-HubSpotAssociation {
    <#
    .SYNOPSIS
        Gets associations between an object and another type of object in HubSpot, e.g. all contacts associated with a company.
    .DESCRIPTION
        Gets associations between an object and another type of object in HubSpot, e.g. all contacts associated with a company.
        The Types switch will list the types of associations between two object types.

        #Note: this cmdlet uses the v3 API and as such does not show secondary company associations (e.g. if there are two companies associated with one deal this cmdlet only returns the primary association)
    .EXAMPLE
        #Get all association types between companies and contacts
        $CompanyAssociations = Get-HubSpotAssociation -BaseObject "Companies" -RelatedObject "Contacts" -Types

        #Get all associations between a company and contacts
        Get-HubSpotAssociation -BaseObject "Companies" -RelatedObject "Contacts" -BaseObjectId 12345678
    .LINK
        https://developers.hubspot.com/beta-docs/reference/api/crm/associations/association-details/v3
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelatedObject,
        [Parameter(Mandatory = $true)]
        [string]$BaseObject,
        [Parameter(Mandatory = $false)]
        [string]$BaseObjectId,
        [Parameter(Mandatory = $false)]
        [switch]$Types
    )

    $BaseEndpoint = "/crm/v3/associations/"
    $AssociationEndpoint = $BaseEndpoint + $BaseObject + '/' + $RelatedObject

    if($Types){
        $Endpoint = $AssociationEndpoint + '/types'
        
        $Req = InvokeHubSpotApi -Endpoint $Endpoint
    }
    else{
        $Endpoint = $AssociationEndpoint + '/batch/read'
        
        $Body = @{
            inputs=@(
                @{
                    id = $BaseObjectId
                }
            )
        } | ConvertTo-Json

        $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $Body -Method Post
    }

    Return $Req.results
}
function New-HubSpotAssociation {
    <#
    .SYNOPSIS
        Creates a new association of a given type between two objects.
    .DESCRIPTION
        Creates a new association of a given type between two objects.

        For a list of types, use Get-HubSpotAssociation with the -Types switch, e.g. 
            Get-HubSpotAssociation -BaseObject "Companies" -RelatedObject "Contacts" -Types
    .EXAMPLE
        #Create new association
        $Splat = @{
            BaseObject = "Deal"
            BaseObjectId = 12345678
            RelatedObject = "Company"
            RelatedObjectId = 019283784
            Type = "deal_to_company"
        }
        New-HubSpotAssociation @Splat
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/associations/associations-v3#create-associations
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseObject,
        [Parameter(Mandatory = $true)]
        [string]$BaseObjectId,
        [Parameter(Mandatory = $true)]
        [string]$RelatedObject,
        [Parameter(Mandatory = $true)]
        [string]$RelatedObjectId,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $Endpoint = "/crm/v3/associations/" + $BaseObject + '/' + $RelatedObject + '/batch/create'

    $Body = @{
        inputs=@(
            @{
                from = @{
                    id = $BaseObjectId
                }
                
                to = @{
                    id = $RelatedObjectId
                }

                type = $Type
            }
        )
    } | ConvertTo-Json -Depth 10

    
    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $Body -Method Post
    
    Return $Req
}
function Remove-HubSpotAssociation {
    <#
    .SYNOPSIS
        Deletes an association between two objects in HubSpot.
    .DESCRIPTION
        Deletes an association between two objects in HubSpot.

        For a list of types, use Get-HubSpotAssociation with the -Types switch, e.g. 
            Get-HubSpotAssociation -BaseObject "Companies" -RelatedObject "Contacts" -Types
    .EXAMPLE
        #Remove an association
        $Splat = @{
            BaseObject = "Deal"
            BaseObjectId = $TestDeal.id
            RelatedObject = "Company"
            RelatedObjectId = $TestCompany.id
            Type = "deal_to_company"
        }
        Remove-HubSpotAssociation @Splat
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/associations/associations-v3#remove-associations
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseObject,
        [Parameter(Mandatory = $true)]
        [string]$BaseObjectId,
        [Parameter(Mandatory = $true)]
        [string]$RelatedObject,
        [Parameter(Mandatory = $true)]
        [string]$RelatedObjectId,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $Endpoint = "/crm/v3/associations/" + $BaseObject + '/' + $RelatedObject + '/batch/archive'

    $Body = @{
        inputs=@(
            @{
                from = @{
                    id = $BaseObjectId
                }
                
                to = @{
                    id = $RelatedObjectId
                }

                type = $Type
            }
        )
    } | ConvertTo-Json -Depth 10

    
    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Body $Body -Method Post
    
    Return $Req
}
function Get-HubSpotContact {
    <#
    .SYNOPSIS
        Gets contacts from HubSpot.
    .DESCRIPTION
        Gets either all contacts, or a specific contact by Id from HubSpot.

        Returns some basic properties by default, but you can include a list of properties to include.

        Using the AssociatedObjectType parameter, you can also return objects of a given type that are associated with a specific contact.
    .EXAMPLE
        #Get all contacts
        Get-HubSpotContact

        #Get specific contact
        Get-HubSpotContact -Id 12345678
    .LINK
        https://developers.hubspot.com/docs/reference/api/crm/objects/contacts#get-%2Fcrm%2Fv3%2Fobjects%2Fcontacts%2F%7Bcontactid%7D
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Properties = $null,
        [Parameter(Mandatory = $false)]
        [ValidateSet("contacts","companies","deals")]
        [string]$AssociatedObjectType
    )

    $Endpoint = "/crm/v3/objects/contacts"

    if($Id){
        $Endpoint += "/$Id"
    }
    if($AssociatedObjectType){
        $Endpoint += "?associations=$AssociatedObjectType"
    }
    if($Properties){
        if($Endpoint.Contains('?')){
            $Endpoint += "&properties=$Properties"
        }
        else{
            $Endpoint += "?properties=$Properties"
        }
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint

    Return $Req
}
function Set-HubSpotContact{
    <#
    .SYNOPSIS
        Sets/updates properties on a contact.
    .DESCRIPTION
        Updates properties for a given contact Id. Properties are passed as an object since they can be customized in HubSpot.
        You can get a list of properties using Get-HubSpotProperty -Object contact
    .EXAMPLE
        $NewProps = @{
            properties = @{
                cell_phone = "800-555-1212"
            }
        } | ConvertTo-Json

        Set-HubSpotContact -id 12345678 -PropertiesObject $NewProps
    .LINK
        https://developers.hubspot.com/docs/reference/api/crm/objects/contacts#patch-%2Fcrm%2Fv3%2Fobjects%2Fcontacts%2F%7Bcontactid%7D
    #>
    [alias("Update-HubSpotContact")]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [object]$PropertiesObject
    )

    $Endpoint = "/crm/v3/objects/contacts/$Id"

    $Req = InvokeHubSpotApi -Method Patch -Body $PropertiesObject -Endpoint $Endpoint

    Return $Req.id
}
function Get-HubSpotNote {
    <#
    .SYNOPSIS
        Gets notes from HubSpot.
    .DESCRIPTION
        Gets notes associated with a given contact/company/deal, or gets all notes in HubSpot.
    .EXAMPLE
        Get-HubSpotNote -AssociatedObjectType deals -Id 12345678
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/engagements/notes#retrieve-notes
    #>
    param(
        [Parameter(Mandatory = $false,ParameterSetName = "SingleNote")]
        [string]$Id,
        [Parameter(Mandatory = $false,ParameterSetName = "SingleNote")]
        [Parameter(Mandatory = $false,ParameterSetName = "NotesByAssociation")]
        [string]$Properties = $null,
        [Parameter(Mandatory = $true,ParameterSetName = "NotesByAssociation")]
        [ValidateSet("contacts","companies","deals")]
        [string]$AssociatedObjectType
    )

    $Endpoint = "/crm/v3/objects/notes"

    if($Id){
        $Endpoint += "/$Id"
    }
    if($AssociatedObjectType){
        $Endpoint += "?associations=$AssociatedObjectType"
    }
    if($Properties){
        if($Endpoint.Contains('?')){
            $Endpoint += "&properties=$Properties"
        }
        else{
            $Endpoint += "?properties=$Properties"
        }
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint
    if($Req.results){
        return $Req.results
    }
    else{
        Return $Req
    }
}
function New-HubSpotNote {
    <#
    .SYNOPSIS
        Creates a new note in HubSpot.
    .DESCRIPTION
        Creates a new note that is associated with a given object.
    .EXAMPLE
        New-HubSpotNote -AssociatedObjectId 12345678 -AssociatedObjectType Deal -NoteBody "Hello world"
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/engagements/notes#create-a-note
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssociatedObjectId,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Contact","Company","Deal")]
        [string]$AssociatedObjectType,
        [Parameter(Mandatory = $true)]
        [string]$NoteBody,
        [Parameter(Mandatory = $false)]
        [string]$Timestamp = "auto"
    )

    $Endpoint = "/crm/v3/objects/notes"

    #Generate timestamp using current date if none provided
    if($Timestamp -eq "auto"){
        $Timestamp = GetHubSpotTimeStamp
    }

    $Body = @{
        properties = @{
            hs_note_body = $NoteBody
            hs_timestamp = $Timestamp
        }
    } | ConvertTo-Json

    $Note = InvokeHubSpotApi -Endpoint $Endpoint -Body $Body -Method Post

    #Now need to associate the note with something

    $AssociationType = $AssociatedObjectType + "_to_note"
    
    $Splat = @{
        BaseObject = $AssociatedObjectType
        BaseObjectId = $AssociatedObjectId
        RelatedObject = "Note"
        RelatedObjectId = $Note.id
        Type = $AssociationType
    }
    $Req = New-HubSpotAssociation @Splat

    return $Req

}
function Get-HubSpotUser {
    <#
    .SYNOPSIS
        Gets user accounts.
    .DESCRIPTION
        Gets user accounts, or a specific user by ID.
        Returns some basic properties by default, but you can include a list of properties to include. For a list of properties, see 'Get-HubSpotProperty -Object Users'
    .EXAMPLE
        #Specific properties to retrieve
        $PropertiesArray =@(
                "hs_deal_stage_probability",
                "hs_forecast_probability",
                "hs_manual_forecast_category",
                "dealtype",
                "dealstage",
                "amount",
                "createDate",
                "closeDate",
                "hs_closed_won_date"
        )
        $Properties = $PropertiesArray -join ','    
        Get-HubSpotDeal -Id "23008365181" -Properties $Properties

        #Get all deals
        Get-HubSpotDeal
    .LINK
        https://developers.hubspot.com/docs/guides/api/settings/users/user-details
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [string]$Properties = $null
    )

    if($Id){
        $Endpoint = "/crm/v3/objects/users/$Id"
    }
    else{
        $Endpoint = "/crm/v3/objects/users/"
    }
    
    if($Properties){
        $Endpoint += "?properties=$Properties"
    }

    $Req = InvokeHubSpotApi -Endpoint $Endpoint

    if($Id){
        Return $Req
    }
    else {
        Return $Req.results
    }
}
function Get-HubSpotOwner {
    <#
    .SYNOPSIS
        Gets owners from HubSpot.
    .EXAMPLE
        #Get all owners
        Get-HubSpotOwner

        #Get owner by Id
        Get-HubSpotOwner -Id 12345678
    .NOTES
        When using the -Archived switch, only owners who are archived will be returned. This is due to an API limitation on HubSpot's part.
    .LINK
        https://developers.hubspot.com/docs/reference/api/crm/owners
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Id,
        [Parameter(Mandatory = $false)]
        [switch]$Archived
    )

    if($Id){
        $Endpoint = "/crm/v3/owners/$Id"
        if($Archived){$Endpoint += "?archived=true"} #note that this ONLY returns archived owners

        $Req = InvokeHubSpotApi -Endpoint $Endpoint

        Return $Req
    }
    else{
        $Endpoint = "/crm/v3/owners/"
        if($Archived){$Endpoint += "?archived=true"} #note that this ONLY returns archived owners
        
        $Req = InvokeHubSpotApi -Endpoint $Endpoint

        Return $Req.results
    }
}
function Resolve-HubSpotOwner {
    <#
    .SYNOPSIS
        Resolves owner ID to a user object.
    .DESCRIPTION
        Resolves the user for a given owner Id and returns a custom user object.
    .EXAMPLE
        Resolve-HubSpotOwner -OwnerId 12345678
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/owners
        https://developers.hubspot.com/docs/guides/api/settings/users/user-details#retrieve-users
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OwnerId
    )

    $Owner = Get-HubSpotOwner -Id $OwnerId
    $Owner += Get-HubSpotOwner -Id $OwnerId
    $Properties = @(
        "hs_deactivated",
        "hs_email",
        "hs_family_name",
        "hs_given_name",
        "hs_internal_user_id",
        "hs_object_id"
    ) -join ','
    
    $User = Get-HubSpotUser -Properties $Properties | select -ExpandProperty properties | Where-Object{$_.hs_internal_user_id -eq $Owner.userId}
    
    Return $User
}
function Search-HubSpot {
    <#
    .SYNOPSIS
        Executes a search query, passed as a hashtable.
    .DESCRIPTION
        Executes a search query against a given object type, e.g. searching deals for that include "test" in the name.
    .EXAMPLE
        #Bloody hell the nesting
        $Query = @{
            "limit" = 200
            "filterGroups"= @(
                @{
                    "filters" = @(
                        @{
                            "propertyName" = "hs_lastmodifieddate"
                            "operator" = "GTE"
                            "value" = $Time
                        }
                    )
                }
            )
            "properties" = @("hs_lastmodifieddate","hs_object_id","name")
        }
        $Matches = Search-HubSpot -ObjectType contacts -Query $Query
    .NOTES
        The search endpoints are limited to 10,000 total results for any given query. Attempting to page beyond 10,000 will result in a 400 error.
        See links for other caveats and limits.
        Paging is handled automatically, with results fetched up to 200 at a time (according to the limit set in the query). It's strongly recommended to use limit=200 (the maximum) due to API rate limits
    .LINK
        https://developers.hubspot.com/docs/guides/api/crm/search
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("deals","contacts","companies")]
        [string]$ObjectType,
        [Parameter(Mandatory = $true)]
        [hashtable]$Query
    )

    $Endpoint = "/crm/v3/objects/$ObjectType/search"
    
    #Save the original query in case it has to be re-used for paging
    $OriginalQuery = $Query.Clone()

    $Req = InvokeHubSpotApi -Endpoint $Endpoint -Method Post -Body ($Query  | ConvertTo-Json -Depth 20)
    $Results = $Req.results

    #Search results are returned in pages but don't use normal pagination
    $ResultCount = $Req.total
    $i = $Req.results.Count
    
    if($env:HubSpotApiVerbosity -eq "Verbose"){
        Write-Host "Total search results: $ResultCount"
    }

    #If there are more results than are in the current page
    while($i -lt $ResultCount){
        #Build the paged query
        $Query = $OriginalQuery.Clone()
        $Query.Add("after",$i)
        $NextQuery = $Query | ConvertTo-Json -Depth 20
        
        $PageReq = InvokeHubSpotApi -Endpoint $Endpoint -Method Post -Body $NextQuery
        $PageCount = $PageReq.results.Count

        $i += $PageCount

        $Results += $PageReq.results

        #Throttling due to search API limits
        Start-Sleep -Milliseconds 500
    }

    Return $Results
}
