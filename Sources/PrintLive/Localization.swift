import Foundation

enum L {
    private static let languages = ["en", "de", "fr", "es", "it", "nl"]

    private static let index: Int = {
        let preferred = (Bundle.main.preferredLocalizations + Locale.preferredLanguages)
            .map { String($0.prefix(2)).lowercased() }
        for code in preferred {
            if let i = languages.firstIndex(of: code) { return i }
        }
        return 0
    }()

    static func s(_ key: String) -> String {
        guard let row = table[key] else { return key }
        return row.indices.contains(index) ? row[index] : row[0]
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: Locale(identifier: languages[index]), arguments: args)
    }

    private static let table: [String: [String]] = [
        "state.offline": ["Offline", "Offline", "Hors ligne", "Sin conexión", "Offline", "Offline"],
        "state.connecting": ["Connecting", "Verbinde", "Connexion", "Conectando", "Connessione", "Verbinden"],
        "state.idle": ["Ready", "Bereit", "Prête", "Lista", "Pronta", "Gereed"],
        "state.preparing": ["Preparing", "Vorbereitung", "Préparation", "Preparando", "Preparazione", "Voorbereiden"],
        "state.printing": ["Printing", "Druckt", "Impression", "Imprimiendo", "In stampa", "Printen"],
        "state.paused": ["Paused", "Pausiert", "En pause", "En pausa", "In pausa", "Gepauzeerd"],
        "state.finished": ["Done", "Fertig", "Terminé", "Terminado", "Finito", "Klaar"],
        "state.failed": ["Failed", "Fehler", "Échec", "Error", "Errore", "Mislukt"],
        "state.stopped": ["Stopped", "Abgebrochen", "Arrêtée", "Detenida", "Interrotta", "Gestopt"],

        "err.unreachable": ["Not reachable", "Nicht erreichbar", "Injoignable", "No disponible", "Non raggiungibile", "Niet bereikbaar"],
        "err.apiKey": ["API key rejected", "API-Key abgelehnt", "Clé API refusée", "Clave API rechazada", "Chiave API rifiutata", "API-sleutel geweigerd"],
        "err.http": ["Error %d", "Fehler %d", "Erreur %d", "Error %d", "Errore %d", "Fout %d"],
        "err.accessCode": ["Access code rejected", "Zugangscode abgelehnt", "Code d’accès refusé", "Código de acceso rechazado", "Codice di accesso rifiutato", "Toegangscode geweigerd"],
        "err.lanMode": ["Printer is in cloud mode. Add it as Anycubic Cloud", "Drucker ist im Cloud-Modus. Als Anycubic Cloud hinzufügen", "L’imprimante est en mode cloud. Ajoutez-la comme Anycubic Cloud", "La impresora está en modo nube. Añádela como Anycubic Cloud", "La stampante è in modalità cloud. Aggiungila come Anycubic Cloud", "Printer staat in cloudmodus. Voeg hem toe als Anycubic Cloud"],
        "err.token": ["Token expired, paste a new one", "Token abgelaufen, füge einen neuen ein", "Jeton expiré, collez-en un nouveau", "Token caducado, pega uno nuevo", "Token scaduto, incollane uno nuovo", "Token verlopen, plak een nieuwe"],
        "err.cloudBusy": ["Anycubic Cloud is busy, retrying", "Anycubic Cloud ist ausgelastet, neuer Versuch folgt", "Anycubic Cloud est occupé, nouvel essai", "Anycubic Cloud está ocupado, reintentando", "Anycubic Cloud è occupato, nuovo tentativo", "Anycubic Cloud is bezet, opnieuw proberen"],
        "err.noPrinter": ["No printer found in this account", "Kein Drucker in diesem Konto gefunden", "Aucune imprimante dans ce compte", "No hay ninguna impresora en esta cuenta", "Nessuna stampante in questo account", "Geen printer gevonden in dit account"],
        "err.refused": ["Printer refused the connection", "Drucker hat abgelehnt", "Connexion refusée", "Conexión rechazada", "Connessione rifiutata", "Verbinding geweigerd"],
        "err.incomplete": ["Settings incomplete", "Angaben unvollständig", "Réglages incomplets", "Ajustes incompletos", "Impostazioni incomplete", "Gegevens onvolledig"],

        "widget.empty": ["Add a printer in Droppy’s settings", "Füge in den Droppy-Einstellungen einen Drucker hinzu", "Ajoutez une imprimante dans les réglages de Droppy", "Añade una impresora en los ajustes de Droppy", "Aggiungi una stampante nelle impostazioni di Droppy", "Voeg een printer toe in de instellingen van Droppy"],
        "widget.left": ["%@ left", "noch %@", "encore %@", "quedan %@", "mancano %@", "nog %@"],
        "widget.done": ["done %@", "fertig %@", "fin %@", "listo %@", "fine %@", "klaar %@"],

        "hud.finished": ["%@ is done", "%@ ist fertig", "%@ est terminé", "%@ ha terminado", "%@ è finito", "%@ is klaar"],
        "hud.paused": ["%@ paused", "%@ pausiert", "%@ en pause", "%@ en pausa", "%@ in pausa", "%@ gepauzeerd"],
        "hud.failed": ["%@ stopped printing", "%@ hat den Druck gestoppt", "%@ a arrêté l’impression", "%@ ha detenido la impresión", "%@ ha interrotto la stampa", "%@ is gestopt met printen"],
        "hud.took": ["took %@", "Dauer %@", "durée %@", "duró %@", "durata %@", "duur %@"],

        "set.printers": ["Printers", "Drucker", "Imprimantes", "Impresoras", "Stampanti", "Printers"],
        "set.printersDetail": ["Print Live connects to your printers on the local network. Only Anycubic Cloud printers go through Anycubic’s servers.", "Print Live verbindet sich im lokalen Netzwerk mit deinen Druckern. Nur Anycubic-Cloud-Drucker laufen über die Server von Anycubic.", "Print Live se connecte à vos imprimantes sur le réseau local. Seules les imprimantes Anycubic Cloud passent par les serveurs d’Anycubic.", "Print Live se conecta a tus impresoras en la red local. Solo las impresoras Anycubic Cloud pasan por los servidores de Anycubic.", "Print Live si collega alle stampanti nella rete locale. Solo le stampanti Anycubic Cloud passano dai server di Anycubic.", "Print Live verbindt via het lokale netwerk met je printers. Alleen Anycubic Cloud-printers gaan via de servers van Anycubic."],
        "set.none": ["No printers yet", "Noch keine Drucker", "Aucune imprimante", "Aún no hay impresoras", "Nessuna stampante", "Nog geen printers"],
        "set.add": ["Add printer", "Drucker hinzufügen", "Ajouter une imprimante", "Añadir impresora", "Aggiungi stampante", "Printer toevoegen"],
        "set.edit": ["Edit", "Bearbeiten", "Modifier", "Editar", "Modifica", "Wijzigen"],
        "set.reconnect": ["Reconnect", "Neu verbinden", "Reconnecter", "Reconectar", "Riconnetti", "Opnieuw verbinden"],
        "set.disabled": ["Off", "Aus", "Désactivée", "Desactivada", "Disattivata", "Uit"],
        "set.delete": ["Delete", "Löschen", "Supprimer", "Eliminar", "Elimina", "Verwijderen"],
        "set.cancel": ["Cancel", "Abbrechen", "Annuler", "Cancelar", "Annulla", "Annuleren"],
        "set.save": ["Save", "Speichern", "Enregistrer", "Guardar", "Salva", "Opslaan"],
        "set.where": ["Where it shows up", "Wo es erscheint", "Où il apparaît", "Dónde aparece", "Dove appare", "Waar het verschijnt"],
        "set.whereNotch": ["Notch", "Notch", "Encoche", "Notch", "Notch", "Notch"],
        "set.whereNotchValue": ["Progress ring and time left", "Fortschrittsring und Restzeit", "Anneau de progression et temps restant", "Anillo de progreso y tiempo restante", "Anello di avanzamento e tempo residuo", "Voortgangsring en resterende tijd"],
        "set.whereShelf": ["Shelf", "Shelf", "Étagère", "Estante", "Ripiano", "Plank"],
        "set.whereShelfValue": ["Every printer with temperatures", "Alle Drucker mit Temperaturen", "Toutes les imprimantes et températures", "Todas las impresoras con temperaturas", "Tutte le stampanti con temperature", "Alle printers met temperaturen"],
        "set.whereHUD": ["Alerts", "Meldungen", "Alertes", "Avisos", "Avvisi", "Meldingen"],
        "set.whereHUDValue": ["Done, paused or failed", "Fertig, pausiert oder Fehler", "Terminé, en pause ou échec", "Terminado, en pausa o error", "Finito, in pausa o errore", "Klaar, gepauzeerd of mislukt"],
        "set.whereLock": ["Lock screen", "Sperrbildschirm", "Écran verrouillé", "Pantalla de bloqueo", "Schermata di blocco", "Vergrendelscherm"],
        "set.whereLockValue": ["Progress of the current print", "Fortschritt des laufenden Drucks", "Progression de l’impression", "Progreso de la impresión", "Avanzamento della stampa", "Voortgang van de print"],

        "help.octoprint": ["Enter the address of OctoPrint, for example octopi.local, and an API key from OctoPrint › Settings › Application Keys.", "Gib die Adresse von OctoPrint ein, zum Beispiel octopi.local, und einen API-Key aus OctoPrint › Einstellungen › Application Keys.", "Saisissez l’adresse d’OctoPrint, par exemple octopi.local, et une clé API depuis OctoPrint › Paramètres › Application Keys.", "Introduce la dirección de OctoPrint, por ejemplo octopi.local, y una clave API de OctoPrint › Ajustes › Application Keys.", "Inserisci l’indirizzo di OctoPrint, ad esempio octopi.local, e una chiave API da OctoPrint › Impostazioni › Application Keys.", "Voer het adres van OctoPrint in, bijvoorbeeld octopi.local, en een API-sleutel uit OctoPrint › Instellingen › Application Keys."],
        "help.bambu": ["Turn on LAN mode on the printer. Its IP address, serial number and access code are on the printer screen under Settings › Network.", "Schalte am Drucker den LAN-Modus ein. IP-Adresse, Seriennummer und Zugangscode stehen am Druckerdisplay unter Einstellungen › Netzwerk.", "Activez le mode LAN sur l’imprimante. L’adresse IP, le numéro de série et le code d’accès sont sur l’écran sous Réglages › Réseau.", "Activa el modo LAN en la impresora. La IP, el número de serie y el código de acceso están en la pantalla en Ajustes › Red.", "Attiva la modalità LAN. Indirizzo IP, numero di serie e codice di accesso sono sul display in Impostazioni › Rete.", "Zet LAN-modus aan op de printer. IP-adres, serienummer en toegangscode staan op het scherm onder Instellingen › Netwerk."],
        "help.anycubic": ["Turn on LAN mode on the printer (Kobra S1, Kobra 3 and others with LAN mode) and enter its IP address. Everything else is read from the printer.", "Schalte am Drucker den LAN-Modus ein (Kobra S1, Kobra 3 und andere mit LAN-Modus) und gib seine IP-Adresse ein. Den Rest liest Print Live vom Drucker.", "Activez le mode LAN (Kobra S1, Kobra 3 et autres) et saisissez son adresse IP. Le reste est lu depuis l’imprimante.", "Activa el modo LAN (Kobra S1, Kobra 3 y otras) e introduce su IP. El resto se lee de la impresora.", "Attiva la modalità LAN (Kobra S1, Kobra 3 e altre) e inserisci il suo indirizzo IP. Il resto viene letto dalla stampante.", "Zet LAN-modus aan (Kobra S1, Kobra 3 en andere) en voer het IP-adres in. De rest leest Print Live van de printer."],

        "help.moonraker": ["For Klipper printers with Moonraker, such as Mainsail, Fluidd, Creality K1 or Sovol. Enter the address, for example mainsailos.local. Port 7125 is used unless you add another one.", "Für Klipper-Drucker mit Moonraker, etwa Mainsail, Fluidd, Creality K1 oder Sovol. Gib die Adresse ein, zum Beispiel mainsailos.local. Ohne Angabe wird Port 7125 benutzt.", "Pour les imprimantes Klipper avec Moonraker, comme Mainsail, Fluidd, Creality K1 ou Sovol. Saisissez l’adresse, par exemple mainsailos.local. Le port 7125 est utilisé par défaut.", "Para impresoras Klipper con Moonraker, como Mainsail, Fluidd, Creality K1 o Sovol. Introduce la dirección, por ejemplo mainsailos.local. Se usa el puerto 7125 si no indicas otro.", "Per stampanti Klipper con Moonraker, come Mainsail, Fluidd, Creality K1 o Sovol. Inserisci l’indirizzo, ad esempio mainsailos.local. Senza porta viene usata la 7125.", "Voor Klipper-printers met Moonraker, zoals Mainsail, Fluidd, Creality K1 of Sovol. Voer het adres in, bijvoorbeeld mainsailos.local. Zonder poort wordt 7125 gebruikt."],
        "help.anycubicCloud": ["Use this when the printer is not in LAN mode. Sign in at cloud-universe.anycubic.com, open the browser’s developer console, run window.localStorage[\"XX-Token\"] and paste the value without quotes.", "Nutze diesen Typ, wenn der Drucker nicht im LAN-Modus ist. Melde dich auf cloud-universe.anycubic.com an, öffne die Entwicklerkonsole des Browsers, führe window.localStorage[\"XX-Token\"] aus und füge den Wert ohne Anführungszeichen ein.", "À utiliser quand l’imprimante n’est pas en mode LAN. Connectez-vous sur cloud-universe.anycubic.com, ouvrez la console développeur du navigateur, exécutez window.localStorage[\"XX-Token\"] et collez la valeur sans guillemets.", "Úsalo cuando la impresora no está en modo LAN. Inicia sesión en cloud-universe.anycubic.com, abre la consola de desarrollador del navegador, ejecuta window.localStorage[\"XX-Token\"] y pega el valor sin comillas.", "Usalo quando la stampante non è in modalità LAN. Accedi a cloud-universe.anycubic.com, apri la console per sviluppatori del browser, esegui window.localStorage[\"XX-Token\"] e incolla il valore senza virgolette.", "Gebruik dit als de printer niet in LAN-modus staat. Meld je aan op cloud-universe.anycubic.com, open de ontwikkelaarsconsole van de browser, voer window.localStorage[\"XX-Token\"] uit en plak de waarde zonder aanhalingstekens."],
        "field.webToken": ["Web token", "Web-Token", "Jeton web", "Token web", "Token web", "Webtoken"],
        "field.printerName": ["Printer name (optional)", "Druckername (optional)", "Nom de l’imprimante (facultatif)", "Nombre de la impresora (opcional)", "Nome della stampante (facoltativo)", "Printernaam (optioneel)"],
        "field.apiKeyOptional": ["API key (optional)", "API-Key (optional)", "Clé API (facultatif)", "Clave API (opcional)", "Chiave API (facoltativa)", "API-sleutel (optioneel)"],
        "err.klippy": ["Klipper is not ready", "Klipper ist nicht bereit", "Klipper n’est pas prêt", "Klipper no está listo", "Klipper non è pronto", "Klipper is niet gereed"],
        "field.name": ["Name", "Name", "Nom", "Nombre", "Nome", "Naam"],
        "field.host": ["Address", "Adresse", "Adresse", "Dirección", "Indirizzo", "Adres"],
        "field.apiKey": ["API key", "API-Key", "Clé API", "Clave API", "Chiave API", "API-sleutel"],
        "field.serial": ["Serial number", "Seriennummer", "Numéro de série", "Número de serie", "Numero di serie", "Serienummer"],
        "field.accessCode": ["Access code", "Zugangscode", "Code d’accès", "Código de acceso", "Codice di accesso", "Toegangscode"],
        "field.enabled": ["Connect", "Verbinden", "Connecter", "Conectar", "Collega", "Verbinden"],
        "field.ready": ["Ready to save", "Bereit zum Speichern", "Prêt à enregistrer", "Listo para guardar", "Pronto da salvare", "Klaar om op te slaan"],
        "field.missing": ["Fill in every field", "Bitte alle Felder ausfüllen", "Remplissez tous les champs", "Rellena todos los campos", "Compila tutti i campi", "Vul alle velden in"],
    ]
}
