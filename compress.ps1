# FFmpeg Video Compressor PowerShell Script (2025 Edition)
# Optimized for Discord with multiple compatibility modes

param(
    [Parameter(Position=0)]
    [string]$InputFile
)

# Function to format file size with appropriate unit
function Format-FileSize {
    param([long]$Size)
    
    if ($Size -ge 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -ge 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -ge 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "$Size Bytes"
    }
}

# Check if input file was provided
if (-not $InputFile) {
    Write-Host "Please drag a video file onto this script." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

# Check if the file exists
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Host "File not found: $InputFile" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Get script directory and check for ffmpeg and ffprobe in the same folder
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpegPath = "ffmpeg"
$ffprobePath = "ffprobe"

# Check if ffmpeg.exe exists in the same directory as the script
if (Test-Path (Join-Path $scriptDirectory "ffmpeg.exe")) {
    $ffmpegPath = Join-Path $scriptDirectory "ffmpeg.exe"
    Write-Host "Using ffmpeg from script directory: $ffmpegPath" -ForegroundColor Green
}

# Check if ffprobe.exe exists in the same directory as the script
if (Test-Path (Join-Path $scriptDirectory "ffprobe.exe")) {
    $ffprobePath = Join-Path $scriptDirectory "ffprobe.exe"
    Write-Host "Using ffprobe from script directory: $ffprobePath" -ForegroundColor Green
}

# Get file information - using more explicit path handling
$fileName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
$filePath = [System.IO.Path]::GetDirectoryName($InputFile)
# Make sure we have valid paths
if ([string]::IsNullOrEmpty($fileName) -or [string]::IsNullOrEmpty($filePath)) {
    Write-Host "Error processing file path. Using default naming." -ForegroundColor Yellow
    $fileName = "video"
    $filePath = $scriptDirectory
}

# Get target size from user
Write-Host "Current file size: $(Format-FileSize (Get-Item -LiteralPath $InputFile).Length)" -ForegroundColor Cyan
$targetSizeMB = Read-Host "Enter target size in MB (default: 10)"
if (-not $targetSizeMB) { $targetSizeMB = 10 }
try {
    $targetSizeMB = [double]$targetSizeMB
} catch {
    Write-Host "Invalid input. Using default of 10MB." -ForegroundColor Yellow
    $targetSizeMB = 10
}

# Display compatibility mode options
Write-Host "`nCompatibility Mode Options:" -ForegroundColor Cyan
Write-Host "1: Modern Compatibility (H.265/MP4) - Better compression, works on all modern platforms" -ForegroundColor White
Write-Host "2: Universal Compatibility (H.264/MP4) - Good compression, works on older plaforms" -ForegroundColor White
Write-Host "3: Desktop Only (VP9/WebM) - Best quality-to-size ratio, doesn't work on iOS at all" -ForegroundColor White

# Get compatibility mode from user
$compatibilityMode = Read-Host "`nSelect compatibility mode (1-3, default: 1)"
if (-not $compatibilityMode -or -not ($compatibilityMode -match '^[1-3]$')) { 
    $compatibilityMode = 1 
    Write-Host "Using default: Modern Compatibility (H.265/MP4)" -ForegroundColor Yellow
}

# Set codec and container based on compatibility mode
switch ($compatibilityMode) {
    1 {
        $codec = "libx265"
        $codecName = "H.265"
        $container = "mp4"
        $audioCodec = "copy"
        $outputFile = Join-Path $filePath ($fileName + "_h265.mp4")
    }
    2 {
        $codec = "libx264"
        $codecName = "H.264"
        $container = "mp4"
        $audioCodec = "copy"
        $outputFile = Join-Path $filePath ($fileName + "_h264.mp4")
    }
    3 {
        $codec = "libvpx-vp9"
        $codecName = "VP9"
        $container = "webm"
        $audioCodec = "libopus" # WebM only supports Vorbis or Opus audio
        $audioBitrateValue = "128k" # Set a reasonable audio bitrate for Opus
        $outputFile = Join-Path $filePath ($fileName + "_vp9.webm")
    }
}

# Ask if user wants to use CRF mode
$encodingMode = Read-Host "`nUse CRF mode for faster encoding? (y/n, default: n)"
$useCRF = $encodingMode.ToLower() -eq "y"

# Set codec-specific parameters
$codecParams = @{
    "libx265" = @{
        "preset" = "medium" # H.265 is already slow, so using medium preset
        "crf" = 28 # H.265 uses different CRF scale, ~28 is roughly equivalent to H.264's 23
        "extraParams" = "-tag:v hvc1" # Add proper tag for iOS compatibility
    }
    "libx264" = @{
        "preset" = "veryslow"
        "crf" = 23
        "extraParams" = ""
    }
    "libvpx-vp9" = @{
        "preset" = ""
        "crf" = 31 # VP9 uses different CRF scale
        "extraParams" = "-b:v 0 -deadline good -cpu-used 2 -row-mt 1"
    }
}

# If using CRF, ask for CRF value
$crfValue = $codecParams[$codec]["crf"]
if ($useCRF) {
    $crf_explanation = ""
    switch ($codec) {
        "libx265" { $crf_explanation = "(24-34 recommended, lower = better quality, default: 28)" }
        "libx264" { $crf_explanation = "(18-28 recommended, lower = better quality, default: 23)" }
        "libvpx-vp9" { $crf_explanation = "(30-35 recommended, lower = better quality, default: 31)" }
    }
    
    $crfInput = Read-Host "Enter CRF value $crf_explanation"
    if ($crfInput -match '^\d+$') {
        $crfValue = [int]$crfInput
        # Ensure CRF is within reasonable range
        if ($crfValue -lt 0) { $crfValue = 0 }
        if ($crfValue -gt 51) { $crfValue = 51 }
    }
}

# Only calculate bitrate if not using CRF mode
if (-not $useCRF) {
    # Apply variable safety margin based on target size
    $safetyMargin = 0.95 # Default 5% margin
    
    if ($targetSizeMB -ge 50 -and $targetSizeMB -lt 200) {
        $safetyMargin = 0.97 # 3% margin for medium files
    } elseif ($targetSizeMB -ge 200) {
        $safetyMargin = 0.98 # 2% margin for large files
    }
    
    $adjustedTargetMB = $targetSizeMB * $safetyMargin
    $marginPercent = (1 - $safetyMargin) * 100
    
    Write-Host "Using $($adjustedTargetMB.ToString('0.0')) MB as working target ($(($safetyMargin*100).ToString('0.0'))% of $targetSizeMB MB) with a $($marginPercent.ToString('0.0'))% safety margin" -ForegroundColor Cyan

    # Convert MB to bits (1 MB = 8,388,608 bits)
    $targetSizeBits = $adjustedTargetMB * 8388608
}

# Get video duration using ffprobe
try {
    $durationOutput = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$InputFile"
    $duration = [double]$durationOutput
    if ($duration -le 0) { $duration = 1 }
} catch {
    Write-Host "Error getting video duration. Using default value." -ForegroundColor Red
    $duration = 1
}

# Calculate bitrate if not using CRF
if (-not $useCRF) {
    # Calculate total bitrate (bits per second)
    $totalBitrateKbps = [int]($targetSizeBits / $duration / 1000)

    # Reserve bitrate for audio (160 kbps typical for good quality)
    $audioBitrateKbps = 160
    $videoBitrateKbps = $totalBitrateKbps - $audioBitrateKbps

    # Ensure minimum video bitrate
    if ($videoBitrateKbps -lt 100) { $videoBitrateKbps = 100 }
}

# Get original resolution
try {
    $resolutionOutput = & $ffprobePath -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$InputFile"
    $resolution = $resolutionOutput.Trim()
    $width, $height = $resolution -split 'x'
    $width = [int]$width
    $height = [int]$height
} catch {
    Write-Host "Error getting video resolution. Using default values." -ForegroundColor Red
    $width = 1920
    $height = 1080
}

# Determine target height based on available bitrate
$targetHeight = $height

# Only apply resolution table if not using CRF
if (-not $useCRF) {
    # Resolution table based on bitrate thresholds
    if ($videoBitrateKbps -lt 400) {
        $targetHeight = 360
    } elseif ($videoBitrateKbps -lt 800) {
        $targetHeight = 480
    } elseif ($videoBitrateKbps -lt 1500) {
        $targetHeight = 720
    } elseif ($videoBitrateKbps -lt 4000) {
        if ($height -gt 1080) {
            $targetHeight = 1080
        }
    }
}

# Display encoding parameters
Write-Host "`nEncoding Parameters:" -ForegroundColor Cyan
Write-Host "Input: $InputFile" -ForegroundColor White
Write-Host "Duration: $duration seconds" -ForegroundColor White
Write-Host "Original Resolution: ${width}x${height}" -ForegroundColor White
Write-Host "Codec: $codecName ($codec)" -ForegroundColor White
Write-Host "Container: $container" -ForegroundColor White

if ($codec -eq "libvpx-vp9") {
    Write-Host "Audio Codec: Opus (required for WebM)" -ForegroundColor White
    Write-Host "Audio Bitrate: $audioBitrateValue" -ForegroundColor White
}

if ($useCRF) {
    Write-Host "Encoding Mode: CRF (quality-based)" -ForegroundColor White
    Write-Host "CRF Value: $crfValue" -ForegroundColor White
} else {
    Write-Host "Encoding Mode: Two-pass (size-based)" -ForegroundColor White
    Write-Host "Target Size: $targetSizeMB MB (hard limit)" -ForegroundColor White
    Write-Host "Adjusted Target for Encoding: $($adjustedTargetMB.ToString('0.0')) MB" -ForegroundColor White
    Write-Host "Video Bitrate: ${videoBitrateKbps}k" -ForegroundColor White
}

if ($tuneOption) {
    Write-Host "Tune: $useTune" -ForegroundColor White
}

Write-Host "Target Height: $targetHeight" -ForegroundColor White
Write-Host "Output will be saved as: $outputFile" -ForegroundColor White
Write-Host ""

# Create temporary directory for pass logs
$tempDir = Join-Path $env:TEMP "ffmpeg-2pass"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}
$passLogFile = Join-Path $tempDir "passlog"

# Get preset if applicable
$preset = $codecParams[$codec]["preset"]
$presetParam = if ($preset) { "-preset $preset" } else { "" }

# Get extra codec params
$extraParams = $codecParams[$codec]["extraParams"]

# Start encoding process
if ($useCRF) {
    # CRF mode (single pass, quality-based)
    Write-Host "Starting CRF encoding (quality-based)..." -ForegroundColor Green
    
    try {
        $crfCmd = ""
        
        if ($codec -eq "libvpx-vp9") {
            # VP9 specific CRF command with explicit audio encoding
            $crfCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec -pix_fmt yuv420p -c:a $audioCodec -b:a $audioBitrateValue -vf `"scale=-2:$targetHeight`" -crf $crfValue $extraParams `"$outputFile`""
        } else {
            # Other codecs CRF command
            $crfCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec $presetParam -pix_fmt yuv420p -c:a $audioCodec -vf `"scale=-2:$targetHeight`" -crf $crfValue $extraParams `"$outputFile`""
        }
        
        Write-Host "Executing: $crfCmd" -ForegroundColor DarkGray
        Invoke-Expression $crfCmd
    } catch {
        Write-Host "Error during CRF encoding: $_" -ForegroundColor Red
    }
} else {
    # Two-pass mode (target bitrate)
    Write-Host "Starting two-pass encoding..." -ForegroundColor Green
    Write-Host "Pass 1 of 2..." -ForegroundColor Green

    # First pass - codec specific first pass settings
    try {
        $firstPassCmd = ""
        
        if ($codec -eq "libvpx-vp9") {
            # VP9 specific first pass command
            $firstPassCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec -pix_fmt yuv420p -vf `"scale=-2:$targetHeight`" -pass 1 -passlogfile `"$passLogFile`" -b:v $($videoBitrateKbps)k $extraParams -an -f null NUL"
        } else {
            # H.264/H.265 first pass command
            $firstPassCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec $presetParam -pix_fmt yuv420p -vf `"scale=-2:$targetHeight`" -pass 1 -passlogfile `"$passLogFile`" -b:v $($videoBitrateKbps)k $extraParams -an -f null NUL"
        }
        
        Write-Host "Executing: $firstPassCmd" -ForegroundColor DarkGray
        Invoke-Expression $firstPassCmd
    } catch {
        Write-Host "Error during first pass: $_" -ForegroundColor Red
    }

    Write-Host "Pass 2 of 2..." -ForegroundColor Green

    # Second pass - codec specific second pass settings
    try {
        $secondPassCmd = ""
        
        if ($codec -eq "libvpx-vp9") {
            # VP9 specific second pass command with explicit audio encoding
            $secondPassCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec -pix_fmt yuv420p -c:a $audioCodec -b:a $audioBitrateValue -vf `"scale=-2:$targetHeight`" -pass 2 -passlogfile `"$passLogFile`" -b:v $($videoBitrateKbps)k $extraParams `"$outputFile`""
        } else {
            # H.264/H.265 second pass command
            $secondPassCmd = "& `"$ffmpegPath`" -y -i `"$InputFile`" -c:v $codec $presetParam -pix_fmt yuv420p -c:a $audioCodec -vf `"scale=-2:$targetHeight`" -pass 2 -passlogfile `"$passLogFile`" -b:v $($videoBitrateKbps)k $extraParams `"$outputFile`""
        }
        
        Write-Host "Executing: $secondPassCmd" -ForegroundColor DarkGray
        Invoke-Expression $secondPassCmd
    } catch {
        Write-Host "Error during second pass: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Encoding complete!" -ForegroundColor Green
Write-Host "Output file: $outputFile" -ForegroundColor Green

# Check final file size and verify it's under the limit
if (Test-Path -LiteralPath $outputFile) {
    $finalSize = (Get-Item -LiteralPath $outputFile).Length
    $finalSizeMB = $finalSize / 1MB
    $formattedSize = Format-FileSize $finalSize
    
    Write-Host "Actual file size: $formattedSize" -ForegroundColor Cyan
    
    # Check if the file is too small (likely failed conversion)
    if ($finalSize -lt 1KB) {
        Write-Host "ERROR: Output file is too small, conversion likely failed. Check error messages above." -ForegroundColor Red
    } elseif (-not $useCRF) {
        Write-Host "Target limit: $targetSizeMB MB" -ForegroundColor Cyan
        
        if ($finalSizeMB -gt $targetSizeMB) {
            Write-Host "WARNING: File size exceeds the target limit." -ForegroundColor Red
            Write-Host "You may need to use a lower target size and try again." -ForegroundColor Yellow
        } else {
            $spaceLeft = $targetSizeMB - $finalSizeMB
            Write-Host "SUCCESS: File is under the $targetSizeMB MB limit (with $($spaceLeft.ToString('0.00')) MB to spare)." -ForegroundColor Green
        }
    }
} else {
    Write-Host "WARNING: Output file was not created. Check for errors above." -ForegroundColor Red
}

# Clean up pass log files
if (Test-Path "$passLogFile-0.log") {
    Remove-Item "$passLogFile-0.log" -Force
}
if (Test-Path "$passLogFile-0.log.mbtree") {
    Remove-Item "$passLogFile-0.log.mbtree" -Force
}

Read-Host "Press Enter to exit"