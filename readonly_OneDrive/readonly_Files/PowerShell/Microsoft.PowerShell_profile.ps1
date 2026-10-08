

 # Import the Chocolatey Profile that contains the necessary code to enable
 # tab-completions to function for `choco`.
 # Be aware that if you are missing these lines from your profile, tab completion
 # for `choco` will not function.
 # See https://ch0.co/tab-completion for details.
# $ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
 #if (Test-Path($ChocolateyProfile)) {
  # Import-Module "$ChocolateyProfile"
 #}

# Oh-My-Posh
#Import-Module posh-git
#Import-Module Terminal-Icons
oh-my-posh init pwsh --config "$HOME\.paradox-custom.omp.json" | Invoke-Expression

# ---------------------------------------------------------------------------
# Git branch prompt
# ---------------------------------------------------------------------------
function Get-GitBranch {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $branch
}



# ---------------------------------------------------------------------------
# Admin aliases — filesystem & navigation
# ---------------------------------------------------------------------------
Set-Alias -Name ll      -Value Get-ChildItem                           # detailed listing
function la   { Get-ChildItem -Force @args }                           # include hidden
function which { (Get-Command $args[0] -ErrorAction Stop).Source }     # locate a command
function touch { $args | ForEach-Object {
    if (Test-Path $_) { (Get-Item $_).LastWriteTime = Get-Date }
    else { New-Item -ItemType File -Path $_ | Out-Null } } }           # unix-style touch
function mkcd { param([string]$dir) New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }

# ---------------------------------------------------------------------------
# Admin aliases — text & search
# ---------------------------------------------------------------------------
Set-Alias -Name grep    -Value Select-String
function tail { param([string]$file, [int]$n = 20) Get-Content $file -Tail $n }
function head { param([string]$file, [int]$n = 20) Get-Content $file -TotalCount $n }

# ---------------------------------------------------------------------------
# Admin aliases — processes & services
# ---------------------------------------------------------------------------
function psg  { Get-Process | Where-Object { $_.Name -like "*$args*" } }
function pkill { Stop-Process -Name $args -Force }
Set-Alias -Name svcs    -Value Get-Service
function svcg { Get-Service | Where-Object { $_.DisplayName -like "*$args*" } }

# ---------------------------------------------------------------------------
# Admin aliases — networking
# ---------------------------------------------------------------------------
function ports      { netstat -ano }
function flushdns   { Clear-DnsClientCache; Write-Host "DNS cache flushed." }
function myip       { (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip }
function localip    { (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike '*Loopback*' }).IPAddress }

# ---------------------------------------------------------------------------
# Admin aliases — system info
# ---------------------------------------------------------------------------
function df         { Get-PSDrive -PSProvider FileSystem }
function uptime     { (Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime }
function sysinfo    { Get-ComputerInfo | Select-Object CsName, OsName, OsVersion, CsProcessors, CsTotalPhysicalMemory }

# ---------------------------------------------------------------------------
# Admin aliases — profile & session
# ---------------------------------------------------------------------------
function reload     { . $PROFILE }
function hosts      { notepad "$env:SystemRoot\System32\drivers\etc\hosts" }
function editprofile { code $PROFILE }
Set-Alias -Name sudo    -Value gsudo -ErrorAction SilentlyContinue     # requires gsudo


function GitStatus {git status -sb}
Set-Alias -Name gss -Value GitStatus

##### posh-fzf

$null = New-Module posh-fzf {
        $defaultHeight = "45%"
        $defaultHeightArg = "--height=$defaultHeight"
        $historyPath = (Get-PSReadLineOption).HistorySavePath

        function Invoke-PoshFzfSelectItems {
                Invoke-PoshFzfTempEnv @{FZF_DEFAULT_COMMAND = 'fd --hidden --exclude ".git"'} -ScriptBlock {
                        $fzfSelection = Invoke-PoshFzfStartProcess -FileName "fzf" -Arguments @("$defaultHeightArg", "-m")
                        if ($fzfSelection) {
                                Invoke-PoshFzfInsertUtf8 $fzfSelection
                        }
                }
        }

        function Invoke-PoshFzfChangeDirectory {
                Invoke-PoshFzfTempEnv @{FZF_DEFAULT_COMMAND = 'fd --type d --hidden --exclude ".git"'} -ScriptBlock {
                        $directory = Invoke-PoshFzfStartProcess -FileName "fzf" -Arguments @("$defaultHeightArg", "--preview", "fd . {} --maxdepth 1")
                        if ($directory) {
                                [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
                                Invoke-PoshFzfInsertUtf8 "cd $directory"
                                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
                        }
                }
        }

        function Invoke-PoshFzfSelectHistory {
                $historyCommand = Invoke-PoshFzfStartProcess -FileName "posh-fzf" -Arguments @("history", $historyPath)
                if ($historyCommand) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
                        Invoke-PoshFzfInsertUtf8 $historyCommand
                }
        }

        # // https://github.com/kelleyma49/PSFzf/blob/051a0da959321253fd11bf9bb14e270b2902eb5c/PSFzf.Base.ps1#L258-L560
        function Invoke-PoshFzfStartProcess {
                [CmdletBinding()]
                param (
                        [Parameter(ValueFromPipeline=$true)]
                        [string]$inputString,
                        [Parameter(Mandatory)]
                        [string]$FileName,
                        [array]$Arguments = @(),
                        [string]$HeightRowsOrPercent = $defaultHeight
                )
                begin {
                        $numRows = CalculateHeight($HeightRowsOrPercent)
                        ClearBufferAhead $numRows
                        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                        $startInfo.FileName = $FileName
                        Set-ArgumentList $startInfo $Arguments
                        $startInfo.RedirectStandardInput = $MyInvocation.ExpectingInput
                        $startInfo.RedirectStandardOutput = $true
                        $startInfo.UseShellExecute = $false
                        $startInfo.WorkingDirectory = (Get-Location).Path

                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo = $startInfo
                        $process.Start() | Out-Null
                }
                process {
                        if ($inputString) {
                                $process.StandardInput.WriteLine($inputString)
                        }
                }
                end {
                        $process.WaitForExit()
                        RedrawLastLineOfPrompt
                        $content = $process.StandardOutput.ReadToEnd().Trim() -join "`n"
                        return $content
                }
        }

        function Set-ArgumentList($startInfo, $argumentList) {
                # Taken from https://github.com/starship/starship/blob/43b2d42cd526e34c5f0290e7409fbd6d3a54e908/src/init/starship.ps1#L35-L53
                if ($startInfo.ArgumentList.Add) {
                        # PowerShell 6+ supports ArgumentList property
                        foreach ($arg in $argumentList) { $startInfo.ArgumentList.Add($arg) }
                }
                else {
                        # Build an arguments string which follows the C++ command-line argument quoting rules
                        # See: https://docs.microsoft.com/en-us/previous-versions//17w5ykft(v=vs.85)?redirectedfrom=MSDN
                        $escaped = $argumentList | ForEach-Object {
                                $s = $_ -Replace '(\\+)"','$1$1"'; # Escape backslash chains immediately preceding quote marks.
                                $s = $s -Replace '(\\+)$','$1$1';  # Escape backslash chains immediately preceding the end of the string.
                                $s = $s -Replace '"','\"';         # Escape quote marks.
                                "`"$s`""                           # Quote the argument.
                        }
                        $startInfo.Arguments = $escaped -Join ' ';
                }
        }

        function Invoke-PoshFzfTempEnv([hashtable]$envObj, [scriptblock]$ScriptBlock) {
                $originals = @{}
                foreach ($key in $envObj.keys) {
                        $originals[$key] = ""# (Get-Item "env:$key" -ErrorAction SilentlyContinue).Value
                        Set-Item "env:$key" $envObj[$key]

                }
                try {
                        Invoke-Command -ScriptBlock $ScriptBlock
                } finally {
                        foreach ($key in $originals.keys) {
                                Set-Item "env:$key" $originals[$key]
                        }
                }
        }
        function ClearBufferAhead([int] $numRows) {
                $tempPosX = [Console]::CursorLeft
                [Console]::Write("`n" * $numRows)
                [Console]::SetCursorPosition($tempPosX, [Console]::CursorTop - $numRows)
                [Microsoft.PowerShell.PSConsoleReadLine]::Delete(0, 0)
        }

        function RedrawLastLineOfPrompt {
                $previousOutputEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [Text.Encoding]::UTF8

                try {
                        $prompt = ""
                        if (Get-Command "Invoke-PoshFzfRedrawLastLineOfPrompt" -ErrorAction SilentlyContinue) {
                                $prompt = Invoke-PoshFzfRedrawLastLineOfPrompt
                        } else {
                                $prompt = prompt 6>$null
                        }
                        $lastLine = ($prompt -split "`n")[-1]
                        Write-Host -NoNewline $lastLine
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(" ")
                        [Microsoft.PowerShell.PSConsoleReadLine]::Undo()
                } finally {
                        [Console]::OutputEncoding = $previousOutputEncoding
                }
        }

        function Invoke-PoshFzfInsertUtf8($data) {
                $previousOutputEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = [Text.Encoding]::UTF8
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($data)
                [Console]::OutputEncoding = $previousOutputEncoding
        }

        function CalculateHeight($heightRowsOrPercent) {
                if ($heightRowsOrPercent -is [int]) {
                        return $heightRowsOrPercent
                }
                # https://github.com/junegunn/fzf/blob/d2b852f7cbd2da53804de00cf22ca0b7e6c9f472/src/terminal.go#L547-L552
                $heightPercent = [int]$heightRowsOrPercent.TrimEnd('%')
                $termHeight = $host.UI.RawUI.WindowSize.Height
                $minHeight = 10 # 10 is the default
                return [Math]::Max([int]($heightPercent * [double]$termHeight / 100.0), $minHeight)
        }

        Export-ModuleMember -Function @(
                "Invoke-PoshFzfSelectItems",
                "Invoke-PoshFzfChangeDirectory",
                "Invoke-PoshFzfSelectHistory",
                "Invoke-PoshFzfStartProcess",
                "Invoke-PoshFzfInsertUtf8",
                "Invoke-PoshFzfTempEnv"
        )
}

# Initialize the posh-fzf tool
# Invoke-Expression (& posh-fzf init | Out-String)

# Explicitly bind the keys to posh-fzf functions
Set-PSReadLineKeyHandler -Key 'Ctrl+t' -ScriptBlock { Invoke-PoshFzfSelectItems }
Set-PSReadLineKeyHandler -Key 'Alt+c' -ScriptBlock { Invoke-PoshFzfChangeDirectory }
Set-PSReadLineKeyHandler -Key 'Ctrl+r' -ScriptBlock { Invoke-PoshFzfSelectHistory }

