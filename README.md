# yipai360.com-photo-downloader
A PowerShell script that downloads photos from yipai360 album IDs into separate local folders by calling the platform’s photo listing API, testing candidate image links, and saving each file with a sanitized filename.

## How to run
Save the file as, for example, `photo-downloader.ps1`, then run it in PowerShell:

```
powershell -ExecutionPolicy Bypass -File .\photo-downloader.ps1
```

When prompted, enter:

- target folder path, for example `C:\Users\TestUser\Downloads\2026`
- album IDs separated by commas, for example `20260622124016233368,20260621083938197471,20260622124843358327`

`Read-Host` is the standard PowerShell way to collect interactive console input, and splitting a single input string into an array is a common pattern for multiple values.

## Optional parameter version
If you want the user to pass values directly on the command line instead of typing them interactively, a PowerShell script can also define named parameters and let PowerShell prompt for mandatory values when not supplied. For example, the run pattern would be:

```
powershell -ExecutionPolicy Bypass -File .\photo-downloader.ps1 -TargetDir "C:\Users\TestUser\Downloads\2026" -AlbumOrders "20260622124016233368","20260621083938197471","20260622124843358327"
```
