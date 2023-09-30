<#
  ╓──────────────────────────────────────────────────────────────────────────────────────
  ║   PowerShell.Module.Core            
  ║   
  ║   Power.ps1
  ╙──────────────────────────────────────────────────────────────────────────────────────
 #>

[CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Position=0,Mandatory=$false)]
        [int]$StatusBarTime = 5
    ) 

function Invoke-AutoUpdateProgress{
  [int32]$PercentComplete = (($Script:StepNumber / $Script:TotalSteps) * 100)
  if($PercentComplete -gt 100){$PercentComplete = 100}
    Write-Progress -Activity $Script:ProgressTitle -Status $Script:ProgressMessage -PercentComplete $PercentComplete
    if($Script:StepNumber -lt $Script:TotalSteps){$Script:StepNumber++}
}


function Get-IPGeoLocation {
    <#
    .Synopsis
    Resolve IPAddress Geo IP Location
    .Description
    This Function Queries The IP API With Supplied IPAdderess And Returns Geo IP Location
    .Parameter IPAddress
    IPAddressTo Be Resolved
    .Example
    Get-IPGeoLocation -IPAddress 96.23.36.24
    .Example
    $IP = Get-NetStat | select -ExpandProperty ForeignAddressIP | Where-Object {$_ -notlike '`['}
    Get-IPGeoLocation -IPAddress $IP
    .Example
    $IP = (Get-NetTCPConnection).remoteaddress | Where-Object {$_ -notmatch '0.0.0.0|:'}  | Where-Object {$_ -notmatch '127.0.0.1|:'} 
    Get-IPGeoLocation -IPAddress $IP
    #>
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $true,
            ValueFromPipeline = $false)]
        [ValidatePattern("(?:(?:1\d\d|2[0-5][0-5]|2[0-4]\d|0?[1-9]\d|0?0?\d)\.){3}(?:1\d\d|2[0-5][0-5]|2[0-4]\d|0?[1-9]\d|0?0?\d)")]
        [string[]]$IPAddress
    )
    begin {
        $CurrentIP = 0
    }
    process {    
        foreach ($IP in $IPAddress) {
            $CurrentIP++
            Write-Progress -Activity "Resoving IPAddress: $IP" -Status "$CurrentIP of $($IPAddress.Count)" -PercentComplete (($CurrentIP / $IPAddress.Count) * 100)
            try {
                Write-Verbose 'Sending Request to http://ip-api.com/json/'
                Invoke-RestMethod -Method Get -Uri "http://ip-api.com/json/$IP" -ErrorAction SilentlyContinue | Foreach-object {
                    [pscustomobject]@{
                        IPAddress     = $IP
                        Country       = $_.Country
                        CountryCode   = $_.CountryCode
                        Region        = $_.Region
                        RegionName    = $_.RegionName
                        City          = $_.City
                        'Postal Code' = $_.Zip
                        Org           = $_.Org
                        ISP           = $_.ISP
                        as            = $_.as
                        Query         = $_.Query
                        Lat           = $_.Lat
                        Lon           = $_.Lon
                        TimeZone      = $_.TimeZone
                    }
                }
            }
            catch {
                Write-Warning -Message "$IP : $_"
            }
            Start-Sleep -Seconds 1
        }
    }
    end { }
        
}



function Resolve-IPAddress{
   [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,Position=0)]
        [string]$Hostname,
        [Parameter(Mandatory=$false)]
        [Hashtable]$HostEntries
    ) 

    Write-verbose "[resolving] $Hostname... "
    $Result = (Test-NetConnection -ComputerName "$Hostname" -EA Ignore)
    
    if( $($Result.PingSucceeded) -eq $True ){
        $ip   = $Result.RemoteAddress
        $dest = $Result.ComputerName

        Write-verbose "[success]  $ip ($dest)" 

        if($PSBoundParameters.ContainsKey('HostEntries') -eq $True){
            Write-verbose "[HostEntries]  updating  HostEntries" 
            $HostEntries["$dest"] = "$ip"
        }
        return $ip
    }
    return ''
}


function Invoke-TestNetSpeed{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$True, Position=0)]
        [string]$Url,
        [Parameter(Mandatory=$false)]
        [switch]$SaveSamples
    ) 
    try{
        [string]$sfile = ((Get-Date -UFormat %s) -as [string])
        [System.Collections.ArrayList]$samplesBps = [System.Collections.ArrayList]::new()
        $Path = "c:\Tmp\$sfile"
        new-item -path $Path -ItemType 'File' -Force | Out-Null
        remove-item -path $Path -Force | Out-Null

        $SpeedSamplePath = "$PSScriptRoot\Bps.json"
        remove-item -path $SpeedSamplePath -Force -ErrorAction Ignore | Out-Null
        $uri = New-Object "System.Uri" "$Url"
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.PreAuthenticate = $false
        $request.Method = 'GET'
        $request.Headers = New-Object System.Net.WebHeaderCollection
       # $request.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.51 Safari/537.36')

        # 15 second timeout
        $request.set_Timeout(15000) 

        # Cache Policy : no cache
        $request.CachePolicy                  = New-Object Net.Cache.RequestCachePolicy([Net.Cache.RequestCacheLevel]::NoCacheNoStore)
        [string]$Script:ProgressMessage  = ' '
        # create the Stream, FileStream and WebResponse objects
        [System.Net.WebResponse]$response     = $request.GetResponse()
        [System.IO.Stream]$responseStream     = $response.GetResponseStream()
        [System.IO.FileStream]$targetStream   = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Create)
        $Script:TotalSteps                    = [System.Math]::Floor($response.get_ContentLength())
        $Script:ProgressTitle                 = "Network Speed Test"
        $startTime                            = [DateTime]::Now
        $lastUpdate                           = [DateTime]::Now
        $buffer                               = new-object byte[] 10KB
        $count                                = $responseStream.Read($buffer,0,$buffer.length)
        $dlkb                                 = 0
        $downloadedBytes                      = 0
        $totalTicks                           = 0
                           
        
        while ($count -gt 0){
           $targetStream.Write($buffer, 0, $count)
           $count                   = $responseStream.Read($buffer,0,$buffer.length)
           $downloadedBytes         = $downloadedBytes + $count
           $dlkb                    = $([System.Math]::Floor($downloadedBytes/1024))
           $segmentUpdate           = [DateTime]::Now
           $timeTakenSegment        = New-TimeSpan $startTime $lastUpdate
           $lastUpdate              = [DateTime]::Now
           $milliseconds            = $timeTakenSegment.TotalMilliseconds

           if($SaveSamples){
             $bps                     = $count / $milliseconds
             $BpsSample               = "{0:n2}" -f $bps
             [PSCustomObject]$o       = [PSCustomObject]@{
                BpsSample = $BpsSample
                SegmentMs = $milliseconds
             }
             [void]$samplesBps.Add($o)
           }

           $timeTaken               = New-TimeSpan $startTime $lastUpdate
           $segmentUpdate           = [DateTime]::Now
           $lastUpdate              = [DateTime]::Now
           $Script:StepNumber       = $downloadedBytes   
           
           Invoke-AutoUpdateProgress
           
        }
        if($SaveSamples){
            $samplesBps | ConvertTo-Json | Set-Content -Path $SpeedSamplePath 
        }

        $targetStream.Flush()
        $targetStream.Close()
        $targetStream.Dispose()
        $responseStream.Dispose()
        
        Remove-Item -Path $Path -Force -ErrorAction Ignore | Out-Null

        $endUpdate               = [DateTime]::Now
        $timeTaken               = New-TimeSpan $startTime $endUpdate
        $bps                     = ($downloadedBytes/$($timeTaken.TotalSeconds))
        $mbs                     = $bps/1Mb
        $kbs                     = $bps/1Kb
        $MbSec                   = "{0:n2}" -f $mbs
        $KbSec                   = "{0:n2}" -f $kbs
        $BytesSec                = "{0:n2}" -f $bps

        [PSCustomObject]$Ret     = [PSCustomObject]@{
              Url                = $Url
              MbSec              = $MbSec
              KbSec              = $KbSec
              BytesSec           = $BytesSec 
              DownloadedBytes    = $downloadedBytes
              TotalSeconds       = $timeTaken.TotalSeconds
        }

        return $Ret
    }catch{
        Write-Error $_
    }
}

[Uri]$u = "https://github.com/arsscriptum/NetworkTest.Repository/raw/master/TenMegabytes.txt"

$data = Invoke-TestNetSpeed -Url "$($u.AbsoluteUri)"

Write-Output "MbSec           : $($data.MbSec)"
Write-Output "KbSec           : $($data.KbSec)"
Write-Output "BytesSec        : $($data.BytesSec)"
Write-Output "DownloadedBytes : $($data.DownloadedBytes)"
Write-Output "TotalSeconds    : $($data.TotalSeconds)"
$ServerIp = Resolve-IPAddress -Hostname "$($u.Host)"
$Location = Get-IPGeoLocation -IPAddress "$ServerIp"

Write-Output "Server location, $($Location.City), $($Location.RegionName), $($Location.Country)"