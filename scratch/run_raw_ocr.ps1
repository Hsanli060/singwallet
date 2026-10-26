Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) {
    $langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($langs[0])
}

$images = @(
    "C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852462_4f8ed2f2.jpg",
    "C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852463_ce555f09.jpg",
    "C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852465_c5e54fb3.jpg",
    "C:\Users\hsanl\.gemini\antigravity\brain\a3ba1530-4be0-43d0-b3fc-7c7176592cd5\.user_uploaded\media_1793001852466_7ec82ee1.jpg"
)

$results = @()

foreach ($imgPath in $images) {
    $fileTask = [Windows.Storage.StorageFile]::GetFileFromPathAsync($imgPath)
    $file = Await $fileTask ([Windows.Storage.StorageFile])
    
    $streamTask = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read)
    $stream = Await $streamTask ([Windows.Storage.Streams.IRandomAccessStream])
    
    $decoderTask = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
    $decoder = Await $decoderTask ([Windows.Graphics.Imaging.BitmapDecoder])
    
    $bitmapTask = $decoder.GetSoftwareBitmapAsync()
    $bitmap = Await $bitmapTask ([Windows.Graphics.Imaging.SoftwareBitmap])
    
    $ocrTask = $engine.RecognizeAsync($bitmap)
    $ocrResult = Await $ocrTask ([Windows.Media.Ocr.OcrResult])
    
    $imgWidth = $bitmap.PixelWidth
    $imgHeight = $bitmap.PixelHeight
    
    $lines = @()
    foreach ($line in $ocrResult.Lines) {
        $minX = 999999.0
        $minY = 999999.0
        $maxX = 0.0
        $maxY = 0.0
        
        foreach ($w in $line.Words) {
            $r = $w.BoundingRect
            if ($r.X -lt $minX) { $minX = $r.X }
            if ($r.Y -lt $minY) { $minY = $r.Y }
            if (($r.X + $r.Width) -gt $maxX) { $maxX = ($r.X + $r.Width) }
            if (($r.Y + $r.Height) -gt $maxY) { $maxY = ($r.Y + $r.Height) }
        }
        
        $boxW = [Math]::Max(1.0, ($maxX - $minX))
        $boxH = [Math]::Max(1.0, ($maxY - $minY))
        
        $lines += [PSCustomObject]@{
            Text = $line.Text
            Box = [PSCustomObject]@{
                Left = [Math]::Round($minX / $imgWidth, 4)
                Top = [Math]::Round($minY / $imgHeight, 4)
                Width = [Math]::Round($boxW / $imgWidth, 4)
                Height = [Math]::Round($boxH / $imgHeight, 4)
            }
            RawBox = [PSCustomObject]@{
                X = [Math]::Round($minX, 1)
                Y = [Math]::Round($minY, 1)
                Width = [Math]::Round($boxW, 1)
                Height = [Math]::Round($boxH, 1)
            }
        }
    }
    
    $results += [PSCustomObject]@{
        ImagePath = $imgPath
        ImageWidth = $imgWidth
        ImageHeight = $imgHeight
        LineCount = $lines.Count
        Lines = $lines
    }
}

$json = $results | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText("c:\Other\Projects\singwallet\scratch\ocr_raw_extracted.json", $json, [System.Text.Encoding]::UTF8)
Write-Host "ALL OCR EXTRACTIONS SAVED AS CLEAN UTF8!"
