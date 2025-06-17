<#
    .SYNOPSIS
    Creates a TCP listener (server) for testing network issues that affect TCP connections.

    .NOTES
    This script was inspired by Boe Prox's article "Checking For Disconnected Connections with TCPListener Using PowerShell".
    .LINK
    https://learn-powershell.net/2015/03/29/checking-for-disconnected-connections-with-tcplistener-using-powershell/
#>
Param(
    [int]$Port = 15600
)

#Stop any existing listeners
$Listener.Stop()
$Listener.Dispose()

$Listener = [System.Net.Sockets.TcpListener]$Port
$Listener.Start()

Write-Host -ForegroundColor Green "TCP listener started, awaiting client connection..."

$Continue = $true
While($Continue){
    #Wait for new connections
    If ($Listener.Pending()) {
        Write-Host -ForegroundColor Green "New connection from client found, accepting..."
        try{
            $Connection = $Listener.AcceptTcpClient()
            $ClientIp = $Connection.Client.RemoteEndPoint.Address.IPAddressToString
            Write-Host -ForegroundColor Green "Client $ClientIp connected!"
        }
        catch{
            Write-Host -ForegroundColor Red "Failed to accept client TCP connection"
        }
        
        #Now wait for connection to close
        While (
            -NOT ($Connection.Client.Poll(1,[System.Net.Sockets.SelectMode]::SelectRead) -AND
            $Connection.Client.Available -eq 0)) {
            Start-Sleep -Milliseconds 100
        }

        Write-Verbose "[$(Get-Date)] Connection has closed remotely"
    }
    else{
        Start-Sleep -Milliseconds 500
    }
}

$Listener.Stop()
$Listener.Dispose()