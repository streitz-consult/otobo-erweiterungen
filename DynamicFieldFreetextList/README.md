# DynamicFieldFreetextList — OTOBO-Erweiterung

## Was macht dieses Paket?

Dieses Paket fügt dem OTOBO-Ticketsystem einen neuen Typ für dynamische Felder hinzu: **Freitextfeld mit Liste** (*FreetextList*).

Dieser Typ kombiniert zwei bekannte Feldtypen:

| Feldtyp | Beschreibung |
|---|---|
| **Text** | Nutzer gibt beliebigen Freitext ein |
| **Einfachauswahl** | Nutzer wählt aus einer vordefinierten Liste |
| **FreetextList** *(neu)* | Beides: Aus einer Liste wählen *oder* eigenen Wert eingeben |

**Besonderheit:** Gibt ein Nutzer einen Wert ein, der noch nicht in der Liste vorhanden ist, wird dieser Wert automatisch zur Liste hinzugefügt. Beim nächsten Aufruf steht er als Vorschlag zur Verfügung.

### Typischer Anwendungsfall

- Erfassung von Produktnamen, Projektnummern oder Kategorien, die nicht vollständig vordefiniert sind
- Felder, die sich im Laufe der Zeit durch Nutzereingaben selbst befüllen sollen
- Überall dort, wo eine Freitext-Eingabe gewünscht ist, aber häufige Werte nicht jedes Mal neu getippt werden sollen

---

## Paketstruktur

```
DynamicFieldFreetextList/
├── DynamicFieldFreetextList.sopm            ← Paketdeskriptor (Metadaten, Dateiliste)
├── Build-OPM.ps1                            ← Build-Skript (Windows PowerShell)
├── README.md                                ← Diese Datei
└── Kernel/
    ├── Config/Files/XML/
    │   └── OTOBODynamicFieldFreetextList.xml    ← SysConfig-Registrierung des Feldtyps
    ├── Language/
    │   └── de_OTOBODynamicFieldFreetextList.pm  ← Deutsche Übersetzungen
    ├── Modules/
    │   └── AdminDynamicFieldFreetextList.pm      ← Admin-Backend (Feld konfigurieren)
    ├── Output/HTML/Templates/Standard/
    │   └── AdminDynamicFieldFreetextList.tt      ← Admin-Template (Konfigurationsoberfläche)
    └── System/DynamicField/Driver/
        └── FreetextList.pm                       ← Kern-Treiber (Speichern, Rendern, Suchen)
```

### Erläuterung der wichtigsten Dateien

**`FreetextList.pm` – der Kern-Treiber**  
Erbt von `Kernel::System::DynamicField::Driver::BaseText` (demselben Basistyp wie das Standard-Textfeld) und überschreibt nur die notwendigen Methoden:
- `EditFieldRender` – rendert das Eingabefeld als `<input>` + `<datalist>` (HTML5-Autocomplete)
- `ValueSet` – speichert den Wert und erweitert bei Bedarf automatisch die Werteliste
- `DisplayValueRender` / `ReadableValueRender` – zeigt gespeicherte Werte an
- `SearchFieldRender` / `SearchFieldParameterBuild` – Suchfunktion

**`AdminDynamicFieldFreetextList.pm` – Admin-Modul**  
Klassisches OTOBO-Admin-Modul mit den Subactions `Add`, `AddAction`, `Change`, `ChangeAction`. Verwaltet die Feldkonfiguration inklusive der vordefinierten Werteliste (`PossibleValues`).

**`AdminDynamicFieldFreetextList.tt` – Admin-Template**  
Zeigt die Konfigurationsoberfläche. Die Werteliste ist per JavaScript dynamisch erweiterbar (+ / − Buttons). Eingebettetes Vanilla-JavaScript, keine externe Abhängigkeit.

**`OTOBODynamicFieldFreetextList.xml` – SysConfig**  
Registriert den neuen Feldtyp unter `DynamicFields::Driver###FreetextList` und meldet das Admin-Modul im Frontend-Framework an.

---

## .opm-Paket erstellen (Windows)

Das Build-Skript liest die Dateiliste aus der `.sopm`-Datei, base64-kodiert alle Dateien und schreibt eine fertige `.opm`-Datei.

```powershell
# Im Paketverzeichnis ausführen:
.\Build-OPM.ps1
```

Die erzeugte Datei heißt `DynamicFieldFreetextList-1.0.0.opm` und liegt im selben Verzeichnis.

### Voraussetzungen

- Windows PowerShell 5.1 oder höher (kein OTOBO-Server nötig)
- Die fünf Quelldateien müssen im `Kernel/`-Verzeichnis vorhanden sein

### Alternative: Auf dem OTOBO-Server bauen

Falls das OTOBO-Framework auf einem Linux-Server verfügbar ist:

```bash
cd /opt/otobo
bin/otobo.Console.pl Dev::Package::Build \
    /pfad/zu/DynamicFieldFreetextList.sopm \
    /ausgabe/verzeichnis/
```

---

## Installation in OTOBO

### Über die Web-Oberfläche (empfohlen)

1. Als Administrator einloggen
2. **Admin → Paketverwaltung** öffnen
3. Unter **Paket installieren** → **Durchsuchen…** die `.opm`-Datei auswählen
4. **Installieren** klicken
5. OTOBO führt nach der Installation automatisch ein SysConfig-Deployment durch

### Manuell (auf dem Server)

```bash
bin/otobo.Console.pl Admin::Package::Install \
    /pfad/zu/DynamicFieldFreetextList-1.0.0.opm
```

### Nach der Installation

Das Deployment wird durch den `CodeInstall`-Block automatisch ausgelöst. Bei manuellen Problemen:

```bash
bin/otobo.Console.pl Maint::Config::Rebuild
bin/otobo.Console.pl Maint::Config::Deploy
```

---

## Ein FreetextList-Feld anlegen

1. **Admin → Dynamische Felder** öffnen
2. **Feld hinzufügen** → Objekttyp wählen (z. B. *Ticket*) → **Freetext List**
3. Namen, Bezeichnung und Reihenfolge vergeben
4. Unter **Feld-Einstellungen** die gewünschten Startwerte eintragen (optional)
5. **Speichern**

Das Feld muss anschließend wie jedes andere dynamische Feld den gewünschten Masken zugeordnet werden (**Admin → Dynamische Felder → Bildschirmkonfiguration**).

---

## Deinstallation

Über **Admin → Paketverwaltung** → Paket suchen → **Deinstallieren**.

> **Hinweis:** Die gespeicherten Feldwerte in bestehenden Tickets bleiben in der Datenbank erhalten (`dynamic_field_value`-Tabelle). Das Feld selbst muss vorher unter *Admin → Dynamische Felder* gelöscht werden, wenn die Daten nicht mehr benötigt werden.

---

## Kompatibilität

| OTOBO-Version | Status |
|---|---|
| 10.0.x | ✅ Unterstützt |
| 11.0.x | ✅ Unterstützt |

Der Treiber erbt von `BaseText` und legt keine eigenen Datenbanktabellen an – Kompatibilität mit zukünftigen OTOBO-Versionen ist daher wahrscheinlich, solange die `DynamicField`-API stabil bleibt.

---

## Lizenz

GNU General Public License v3 — siehe https://www.gnu.org/licenses/gpl-3.0.html
