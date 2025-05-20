<#
This script is intended to be packaged as a Win32 app in Intune along with an Adobe extension file (.zxp).

It will install the extention file (passed via the ExtensionFileName parameter) or uninstall a given extension via the extension name.

To find the name of an extension (in order to then script it's removal) you can run "UnifiedPluginInstallerAgent.exe /list all".


Usage examples:
#Install the "ci-hub" extension:
.\AdobeExtensionInstaller.ps1 -ExtensionFileName ci-hub.zxp

#Uninstall the CI-Hub extension:
.\AdobeExtensionInstaller.ps1 -Uninstall -ExtensionName CI_Hub_CC_Connector


Folder to use for Intune app detection rule: "C:\Program Files (x86)\Common Files\Adobe\CEP\extensions\CI_Hub_CC_Connector"
#>

param(
    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$Uninstall,
    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$ExtensionName,
    [Parameter(ParameterSetName = 'Install')]
    [string]$ExtensionFileName
)


#https://helpx.adobe.com/creative-cloud/help/working-from-the-command-line.html
$UPIA = "C:\Program Files\Common Files\Adobe\Adobe Desktop Common\RemoteComponents\UPI\UnifiedPluginInstallerAgent\UnifiedPluginInstallerAgent.exe"


if(Test-Path $UPIA){
    #Uninstall
    if($Uninstall){
        try{
            $PluginName = '"' + $ExtensionName + '"'
            $Process = Start-Process -Wait -FilePath $UPIA -ArgumentList "/remove $PluginName" -PassThru -NoNewWindow
            return $Process.ExitCode
        }
        catch{
            Write-Error "Failed to install extension"
        }

    }
    #Install
    else{
        $ExtensionPath = '"' + $PSScriptRoot + '\' + $ExtensionFileName + '"'

        try{
            $Process = Start-Process -Wait -FilePath $UPIA -ArgumentList "/install $ExtensionPath" -PassThru -NoNewWindow
            return $Process.ExitCode
        }
        catch{
            Write-Error "Failed to install extension"
        }
    }
}
else{
    Write-Error "Adobe Unified Plugin Installer Agent executable not detected, aborting."
}
