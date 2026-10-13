# Nilufar Tools - installazione su Windows (solo per l'utente, nessun permesso di amministratore).
# Usa solo programmi firmati: il Python ufficiale di python.org (Python Software Foundation) e il suo venv.
# Nessun .exe nostro: Smart App Control non ha nulla da bloccare.
#
# Riga per l'utente (Win+R):
#   powershell -NoProfile -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/fntanyl/tool-installer/main/installa-win.ps1 | iex"
# Rilanciarla = riparare. Opzioni tramite variabili d'ambiente prima di irm:
#   $env:NILUFAR_DISINSTALLA='1'   toglie collegamenti e dati dello strumento (la cartella Nilufar Tools resta)
#   $env:NILUFAR_NUOVA_CHIAVE='1'  chiede di nuovo la chiave
#   $env:NILUFAR_CANALE='test'     installa anche le versioni di prova
#   $env:NILUFAR_VECCHIA='C:\...\NilufarTools'  cartella della vecchia installazione da migrare

function Install-NilufarTools {
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$Owner = if ($env:NILUFAR_OWNER) { $env:NILUFAR_OWNER } else { 'fntanyl' }
$Repo = if ($env:NILUFAR_REPO) { $env:NILUFAR_REPO } else { 'NilufarTools' }
$InstallerBase = "https://raw.githubusercontent.com/$Owner/tool-installer/main"
$Api = 'https://api.github.com'
$Root = Join-Path $env:LOCALAPPDATA 'NilufarTools'
$Rt = Join-Path $Root 'runtime'
$Venv = Join-Path $Rt 'venv'
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
$VenvPyw = Join-Path $Venv 'Scripts\pythonw.exe'
$LogDir = Join-Path $Root 'logs-installazione'
$Log = Join-Path $LogDir 'installazione.log'
$Docs = Join-Path $env:USERPROFILE 'Nilufar Tools'      # cartella dell'utente (fuori da OneDrive)
$Desktop = [Environment]::GetFolderPath('Desktop')
$StartMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Nilufar Tools.lnk'
$DeskLnk = Join-Path $Desktop 'Nilufar Tools.lnk'
$PyVer = '3.13.16'
$PyUrl = "https://www.python.org/ftp/python/$PyVer/python-$PyVer-amd64.exe"
$PyUser = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313'

function Say($msg) {
    Write-Host "  $msg"
    try { Add-Content -LiteralPath $Log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}
function Fail($msg) {
    Write-Host ""
    Write-Host "  ERRORE: $msg" -ForegroundColor Red
    try { Add-Content -LiteralPath $Log -Value "ERRORE $msg" -Encoding UTF8 } catch {}
    Write-Host "  Dettagli in: $Log"
    Write-Host "  Puoi rilanciare la stessa riga per riprovare."
    throw "installazione interrotta"
}
# comando nativo con output nel log; ritorna il codice di uscita
function Run-Logged([string]$exe, [string[]]$argv, [string]$stdin = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($argv | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $p = [System.Diagnostics.Process]::Start($psi)
    # byte scritti direttamente: niente BOM UTF-8 davanti alla chiave o allo script Python
    $bin = $p.StandardInput.BaseStream
    if ($stdin) { $bytes = (New-Object Text.UTF8Encoding $false).GetBytes($stdin); $bin.Write($bytes, 0, $bytes.Length); $bin.Flush() }
    $bin.Close()
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $err = $errTask.Result
    try { Add-Content -LiteralPath $Log -Value ($out + $err) -Encoding UTF8 } catch {}
    $script:LastOut = $out
    return $p.ExitCode
}
function Get-GitHubStatus([string]$token, [string]$url) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 20 -Headers @{
            Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
        return [int]$r.StatusCode
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    } catch { return 0 }
}
function New-Shortcut([string]$lnk, [string]$root) {
    $ico = Join-Path $root 'nilufar.ico'
    $avvia = Join-Path $root 'avvia.py'
    $work = Join-Path $root 'home'
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
    try {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = $VenvPyw
        $s.Arguments = '"' + $avvia + '"'
        $s.WorkingDirectory = $work
        $s.IconLocation = "$ico,0"
        $s.Description = 'Nilufar Tools'
        $s.Save()
    } catch { Add-Content -LiteralPath $Log -Value "collegamento via PowerShell non riuscito: $_" }
    if (Test-Path -LiteralPath $lnk) { return $true }
    # ripiego collaudato: VBScript (in passato la creazione falliva in silenzio)
    $vbs = Join-Path $env:TEMP 'nilufar_collegamento.vbs'
    @(
        'Set sh = CreateObject("WScript.Shell")',
        "Set s = sh.CreateShortcut(""$lnk"")",
        "s.TargetPath = ""$VenvPyw""",
        "s.Arguments = """"""$avvia""""""",
        "s.WorkingDirectory = ""$work""",
        "s.IconLocation = ""$ico,0""",
        's.Save'
    ) | Set-Content -LiteralPath $vbs -Encoding ASCII
    Run-Logged 'cscript.exe' @('//nologo', $vbs) | Out-Null
    Remove-Item -LiteralPath $vbs -Force -ErrorAction SilentlyContinue
    return (Test-Path -LiteralPath $lnk)
}

Write-Host ""
Write-Host "  NILUFAR TOOLS - installazione su Windows"
Write-Host "  -------------------------------------------------------------"

# ---------------------------------------------------------------- disinstalla
if ($env:NILUFAR_DISINSTALLA -eq '1' -or $env:DISINSTALLA -eq '1') {
    $r = Read-Host "  Tolgo Nilufar Tools da questo PC (i documenti in $Docs restano). Confermi? [s/N]"
    if ($r -notmatch '^(s|si)$') { Write-Host "  Annullato."; return }
    Get-CimInstance Win32_Process -Filter "Name like 'python%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Root) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    foreach ($l in @($StartMenu, $DeskLnk)) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Root) { Write-Host "  Alcuni file sono ancora in uso: chiudi Nilufar Tools e rilancia." ; return }
    Write-Host "  Fatto: Nilufar Tools e' stato tolto. I tuoi documenti sono ancora in $Docs"
    return
}

New-Item -ItemType Directory -Force -Path $LogDir, $Rt, (Join-Path $Root 'tmp'), (Join-Path $Root 'home\sessione') | Out-Null
Add-Content -LiteralPath $Log -Value ("`n---- {0} installazione" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ($Root.Length -gt 120) { Say "ATTENZIONE: percorso lungo ($Root), alcune librerie potrebbero non installarsi" }

# ---------------------------------------------------------------- 1. chiave
$GhBin = Join-Path $Root 'home\sessione\github.bin'
$Token = $null
if ($env:NILUFAR_NUOVA_CHIAVE -ne '1' -and (Test-Path -LiteralPath $GhBin)) {
    try {
        Add-Type -AssemblyName System.Security
        $b = [IO.File]::ReadAllBytes($GhBin)
        if ([Text.Encoding]::ASCII.GetString($b, 0, 5) -eq 'DPAPI') {
            $plain = [Security.Cryptography.ProtectedData]::Unprotect($b[5..($b.Length - 1)], $null, 'CurrentUser')
            $Token = [Text.Encoding]::UTF8.GetString($plain)
        }
    } catch { $Token = $null }
    if ($Token -and (Get-GitHubStatus $Token "$Api/repos/$Owner/$Repo") -eq 200) { Say "[1/6] chiave gia' salvata: valida" } else { $Token = $null }
}
if (-not $Token) {
    Write-Host "  [1/6] Chiave di installazione (te la da' chi mantiene lo strumento, inizia con github_pat_)"
    for ($i = 0; $i -lt 3 -and -not $Token; $i++) {
        $sec = Read-Host "        Incolla la chiave e premi Invio" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $t = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        if (-not $t) { continue }
        $code = Get-GitHubStatus $t "$Api/repos/$Owner/$Repo"
        if ($code -eq 200) { $Token = $t; Say "        chiave valida" }
        elseif ($code -eq 0) { Fail "nessuna connessione a GitHub: controlla internet e riprova" }
        else { Write-Host "        chiave non valida o senza accesso al repository (codice $code), riprova" }
    }
    if (-not $Token) { Fail "chiave non valida" }
}

# ---------------------------------------------------------------- 2. Python firmato
function Find-SystemPython {
    $check = "import sys; print(sys.executable if (3,10) <= sys.version_info[:2] <= (3,14) else '')"
    $cands = @(@('py', '-3.13'), @('py', '-3.12'), @('py', '-3'), @('python'))
    foreach ($c in $cands) {
        try {
            $exe = $c[0]; $pre = @($c | Select-Object -Skip 1)
            if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
            $out = & $exe @pre -c $check 2>$null
            if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path -LiteralPath $out.Trim())) { return $out.Trim() }
        } catch {}
    }
    $u = Join-Path $PyUser 'python.exe'
    if (Test-Path -LiteralPath $u) { return $u }
    return $null
}
$venvOk = $false
if (Test-Path -LiteralPath $VenvPy) {
    $venvOk = (Run-Logged $VenvPy @('-c', 'import sys; assert (3,10) <= sys.version_info[:2] <= (3,14)')) -eq 0
}
if ($venvOk) { Say "[2/6] ambiente Python gia' pronto" }
else {
    $SysPy = Find-SystemPython
    if (-not $SysPy) {
        Say "[2/6] Python non trovato: scarico l'installatore ufficiale $PyVer da python.org (circa 30 MB)..."
        $exe = Join-Path $Root "tmp\python-$PyVer-amd64.exe"
        try { Invoke-WebRequest -UseBasicParsing -Uri $PyUrl -OutFile $exe -TimeoutSec 600 } catch { Fail "download di Python non riuscito: $_" }
        $sig = Get-AuthenticodeSignature -LiteralPath $exe
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike '*Python Software Foundation*') {
            Remove-Item -LiteralPath $exe -Force
            Fail "la firma dell'installatore di Python non e' valida: non lo eseguo"
        }
        Say "      firma verificata (Python Software Foundation), installo per il solo utente: 1-2 minuti..."
        $p = Start-Process -FilePath $exe -ArgumentList '/quiet', 'InstallAllUsers=0', 'Include_launcher=0', 'PrependPath=0', 'Shortcuts=0', 'Include_doc=0', 'Include_test=0', 'Include_tcltk=1', 'Include_pip=1' -Wait -PassThru
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
        $SysPy = Join-Path $PyUser 'python.exe'
        if (-not (Test-Path -LiteralPath $SysPy)) { Fail "installazione di Python non riuscita (codice $($p.ExitCode))" }
    }
    Say "[2/6] Python: $SysPy, creo l'ambiente dello strumento..."
    if (Test-Path -LiteralPath $Venv) { Remove-Item -LiteralPath $Venv -Recurse -Force }
    if ((Run-Logged $SysPy @('-m', 'venv', $Venv)) -ne 0 -or -not (Test-Path -LiteralPath $VenvPyw)) { Fail "ambiente Python non creato" }
}

# ---------------------------------------------------------------- 3. configurazione
$Canale = $env:NILUFAR_CANALE
$CfgFile = Join-Path $Root 'config.json'
if (-not $Canale -and (Test-Path -LiteralPath $CfgFile)) {
    try { $Canale = (Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json).canale } catch {}
}
if (-not $Canale) { $Canale = 'stabile' }
# installazione esistente: la cartella dell'utente resta quella configurata (la sposta l'app, se serve)
if (Test-Path -LiteralPath $CfgFile) { try { $d = (Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json).docs; if ($d) { $Docs = $d } } catch {} }
$env:NT_OWNER = $Owner; $env:NT_REPO = $Repo; $env:NT_CANALE = $Canale; $env:NT_DOCS = $Docs; $env:NT_BASE = $InstallerBase
$cfgPy = @'
import json, os, sys
p = sys.argv[1]
try:
    c = json.load(open(p, encoding="utf-8"))
except Exception:
    c = {}
if "docs" not in c:                    # prima installazione: cartella nuova, niente da spostare
    c.update(docs=os.environ["NT_DOCS"], docs_versione=2)
c.update(owner=os.environ["NT_OWNER"], repo=os.environ["NT_REPO"], canale=os.environ["NT_CANALE"],
         installer_base=os.environ["NT_BASE"], installer_version=2)
json.dump(c, open(p + ".tmp", "w", encoding="utf-8"), indent=2, ensure_ascii=False)
os.replace(p + ".tmp", p)
'@
if ((Run-Logged $VenvPy @('-', $CfgFile) $cfgPy) -ne 0) { Fail "config.json non scritto" }

# ---------------------------------------------------------------- 4. versione e librerie
Say "[3/6] scarico l'ultima versione dello strumento..."
$UpdPy = Join-Path $Root 'tmp\updater.py'
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$Api/repos/$Owner/$Repo/contents/app/updater.py" -OutFile $UpdPy -TimeoutSec 60 -Headers @{
        Authorization = "Bearer $Token"; Accept = 'application/vnd.github.raw'; 'X-GitHub-Api-Version' = '2022-11-28' }
} catch { Fail "download dell'aggiornatore non riuscito" }
Say "[4/6] installo versione e librerie (la prima volta qualche minuto)..."
# output in tempo reale (avanzamento delle librerie); la chiave arriva da stdin, il BOM lo toglie updater.py
$env:PYTHONIOENCODING = 'utf-8'
$prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$Token | & $VenvPy $UpdPy installa --root $Root --canale $Canale 2>$null | ForEach-Object { Say "      $_" }
$rc = $LASTEXITCODE
$ErrorActionPreference = $prevEap
$Cur = $null
try { $Cur = (Get-Content -LiteralPath (Join-Path $Root 'current.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch {}
if ($rc -ne 0 -or -not $Cur -or -not (Test-Path -LiteralPath (Join-Path $Root "versions\$Cur\boot.py"))) { Fail "installazione della versione non riuscita" }
Remove-Item -LiteralPath $UpdPy -Force -ErrorAction SilentlyContinue
$env:NILUFAR_HOME = Join-Path $Root 'home'
if ((Run-Logged $VenvPy @((Join-Path $Root "versions\$Cur\scripts\segreti.py"), 'salva', 'github') $Token) -ne 0) { Fail "chiave non salvata" }
$Token = $null
Say "      versione $Cur installata, chiave salvata cifrata (DPAPI)"

# ---------------------------------------------------------------- 5. browser
$chrome = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'Google\Chrome\Application\chrome.exe' } | Where-Object { Test-Path -LiteralPath $_ }
if ($chrome) { Say "[5/6] uso Google Chrome installato" }
else {
    Say "[5/6] Chrome non trovato: scarico Chromium per lo strumento (circa 200 MB)..."
    $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $Rt 'browsers'
    if ((Run-Logged $VenvPy @('-m', 'playwright', 'install', '--no-shell', 'chromium')) -ne 0) { Say "      ATTENZIONE: download di Chromium non riuscito (dettagli nel log)" }
    $setPy = @'
import json, sys
p = sys.argv[1]
try:
    s = json.load(open(p, encoding="utf-8"))
except Exception:
    s = {}
s["browser_channel"] = ""
json.dump(s, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
'@
    Run-Logged $VenvPy @('-', (Join-Path $Root 'home\impostazioni.json')) $setPy | Out-Null
}

# ---------------------------------------------------------------- 6. migrazione dalla vecchia cartella (AVVIA.bat)
$Old = $env:NILUFAR_VECCHIA
if (-not $Old) {
    $bases = @($Desktop, (Join-Path $env:USERPROFILE 'Downloads'), ([Environment]::GetFolderPath('MyDocuments')), $env:USERPROFILE)
    foreach ($b in $bases) {
        if (-not $b -or -not (Test-Path -LiteralPath $b)) { continue }
        $hit = Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'AVVIA.bat')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'app\gui.py')) } | Select-Object -First 1
        if (-not $hit) {
            $hit = Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } | Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName 'AVVIA.bat')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'app\gui.py')) } | Select-Object -First 1
        }
        if ($hit) { $Old = $hit.FullName; break }
    }
}
$Home2 = Join-Path $Root 'home'
if ($Old -and (Test-Path -LiteralPath (Join-Path $Old 'app\gui.py')) -and -not (Test-Path -LiteralPath (Join-Path $Home2 'migrato_da.txt'))) {
    Say "[6/6] trovata la vecchia installazione: $Old, porto login, impostazioni e storici..."
    $oldSet = Join-Path $Old 'impostazioni.json'
    if (Test-Path -LiteralPath $oldSet) { Copy-Item -LiteralPath $oldSet -Destination (Join-Path $Home2 'impostazioni.json') -Force }
    # i percorsi relativi "dati/..." diventano i Documenti alla prima apertura (common.py, settings_version 3)
    New-Item -ItemType Directory -Force -Path $Docs | Out-Null
    $oldDati = Join-Path $Old 'dati'
    if (Test-Path -LiteralPath $oldDati) {
        Get-ChildItem -LiteralPath $oldDati -File | Where-Object { $_.Extension -in '.xlsx', '.txt', '.csv' } | ForEach-Object {
            $dst = Join-Path $Docs $_.Name
            if (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $_.FullName -Destination $dst }
        }
        foreach ($sub in @('estrazioni', 'Estrazioni')) {
            $src = Join-Path $oldDati $sub
            if (Test-Path -LiteralPath $src) { Copy-Item -Path (Join-Path $src '*') -Destination (New-Item -ItemType Directory -Force (Join-Path $Docs 'Estrazioni')) -Recurse -ErrorAction SilentlyContinue }
        }
        $cache = Join-Path $oldDati 'cache'
        if (Test-Path -LiteralPath $cache) {
            $datiNew = New-Item -ItemType Directory -Force (Join-Path $Home2 'dati')
            Copy-Item -LiteralPath $cache -Destination $datiNew.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $oldSess = Join-Path $Old 'sessione'
    if (Test-Path -LiteralPath $oldSess) {
        Get-ChildItem -LiteralPath $oldSess | Where-Object { $_.Name -ne 'github.bin' } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Home2 'sessione') -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $logs = Join-Path $Home2 'logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    foreach ($n in @('storico.jsonl', 'panthera_esiti.csv', 'backup_excel', 'registro')) {
        $src = Join-Path $Old "logs\$n"
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $logs -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($n in @('estrazione.json', 'panthera_selettori.json')) {
        $src = Join-Path $Old $n
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $Home2 -Force }
    }
    Set-Content -LiteralPath (Join-Path $Home2 'migrato_da.txt') -Value $Old -Encoding UTF8
    $MigratedFrom = $Old
} else {
    Say "[6/6] nessuna vecchia installazione da migrare"
}

# ---------------------------------------------------------------- collegamenti
Say "creo i collegamenti nel Menu Start e sul Desktop..."
$okStart = New-Shortcut $StartMenu $Root
$okDesk = New-Shortcut $DeskLnk $Root
if (-not $okStart -and -not $okDesk) { Fail "collegamenti non creati: Windows blocca gli script (dettagli nel log)" }
# vecchio collegamento sul Desktop che apriva AVVIA.bat
Get-ChildItem -LiteralPath $Desktop -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $t = (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath
        if ($t -like '*\AVVIA.bat') { Remove-Item -LiteralPath $_.FullName -Force; Say "      tolto il vecchio collegamento $($_.Name)" }
    } catch {}
}
Remove-Item -LiteralPath (Join-Path $Root 'tmp\*') -Recurse -Force -ErrorAction SilentlyContinue

Say "avvio Nilufar Tools"
Start-Process -FilePath $VenvPyw -ArgumentList ('"' + (Join-Path $Root 'avvia.py') + '"') -WorkingDirectory $Home2
Write-Host ""
Write-Host "  Fatto: Nilufar Tools e' nel Menu Start e sul Desktop. Gli aggiornamenti arrivano da soli."
Write-Host "  I tuoi Excel vanno in: $Docs"
if ($MigratedFrom) {
    Write-Host "  Login, impostazioni e storici sono stati portati dalla vecchia cartella."
    Write-Host "  Quando hai controllato che tutto funziona puoi cancellare la vecchia cartella: $MigratedFrom"
}
Write-Host ""
}

try { Install-NilufarTools } catch { if ("$_" -ne 'installazione interrotta') { Write-Host "  ERRORE inatteso: $_" -ForegroundColor Red } }
finally { try { Read-Host "  Premi Invio per chiudere questa finestra" | Out-Null } catch {} }
