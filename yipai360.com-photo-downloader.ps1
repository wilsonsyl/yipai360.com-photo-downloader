$ErrorActionPreference = 'Stop'

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    "Accept"     = "application/json, text/plain, */*"
    "Referer"    = "https://www.yipai360.com/"
    "Origin"     = "https://www.yipai360.com"
}

function Get-Json {
    param([string]$Url)
    Invoke-RestMethod -Uri $Url -Headers $headers -Method Get
}

function Get-PhotoItemsFromResponse {
    param($Resp)

    if ($null -eq $Resp -or $null -eq $Resp.data) {
        return @()
    }

    $data = $Resp.data

    if ($data -is [System.Collections.IEnumerable] -and -not ($data -is [string])) {
        $arr = @($data)
        if ($arr.Count -gt 0) { return $arr }
    }

    if ($data.PSObject -and $data.PSObject.Properties) {
        foreach ($p in $data.PSObject.Properties) {
            $v = $p.Value
            if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
                $arr = @($v)
                if ($arr.Count -gt 0) { return $arr }
            }
        }
    }

    return @()
}

function Join-Url {
    param(
        [string]$Base,
        [string]$Path,
        [string]$Query
    )

    if ([string]::IsNullOrWhiteSpace($Base) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $u = $Base.TrimEnd('/') + $Path
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $u += $Query
    }
    return $u
}

function Get-CandidateUrlsFromImgObject {
    param($Item)

    $list = New-Object System.Collections.Generic.List[string]

    if (-not ($Item.PSObject.Properties.Name -contains 'img')) {
        return @()
    }

    $img = $Item.img
    if ($null -eq $img) {
        return @()
    }

    if (-not ($img -is [System.Management.Automation.PSCustomObject])) {
        return @()
    }

    $primary  = if ($img.PSObject.Properties.Name -contains 'primary')  { [string]$img.primary }  else { $null }
    $failover = if ($img.PSObject.Properties.Name -contains 'failover') { [string]$img.failover } else { $null }
    $path     = if ($img.PSObject.Properties.Name -contains 'path')     { [string]$img.path }     else { $null }
    $sign     = if ($img.PSObject.Properties.Name -contains 'sign')     { [string]$img.sign }     else { $null }
    $s1920    = if ($img.PSObject.Properties.Name -contains 's1920')    { [string]$img.s1920 }    else { $null }
    $s1080    = if ($img.PSObject.Properties.Name -contains 's1080')    { [string]$img.s1080 }    else { $null }
    $s375     = if ($img.PSObject.Properties.Name -contains 's375')     { [string]$img.s375 }     else { $null }

    $bases = @()
    if (-not [string]::IsNullOrWhiteSpace($primary))  { $bases += $primary }
    if (-not [string]::IsNullOrWhiteSpace($failover)) { $bases += $failover }

    foreach ($b in $bases) {
        foreach ($q in @($sign, $s1920, $s1080, $s375)) {
            $u = Join-Url -Base $b -Path $path -Query $q
            if (-not [string]::IsNullOrWhiteSpace($u) -and $list -notcontains $u) {
                $list.Add($u)
            }
        }
    }

    return @($list)
}

function Test-UrlWorks {
    param([string]$Url)

    try {
        $r = Invoke-WebRequest -Uri $Url -Headers $headers -Method Head -TimeoutSec 20 -ErrorAction Stop
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) {
            return $true
        }
    }
    catch {
        try {
            $r = Invoke-WebRequest -Uri $Url -Headers $headers -Method Get -TimeoutSec 20 -MaximumRedirection 5 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) {
                return $true
            }
        }
        catch {
        }
    }

    return $false
}

function Get-FileExtension {
    param($Item)

    if ($Item.PSObject.Properties.Name -contains 'ext') {
        $ext = [string]$Item.ext
        if (-not [string]::IsNullOrWhiteSpace($ext)) {
            return "." + $ext.TrimStart('.').ToLowerInvariant()
        }
    }

    if ($Item.PSObject.Properties.Name -contains 'fname') {
        $fname = [string]$Item.fname
        $ext = [System.IO.Path]::GetExtension($fname)
        if (-not [string]::IsNullOrWhiteSpace($ext)) {
            return $ext.ToLowerInvariant()
        }
    }

    return ".jpg"
}

function Get-BaseFileName {
    param($Item, [int]$Page, [int]$Index)

    if ($Item.PSObject.Properties.Name -contains 'fname') {
        $fname = [string]$Item.fname
        if (-not [string]::IsNullOrWhiteSpace($fname)) {
            return [System.IO.Path]::GetFileNameWithoutExtension($fname)
        }
    }

    return ("photo_{0:D3}_{1:D3}" -f $Page, $Index)
}

function Get-UserInput {
    $targetDirInput = Read-Host "Enter target folder path"
    if ([string]::IsNullOrWhiteSpace($targetDirInput)) {
        throw "Target folder path cannot be empty."
    }

    $albumInput = Read-Host "Enter album order IDs separated by commas"
    if ([string]::IsNullOrWhiteSpace($albumInput)) {
        throw "Album order IDs cannot be empty."
    }

    $albumOrders = $albumInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    if ($albumOrders.Count -eq 0) {
        throw "No valid album order IDs were provided."
    }

    return @{
        TargetDir   = $targetDirInput
        AlbumOrders = $albumOrders
    }
}

$inputData = Get-UserInput
$targetDir = $inputData.TargetDir
$albumOrders = $inputData.AlbumOrders

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

foreach ($orderId in $albumOrders) {
    Write-Host ""
    Write-Host "Processing album $orderId"

    $albumDir = Join-Path $targetDir $orderId
    New-Item -ItemType Directory -Path $albumDir -Force | Out-Null

    $page = 1
    $pageSize = 100
    $downloaded = 0
    $seenUrls = @{}
    $seenNames = @{}

    do {
        $apiUrl = "https://www.yipai360.com/api/v1/yipai/order/$orderId/audience/photos?tagId=&sortType=desc&page=$page&pageSize=$pageSize"

        try {
            $resp = Get-Json -Url $apiUrl
        }
        catch {
            Write-Warning "Failed to fetch page $page for ${orderId}: $_"
            break
        }

        $items = @(Get-PhotoItemsFromResponse -Resp $resp)
        Write-Host "Page ${page}: $($items.Count) photo items"

        if ($items.Count -eq 0) {
            break
        }

        $i = 1
        foreach ($item in $items) {
            $candidates = @(Get-CandidateUrlsFromImgObject -Item $item)

            $working = $null
            foreach ($u in $candidates) {
                if ($seenUrls.ContainsKey($u)) {
                    $working = $u
                    break
                }

                if (Test-UrlWorks -Url $u) {
                    $seenUrls[$u] = $true
                    $working = $u
                    break
                }
            }

            if ($working) {
                $baseName = Get-BaseFileName -Item $item -Page $page -Index $i
                $ext = Get-FileExtension -Item $item
                $safeBase = ($baseName -replace '[\\/:*?"<>|]', '_')
                $fileName = $safeBase + $ext

                if ($seenNames.ContainsKey($fileName)) {
                    $fileName = "{0}_{1:D3}_{2}" -f $orderId, $i, $fileName
                }

                $outFile = Join-Path $albumDir $fileName

                try {
                    Invoke-WebRequest -Uri $working -Headers $headers -OutFile $outFile -TimeoutSec 60
                    Write-Host "Saved: $outFile"
                    $seenNames[$fileName] = $true
                    $downloaded++
                }
                catch {
                    Write-Warning "Failed final download: $working -> $_"
                }
            }

            $i++
        }

        if ($items.Count -lt $pageSize) {
            break
        }

        $page++
        Start-Sleep -Milliseconds 200

    } while ($true)

    Write-Host "Album ${orderId}: downloaded $downloaded files"
}

Write-Host ""
Write-Host "Done. Files saved in $targetDir"
