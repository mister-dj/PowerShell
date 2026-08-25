Function Update-RunbookContent{
    <#
    .DESCRIPTION
        Updates the content of an Azure Automation Account Runbook.
    .EXAMPLE
        $Content = @"
            if($true){write-host "True is true"}
        "@

        Update-Runbookcontent.ps1 -AutomationAccountName "AutomationAccount" -ResourceGroupName "AutomationRG" -RunbookName "TestTrue" -Content $Content  -Publish
    .PARAMETER Publish
        This switch parameter will publish the runbook after successfully updating its content. If this is not specified, the updated content will remain in draft status.
    .LINK
        https://learn.microsoft.com/en-us/rest/api/automation/runbook-draft/replace-content?view=rest-automation-2024-10-23
        https://learn.microsoft.com/en-us/rest/api/automation/runbook/publish?view=rest-automation-2024-10-23&tabs=HTTP
    #>  
    param(
        [Parameter(Mandatory = $true)]
        [string]$AutomationAccountName,
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]$RunbookName,
        [string]$SubscriptionId = $null,
        [string]$ApiVersion = "2024-10-23",
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [switch]$Publish
    )

    #Use current AzContext subscription if none was specified
    if([string]::IsNullOrEmpty($SubscriptionId)){
        if($null -ne (Get-AzContext).Subscription.Id){
            $SubscriptionId = (Get-AzContext).Subscription.Id
        }
        else{
            throw "No subscription Id was specified and no AzContext was found."
        }
    }

    $URI = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$RunbookName/draft/content?api-version=$ApiVersion"

    #Get an auth token to use in API calls
    $AuthToken = (Get-AzAccessToken).token | ConvertFrom-SecureString -AsPlainText

    #Build auth headers with token
    $Headers = @{
        Authorization = "Bearer $AuthToken"
        "Content-Type" = "text/plain" #send the raw string content as the body
    }

    $Req = Invoke-WebRequest -Uri $URI -Headers $Headers -Body $Content -Method Put

    if($Req.StatusCode -ne 202){
        Write-Host -ForegroundColor Red "Failed to update runbook content."
        Write-Error $Req
    }
    else{
        Write-Host -ForegroundColor Green "Updated runbook content successfully."

        #Publish the runbook if parameter is specified. Without this, the newly updated content is in draft status
        if($Publish){
            $URI = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/runbooks/$RunbookName/publish?api-version=$ApiVersion"

            #Remove content-type as it isn't needed, keep the bearer token auth
            $Headers.Remove("Content-Type")

            $Req = Invoke-WebRequest -Uri $URI -Headers $Headers -Method Post

            if($Req.StatusCode -ne 202){
                Write-Host -ForegroundColor Red "Failed to publish runbook."
                Write-Error $Req
            }
            else{
                Write-Host -ForegroundColor Green "Published runbook successfully."
            }
        }
    }
}