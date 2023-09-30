
    [CmdletBinding(SupportsShouldProcess)]
    param()

function Invoke-BuildTestApp{
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try{
        Import-Module PowerShell.Module.Compiler -Force 
        $m = Get-Module "PowerShell.Module.Compiler" -ea Ignore
        if($Null -eq $m){throw "no compiler module" }
        rm NetworkSpeedTest.exe -EA Ignore -Force
        $Null = cl .\NetworkSpeedTest.ps1 -noError
        if(Test-Path ./NetworkSpeedTest.exe){
                Write-Host '[OK] ' -f DarkGreen -NoNewLine
                Write-Host "NetworkSpeedTest.exe compiled" -f Gray 
        }
        
 
    }catch{
        Write-Error "$_"
    }
}


Invoke-BuildTestApp