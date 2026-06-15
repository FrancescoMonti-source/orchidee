Add-Type -AssemblyName System.Drawing

$srcs = @(
  'ratb_global_heatmap_klebsiella_pneumoniae.png',
  'ratb_by_type_heatmap_klebsiella_pneumoniae.png',
  'ratb_incidence_global_heatmap_klebsiella_pneumoniae.png',
  'ratb_global_heatmap_enterobacterales.png'
)

$root = (Get-Location).Path
$outDir = Join-Path $root 'downloads\presentation_crops'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

foreach ($name in $srcs) {
  $path = Join-Path $root "downloads\$name"
  $bmp = [System.Drawing.Bitmap]::FromFile($path)
  $minX = $bmp.Width
  $minY = $bmp.Height
  $maxX = 0
  $maxY = 0

  for ($y = 0; $y -lt $bmp.Height; $y += 2) {
    for ($x = 0; $x -lt $bmp.Width; $x += 2) {
      $c = $bmp.GetPixel($x, $y)
      if (-not ($c.R -gt 246 -and $c.G -gt 246 -and $c.B -gt 246)) {
        if ($x -lt $minX) { $minX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }

  $pad = 24
  $minX = [Math]::Max(0, $minX - $pad)
  $minY = [Math]::Max(0, $minY - $pad)
  $maxX = [Math]::Min($bmp.Width - 1, $maxX + $pad)
  $maxY = [Math]::Min($bmp.Height - 1, $maxY + $pad)

  $rect = [System.Drawing.Rectangle]::new($minX, $minY, ($maxX - $minX + 1), ($maxY - $minY + 1))
  $crop = $bmp.Clone($rect, $bmp.PixelFormat)
  $out = Join-Path $outDir $name
  $crop.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $crop.Dispose()
  $bmp.Dispose()

  Write-Output "$name -> $($rect.Width)x$($rect.Height)"
}
