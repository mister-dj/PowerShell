param(
    [Parameter(Mandatory = $true)]
    [ipaddress]$Server,
    [Parameter(Mandatory = $true)]
    [int]$Port = 15600
)

#Opens new IPEndpoint on any IP and port
$Endpoint = new-object System.Net.IPEndpoint ([ipaddress]::any,0)
$Client = [Net.Sockets.TCPClient]$Endpoint 
$Client.Connect($Server,$Port)

$Continue = $true
Write-Host -ForegroundColor Green "Client started `n  stop client? (y)"
while($Continue){
    if((Read-Host) -eq 'y' ){
        $Continue = $false
        Write-Host -ForegroundColor Green "Stopping client"
    }
}

$Client.Close()
