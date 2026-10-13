#!/bin/bash
# Nilufar Tools - installazione su Mac (nessuna password di amministratore, nessun avviso di sicurezza).
#
#   curl -fsSL https://raw.githubusercontent.com/fntanyl/nilufar-tools-installer/main/installa-mac.sh | bash
#
# Rilanciarlo = riparare (idempotente). Opzioni (dopo "bash -s --"):
#   --disinstalla     toglie app e dati dello strumento (la cartella Documenti/Nilufar Tools resta)
#   --nuova-chiave    chiede di nuovo la chiave di installazione
#   --canale test     installa anche le versioni di prova
#
# Tutto il codice e' dentro main(): bash legge l'intero script prima di eseguirlo (arriva da una pipe).
# Ogni comando che potrebbe leggere lo standard input ha </dev/null o un input esplicito.

main() {
set -euo pipefail

OWNER="${NILUFAR_OWNER:-fntanyl}"
REPO="${NILUFAR_REPO:-NilufarTools}"
INSTALLER_BASE="https://raw.githubusercontent.com/$OWNER/nilufar-tools-installer/main"
API="https://api.github.com"
ROOT="$HOME/Library/Application Support/NilufarTools"
APP="$HOME/Applications/Nilufar Tools.app"
DOCS="$HOME/Documents/Nilufar Tools"
RT="$ROOT/runtime"
VENV="$RT/venv"
PY="$VENV/bin/python"
LOGDIR="$ROOT/logs-installazione"
LOG="$LOGDIR/installazione.log"
KC_GITHUB="NilufarTools-GitHub"
KC_PANTHERA="NilufarTools-Panthera"

DISINSTALLA=0
NUOVA_CHIAVE=0
CANALE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --disinstalla) DISINSTALLA=1 ;;
        --nuova-chiave) NUOVA_CHIAVE=1 ;;
        --canale) shift; CANALE="${1:-}" ;;
    esac
    shift
done

say() { printf '  %s\n' "$*"; [ -d "$LOGDIR" ] && printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" || true; }
fail() {
    printf '\n  ERRORE: %s\n' "$*"
    [ -d "$LOGDIR" ] && printf '%s ERRORE %s\n' "$(date '+%F %T')" "$*" >> "$LOG" || true
    printf '  Dettagli in: %s\n  Puoi rilanciare la stessa riga per riprovare.\n\n' "$LOG"
    exit 1
}
ask() { printf '%s' "$1" > /dev/tty; local a; IFS= read -r a < /dev/tty || a=""; printf '%s' "$a"; }

echo
echo "  NILUFAR TOOLS - installazione su Mac"
echo "  -------------------------------------------------------------"

# ---------------------------------------------------------------- disinstalla
if [ "$DISINSTALLA" = 1 ]; then
    r="$(ask "  Tolgo Nilufar Tools da questo Mac (i documenti in $DOCS restano). Confermi? [s/N] ")"
    case "$r" in s|S|si|SI|Si) ;; *) echo "  Annullato."; exit 0 ;; esac
    pkill -f "$ROOT/avvia.py" </dev/null 2>/dev/null || true
    pkill -f "$ROOT/versions/" </dev/null 2>/dev/null || true
    sleep 1
    rm -rf "$APP" "$ROOT"
    /usr/bin/security delete-generic-password -s "$KC_GITHUB" -a nilufar </dev/null >/dev/null 2>&1 || true
    /usr/bin/security delete-generic-password -s "$KC_PANTHERA" -a nilufar </dev/null >/dev/null 2>&1 || true
    echo "  Fatto: Nilufar Tools e' stato tolto. I tuoi documenti sono ancora in $DOCS"
    exit 0
fi

mkdir -p "$LOGDIR" "$RT" "$ROOT/tmp" "$ROOT/home" "$DOCS"
printf '\n---- %s installazione (%s)\n' "$(date '+%F %T')" "$(sw_vers -productVersion 2>/dev/null || echo macOS)" >> "$LOG"

# ---------------------------------------------------------------- 1. chiave
# curl riceve la chiave da stdin (-K -): non compare nella lista dei processi
gh_status() {   # $1 = token, $2 = url -> stampa il codice HTTP (000 = nessuna connessione)
    local out
    out="$(printf 'header = "Authorization: Bearer %s"\n' "$1" | \
        curl -s -o /dev/null -w '%{http_code}' -K - -H "Accept: application/vnd.github+json" \
             -H "X-GitHub-Api-Version: 2022-11-28" --max-time 20 "$2" 2>/dev/null)" || true
    out="${out:-000}"
    printf '%s' "${out:0:3}"
}
TOKEN=""
if [ "$NUOVA_CHIAVE" = 0 ]; then
    saved="$(/usr/bin/security find-generic-password -s "$KC_GITHUB" -a nilufar -w </dev/null 2>/dev/null || true)"
    case "$saved" in b64:*) TOKEN="$(printf '%s' "${saved#b64:}" | base64 -D 2>/dev/null || true)" ;; *) TOKEN="$saved" ;; esac
    if [ -n "$TOKEN" ] && [ "$(gh_status "$TOKEN" "$API/repos/$OWNER/$REPO")" = "200" ]; then
        say "[1/6] chiave gia' salvata nel Portachiavi: valida"
    else
        TOKEN=""
    fi
fi
if [ -z "$TOKEN" ]; then
    echo "  [1/6] Chiave di installazione (te la da' chi mantiene lo strumento, inizia con github_pat_)"
    for tentativo in 1 2 3; do
        printf '        Incolla la chiave e premi Invio (non si vede mentre la incolli): ' > /dev/tty
        IFS= read -rs TOKEN < /dev/tty || TOKEN=""
        printf '\n' > /dev/tty
        TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
        [ -z "$TOKEN" ] && continue
        code="$(gh_status "$TOKEN" "$API/repos/$OWNER/$REPO")"
        if [ "$code" = "200" ]; then say "        chiave valida"; break; fi
        if [ "$code" = "000" ]; then fail "nessuna connessione a GitHub: controlla internet e riprova"; fi
        echo "        chiave non valida o senza accesso al repository (codice $code), riprova"
        TOKEN=""
    done
    [ -n "$TOKEN" ] || fail "chiave non valida"
fi

# ---------------------------------------------------------------- 2. uv e Python
ARCH="$(uname -m)"
case "$ARCH" in
    arm64) UVT="aarch64-apple-darwin" ;;
    x86_64) UVT="x86_64-apple-darwin" ;;
    *) fail "processore non supportato: $ARCH" ;;
esac
export UV_PYTHON_INSTALL_DIR="$RT/python" UV_CACHE_DIR="$RT/uv-cache" UV_PYTHON_PREFERENCE=only-managed UV_NO_PROGRESS=1
if [ ! -x "$RT/uv" ] || ! "$RT/uv" --version </dev/null >/dev/null 2>&1; then
    say "[2/6] scarico uv ($UVT)..."
    rm -rf "$ROOT/tmp/uv" && mkdir -p "$ROOT/tmp/uv"
    curl -fsSL --max-time 300 -o "$ROOT/tmp/uv.tar.gz" \
        "https://github.com/astral-sh/uv/releases/latest/download/uv-$UVT.tar.gz" </dev/null >> "$LOG" 2>&1 \
        || fail "download di uv non riuscito"
    tar -xzf "$ROOT/tmp/uv.tar.gz" -C "$ROOT/tmp/uv" >> "$LOG" 2>&1 || fail "archivio di uv illeggibile"
    mv -f "$ROOT/tmp/uv/uv-$UVT/uv" "$RT/uv" && chmod +x "$RT/uv"
    rm -rf "$ROOT/tmp/uv" "$ROOT/tmp/uv.tar.gz"
else
    say "[2/6] uv gia' presente"
fi
if [ -x "$PY" ] && "$PY" -c "import sys; assert sys.version_info[:2] == (3, 12)" </dev/null >/dev/null 2>&1; then
    say "      Python 3.12 gia' pronto"
else
    say "      installo Python 3.12 (solo per questo strumento, circa 1 minuto)..."
    "$RT/uv" python install 3.12 </dev/null >> "$LOG" 2>&1 || fail "installazione di Python non riuscita"
    rm -rf "$VENV"
    "$RT/uv" venv --seed --python 3.12 "$VENV" </dev/null >> "$LOG" 2>&1 || fail "ambiente Python non creato"
fi

# ---------------------------------------------------------------- 3. configurazione
OLD_CANALE="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1])).get('canale',''))" "$ROOT/config.json" </dev/null 2>/dev/null || true)"
[ -n "$CANALE" ] || CANALE="${OLD_CANALE:-stabile}"
NT_OWNER="$OWNER" NT_REPO="$REPO" NT_CANALE="$CANALE" NT_DOCS="$DOCS" NT_BASE="$INSTALLER_BASE" "$PY" - "$ROOT/config.json" <<'EOF' || fail "config.json non scritto"
import json, os, sys
p = sys.argv[1]
try:
    c = json.load(open(p, encoding="utf-8"))
except Exception:
    c = {}
c.update(owner=os.environ["NT_OWNER"], repo=os.environ["NT_REPO"], canale=os.environ["NT_CANALE"],
         docs=os.environ["NT_DOCS"], installer_base=os.environ["NT_BASE"], installer_version=1)
json.dump(c, open(p + ".tmp", "w", encoding="utf-8"), indent=2, ensure_ascii=False)
os.replace(p + ".tmp", p)
EOF

# ---------------------------------------------------------------- 4. versione e librerie
say "[3/6] scarico l'ultima versione dello strumento..."
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | \
    curl -fsS -K - -H "Accept: application/vnd.github.raw" --max-time 60 -o "$ROOT/tmp/updater.py" \
         "$API/repos/$OWNER/$REPO/contents/app/updater.py" >> "$LOG" 2>&1 || fail "download dell'aggiornatore non riuscito"
say "[4/6] installo versione e librerie (la prima volta qualche minuto)..."
printf '%s' "$TOKEN" | "$PY" "$ROOT/tmp/updater.py" installa --root "$ROOT" --canale "$CANALE" 2>> "$LOG" | \
    while IFS= read -r line; do say "      $line"; done || true
CUR="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$ROOT/current.json" </dev/null 2>/dev/null || true)"
[ -n "$CUR" ] && [ -f "$ROOT/versions/$CUR/boot.py" ] && [ -f "$ROOT/avvia.py" ] || fail "installazione della versione non riuscita"
rm -f "$ROOT/tmp/updater.py"
printf '%s' "$TOKEN" | NILUFAR_HOME="$ROOT/home" "$PY" "$ROOT/versions/$CUR/scripts/segreti.py" salva github >> "$LOG" 2>&1 \
    || fail "chiave non salvata nel Portachiavi"
TOKEN=""
say "      versione $CUR installata, chiave salvata nel Portachiavi"

# ---------------------------------------------------------------- 5. browser
if [ -d "/Applications/Google Chrome.app" ] || [ -d "$HOME/Applications/Google Chrome.app" ]; then
    say "[5/6] uso Google Chrome installato"
else
    say "[5/6] Chrome non trovato: scarico Chromium per lo strumento (circa 150 MB)..."
    PLAYWRIGHT_BROWSERS_PATH="$RT/browsers" "$PY" -m playwright install chromium </dev/null >> "$LOG" 2>&1 \
        || say "      ATTENZIONE: download di Chromium non riuscito (dettagli nel log)"
    NILUFAR_HOME="$ROOT/home" "$PY" - "$ROOT/home/impostazioni.json" <<'EOF' || true
import json, os, sys
p = sys.argv[1]
try:
    s = json.load(open(p, encoding="utf-8"))
except Exception:
    s = {}
s["browser_channel"] = ""          # Chromium scaricato al posto di Chrome
json.dump(s, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
EOF
fi

# ---------------------------------------------------------------- 6. app
say "[6/6] creo l'app in $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nilufar Tools</string>
    <key>CFBundleDisplayName</key><string>Nilufar Tools</string>
    <key>CFBundleIdentifier</key><string>it.nilufar.tools</string>
    <key>CFBundleExecutable</key><string>nilufar-tools</string>
    <key>CFBundleIconFile</key><string>nilufar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
# il lanciatore parte e finisce subito: ogni clic sull'icona riapre la finestra della dashboard
cat > "$APP/Contents/MacOS/nilufar-tools" <<'EOF'
#!/bin/bash
ROOT="$HOME/Library/Application Support/NilufarTools"
if [ ! -x "$ROOT/runtime/venv/bin/python" ] || [ ! -f "$ROOT/avvia.py" ]; then
    osascript -e 'display alert "Nilufar Tools" message "Installazione incompleta: rilancia la riga di installazione nel Terminale."'
    exit 1
fi
cd "$ROOT/home" 2>/dev/null || cd "$ROOT"
"$ROOT/runtime/venv/bin/python" "$ROOT/avvia.py" </dev/null >/dev/null 2>&1 &
disown
exit 0
EOF
chmod +x "$APP/Contents/MacOS/nilufar-tools"
cp -f "$ROOT/versions/$CUR/static/nilufar.icns" "$APP/Contents/Resources/nilufar.icns" 2>/dev/null || true
/usr/bin/xattr -cr "$APP" 2>/dev/null || true
touch "$APP"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP" </dev/null >/dev/null 2>&1 || true
rm -rf "$RT/uv-cache"

say "avvio Nilufar Tools"
open "$APP" </dev/null || true
echo
echo "  Fatto: trovi Nilufar Tools in Applicazioni (cartella Inizio > Applicazioni) e nel Launchpad."
echo "  Consiglio: trascinala nel Dock. I tuoi Excel vanno in: $DOCS"
echo "  Gli aggiornamenti arrivano da soli all'apertura."
echo
}

main "$@"
