function Get-MacAddressVendor {
    <#
    .DESCRIPTION
        This is a simple utility command for querying MAC addresses to find their vendor using a free public API.
    .SYNOPSIS
        This function queries the maclookup.app API to find the vendor for a given MAC address, and return the vendor and, optionally, details on the MAC OUI.
        It supports multiple input formats: xx:xx:xx:xx:xx:xx, xx-xx-xx-xx-xx-xx, xx.xx.xx.xx.xx.xx, and xxxxxxxxxxxx.
    .PARAMETER MatchFilter
        This parameter accepts a string input and will only return query results where the vendor company contains the string (wildcard match). 
        When this parameter is used there is additional info sent via write-host to tell humans that it's working (otherwise you'd see a lot of nothing when querying large MAC arrays via loops). This output can be disabled with the -quiet parameter.
    .PARAMETER Quiet
        Disables human-friendly output when using MatchFilter
    .PARAMETER Detailed

    .EXAMPLE
        #Get the vendor for MAC 00098c006963
        Get-MacAddressVendor "00098c006963"
    .EXAMPLE
        #Get the vendor for MAC 00:09:8c:00:69:63
        Get-MacAddressVendor "00:09:8c:00:69:63"
    .EXAMPLE
        #Get the vendor for MAC 00:09:8c:00:69:63 and only return results where the vendor name contains "swede"
        Get-MacAddressVendor "00:09:8c:00:69:63"  -MatchFilter "swede"
    .NOTES
        This function uses a free, public API that has rate limits. The function includes a basic rate limit mechanism, and as such will be slow when querying many MACs in a loop - it will run ~1 query/second.
    .LINK
        https://maclookup.app/
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MacAddress,
        [switch]$Detailed,
        [string]$MatchFilter,
        [switch]$Quiet
    )
    $ApiBaseUrl = "https://api.maclookup.app/v2/macs/"

    #The MAC lookup site is a free public service with an API rate limit - so we need to be nice and respect that
    #Rate limit is 2 queries per second, this will limit to ~1/s
    #Basic rate limiting method for when this function is run in a loop
    [int]$Timestamp = Get-Date -UFormat "%s"
    if([int]$env:MacVendorRateLimitTimestamp -ge $Timestamp){Start-Sleep -Seconds 1}

    #Remove non-alphanumeric characters if needed to sanitize the MAC
    if($MacAddress -match '^[A-Za-z0-9]*$'){
        $CleanedMac = $MacAddress
        $ApiUrl = $ApiBaseUrl + $CleanedMac
    }
    else{
        $CleanedMac = $MacAddress.replace(':','').replace('-','').replace('.','')
        if(
            $CleanedMac -notmatch '^[A-Za-z0-9]*$'
        ){
                throw "Unable to sanitize MAC address"
        }
        else{
            $ApiUrl = $ApiBaseUrl + $CleanedMac
        }
    }

    #Write status if using filtering so humans don't think nothing is happening when doing filtered mass lookups
    if(![string]::IsNullOrEmpty($MatchFilter) -and !$Quiet){
        Write-Host -ForegroundColor Gray "Querying vendor for MAC: $CleanedMac"
    }

    #Filter for broadcast address
    if($CleanedMac -eq "ffffffffffff"){
        $Output = [pscustomobject]@{
            MAC = $CleanedMac
            Company = "n/a - Broadcast address"
        }
    }
    else{
        #Call API to query MAC vendor
        $Req = Invoke-WebRequest -Uri $ApiUrl
        #Parse JSON and convert to object
        $Result = $Req.Content | ConvertFrom-Json

        #Initial output formatting and error handling
        if($Result.success){
            if($Result.found){
                #More info
                if($Detailed){
                    $Output = [pscustomobject]@{
                        MAC = $CleanedMac
                        Company = $Result.company
                        CompanyAddress = $Result.address
                        Country = $Result.country
                        PrefixBlockStart = $Result.blockStart
                        PrefixBlockEnd = $Result.blockEnd
                        MacAssignmentUpdate = $Result.updated
                    }                
                }
                #Default info
                else{
                    $Output = [pscustomobject]@{
                        MAC = $CleanedMac
                        Company = $Result.company
                    } 
                }
            }
            else{
                Write-Warning "$($MacAddress) | Unknown MAC vendor"
            }
        }
        else{
            Write-Error "$($MacAddress) | MAC OUI lookup failed"
        }
    }
    
    #Timestamp for rate limiting before returning output
    $env:MacVendorRateLimitTimestamp = Get-Date -UFormat "%s"

    #Return output, optionally with filtering
    if([string]::IsNullOrEmpty($MatchFilter)){
        Return $Output
    }
    else{
        if($Output.Company -like "*$MatchFilter*"){
            Return $Output
        }
    }
}
