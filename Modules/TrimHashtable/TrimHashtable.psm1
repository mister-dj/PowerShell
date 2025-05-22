function TrimHashTable{
    <#
    .SYNOPSIS
        Removes empty string or null value keys from a hashtable
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [object]$Hashtable,
        [Parameter(Mandatory = $False)]
        [switch]$AllowEmptyStrings = $false
    )

    $CleanHashtable = @{}
    $Keys = $Hashtable.Keys
    foreach ($Key in $Keys){
        if($AllowEmptyStrings){
            if($null -ne $Hashtable.$Key){
                $CleanHashtable.Add($Key,$Hashtable.$Key)
            }
        }
        else{
            if(($Hashtable.$Key -ne "") -and ($null -ne $Hashtable.$Key)){
                $CleanHashtable.Add($Key,$Hashtable.$Key)
            }
        }
    }
    return $CleanHashtable
}