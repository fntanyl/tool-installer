# Installazione

Serve la **chiave di installazione** (inizia con `github_pat_`): te la da' chi ti ha mandato questo link.
Non servono permessi di amministratore. Rilanciare la stessa riga ripara l'installazione.

## Mac

Apri **Terminale** (Cmd+Spazio, scrivi Terminale), incolla questa riga e premi Invio:

```
curl -fsSL https://raw.githubusercontent.com/fntanyl/tool-installer/main/installa-mac.sh | bash
```

Quando lo chiede, incolla la chiave (Cmd+V, mentre la incolli non si vede: e' normale) e premi Invio.
Alla fine l'app si apre da sola: la trovi in Applicazioni e nel Launchpad, trascinala nel Dock.

## Windows

Premi **Win+R**, incolla questa riga e premi Invio:

```
powershell -NoProfile -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/fntanyl/tool-installer/main/installa-win.ps1 | iex"
```

Quando lo chiede, incolla la chiave (tasto destro del mouse) e premi Invio. Alla fine l'app si apre da sola:
la trovi nel Menu Start e sul Desktop.

## Aggiornamenti

Arrivano da soli all'apertura dell'app. Se una versione nuova da' problemi:
Impostazioni > Aggiornamenti > **Torna alla versione precedente**.

## Disinstallare

I tuoi documenti restano sempre dove sono.

- Mac: `curl -fsSL https://raw.githubusercontent.com/fntanyl/tool-installer/main/installa-mac.sh | bash -s -- --disinstalla`
- Windows (Win+R): `powershell -NoProfile -ExecutionPolicy Bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12'; $env:DISINSTALLA='1'; irm https://raw.githubusercontent.com/fntanyl/tool-installer/main/installa-win.ps1 | iex"`
