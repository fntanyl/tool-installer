# Nilufar Tools: installazione

Serve la **chiave di installazione** (inizia con `github_pat_`): te la da' chi mantiene lo strumento.
Non servono permessi di amministratore. Rilanciare la stessa riga ripara l'installazione.

## Mac

Apri **Terminale** (Cmd+Spazio, scrivi Terminale), incolla questa riga e premi Invio:

```
curl -fsSL https://raw.githubusercontent.com/fntanyl/nilufar-tools-installer/main/installa-mac.sh | bash
```

Alla fine trovi **Nilufar Tools** in Applicazioni e nel Launchpad: trascinala nel Dock.

## Windows

Premi **Win+R**, incolla questa riga e premi Invio:

```
powershell -NoProfile -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/fntanyl/nilufar-tools-installer/main/installa-win.ps1 | iex"
```

Alla fine trovi **Nilufar Tools** nel Menu Start e sul Desktop. Se avevi la vecchia cartella NilufarTools
(con AVVIA.bat), login e impostazioni vengono portati da soli.

## Aggiornamenti

Arrivano da soli all'apertura dell'app. Se una versione nuova da' problemi:
Impostazioni > Aggiornamenti > **Torna alla versione precedente**.

## Disinstallare

I tuoi documenti (cartella Documenti > Nilufar Tools) restano sempre dove sono.

- Mac: `curl -fsSL https://raw.githubusercontent.com/fntanyl/nilufar-tools-installer/main/installa-mac.sh | bash -s -- --disinstalla`
- Windows (Win+R): `powershell -NoProfile -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12'; $env:NILUFAR_DISINSTALLA='1'; irm https://raw.githubusercontent.com/fntanyl/nilufar-tools-installer/main/installa-win.ps1 | iex"`
