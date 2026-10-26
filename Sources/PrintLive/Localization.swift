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
        "err.lanMode": ["Turn on LAN mode on the printer", "LAN-Modus am Drucker einschalten", "Activez le mode LAN sur l’imprimante", "Activa el modo LAN en la impresora", "Attiva la modalità LAN sulla stampante", "Zet LAN-modus aan op de printer"],
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
        "set.printersDetail": ["Print Live connects to your printers on the local network. Nothing goes through the cloud.", "Print Live verbindet sich im lokalen Netzwerk mit deinen Druckern. Nichts läuft über eine Cloud.", "Print Live se connecte à vos imprimantes sur le réseau local. Rien ne passe par le cloud.", "Print Live se conecta a tus impresoras en la red local. Nada pasa por la nube.", "Print Live si collega alle stampanti nella rete locale. Nulla passa dal cloud.", "Print Live verbindt via het lokale netwerk met je printers. Niets gaat via de cloud."],
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
