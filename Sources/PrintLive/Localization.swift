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
        "set.whereHUDValue": ["Done, paused, failed and more", "Fertig, pausiert, Fehler und mehr", "Terminé, en pause, échec et plus", "Terminado, en pausa, error y más", "Finito, in pausa, errore e altro", "Klaar, gepauzeerd, mislukt en meer"],
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

        "cam.title": ["Camera", "Kamera", "Caméra", "Cámara", "Fotocamera", "Camera"],
        "cam.unavailable": ["Camera not available", "Kamera nicht verfügbar", "Caméra indisponible", "Cámara no disponible", "Fotocamera non disponibile", "Camera niet beschikbaar"],
        "cam.bambuUnsupported": ["The camera of the X1 and H2 series streams over RTSP, which Print Live can’t show yet", "Die Kamera der X1- und H2-Serie sendet per RTSP, das Print Live noch nicht anzeigen kann", "La caméra des séries X1 et H2 diffuse en RTSP, que Print Live ne sait pas encore afficher", "La cámara de las series X1 y H2 emite por RTSP, que Print Live aún no puede mostrar", "La fotocamera delle serie X1 e H2 trasmette via RTSP, che Print Live non può ancora mostrare", "De camera van de X1- en H2-serie streamt via RTSP, dat Print Live nog niet kan tonen"],
        "cam.anycubicCloudUnsupported": ["Anycubic Cloud streams video through a proprietary service Print Live can’t show. Use LAN mode for the camera", "Anycubic Cloud überträgt Video über einen eigenen Dienst, den Print Live nicht anzeigen kann. Nutze für die Kamera den LAN-Modus", "Anycubic Cloud diffuse la vidéo via un service propriétaire que Print Live ne peut pas afficher. Utilisez le mode LAN pour la caméra", "Anycubic Cloud transmite el vídeo mediante un servicio propio que Print Live no puede mostrar. Usa el modo LAN para la cámara", "Anycubic Cloud trasmette il video tramite un servizio proprietario che Print Live non può mostrare. Usa la modalità LAN per la fotocamera", "Anycubic Cloud streamt video via een eigen dienst die Print Live niet kan tonen. Gebruik LAN-modus voor de camera"],
        "cam.anycubicUnsupported": ["This Anycubic printer offers no camera stream Print Live can show", "Dieser Anycubic-Drucker bietet keinen Kamerastream, den Print Live anzeigen kann", "Cette imprimante Anycubic ne propose aucun flux caméra que Print Live peut afficher", "Esta impresora Anycubic no ofrece ninguna emisión de cámara que Print Live pueda mostrar", "Questa stampante Anycubic non offre uno stream video che Print Live possa mostrare", "Deze Anycubic-printer biedt geen camerastream die Print Live kan tonen"],
        "cam.offline": ["Printer is not connected", "Drucker ist nicht verbunden", "L’imprimante n’est pas connectée", "La impresora no está conectada", "La stampante non è collegata", "Printer is niet verbonden"],
        "cam.loading": ["Connecting to the camera", "Verbinde mit der Kamera", "Connexion à la caméra", "Conectando con la cámara", "Connessione alla fotocamera", "Verbinden met de camera"],
        "cam.switch": ["Switch printer", "Drucker wechseln", "Changer d’imprimante", "Cambiar de impresora", "Cambia stampante", "Andere printer"],

        "hud.firstLayer": ["First layer done", "Erste Schicht fertig", "Première couche terminée", "Primera capa terminada", "Primo strato completato", "Eerste laag klaar"],
        "hud.timeLeft": ["10 minutes left", "Noch 10 Minuten", "Encore 10 minutes", "Quedan 10 minutos", "Mancano 10 minuti", "Nog 10 minuten"],
        "hud.temperature": ["Nozzle is too cold", "Düse ist zu kalt", "La buse est trop froide", "La boquilla está demasiado fría", "L’ugello è troppo freddo", "Nozzle is te koud"],

        "alert.finished": ["Print done", "Druck fertig", "Impression terminée", "Impresión terminada", "Stampa finita", "Print klaar"],
        "alert.finishedDetail": ["When a print finishes.", "Wenn ein Druck fertig ist.", "Quand une impression se termine.", "Cuando termina una impresión.", "Quando una stampa finisce.", "Als een print klaar is."],
        "alert.paused": ["Print paused", "Druck pausiert", "Impression en pause", "Impresión en pausa", "Stampa in pausa", "Print gepauzeerd"],
        "alert.pausedDetail": ["When a print pauses, for example for a filament change.", "Wenn ein Druck pausiert, etwa für einen Filamentwechsel.", "Quand une impression se met en pause, par exemple pour changer de filament.", "Cuando una impresión se pausa, por ejemplo para cambiar el filamento.", "Quando una stampa va in pausa, ad esempio per un cambio di filamento.", "Als een print pauzeert, bijvoorbeeld voor een filamentwissel."],
        "alert.failed": ["Print failed or stopped", "Druck fehlgeschlagen oder abgebrochen", "Impression échouée ou arrêtée", "Impresión fallida o detenida", "Stampa fallita o interrotta", "Print mislukt of gestopt"],
        "alert.failedDetail": ["When a print fails or is stopped.", "Wenn ein Druck fehlschlägt oder abgebrochen wird.", "Quand une impression échoue ou est arrêtée.", "Cuando una impresión falla o se detiene.", "Quando una stampa fallisce o viene interrotta.", "Als een print mislukt of wordt gestopt."],
        "alert.firstLayer": ["First layer done", "Erste Schicht fertig", "Première couche terminée", "Primera capa terminada", "Primo strato completato", "Eerste laag klaar"],
        "alert.firstLayerDetail": ["Once per print, when the second layer starts. A good moment to check adhesion.", "Einmal pro Druck, wenn die zweite Schicht beginnt. Ein guter Moment, die Haftung zu prüfen.", "Une fois par impression, au début de la deuxième couche. Le bon moment pour vérifier l’adhérence.", "Una vez por impresión, al empezar la segunda capa. Buen momento para revisar la adherencia.", "Una volta per stampa, quando inizia il secondo strato. Il momento giusto per controllare l’adesione.", "Eén keer per print, als de tweede laag begint. Een goed moment om de hechting te controleren."],
        "alert.timeLeft": ["10 minutes left", "Noch 10 Minuten", "Encore 10 minutes", "Quedan 10 minutos", "Mancano 10 minuti", "Nog 10 minuten"],
        "alert.timeLeftDetail": ["Once per print, when ten minutes are left.", "Einmal pro Druck, wenn noch zehn Minuten übrig sind.", "Une fois par impression, quand il reste dix minutes.", "Una vez por impresión, cuando quedan diez minutos.", "Una volta per stampa, quando mancano dieci minuti.", "Eén keer per print, als er nog tien minuten over zijn."],
        "alert.temperature": ["Temperature warning", "Temperaturwarnung", "Alerte de température", "Aviso de temperatura", "Avviso di temperatura", "Temperatuurwaarschuwing"],
        "alert.temperatureDetail": ["Once per print, when the nozzle stays more than 15 °C below its target for a minute.", "Einmal pro Druck, wenn die Düse eine Minute lang mehr als 15 °C unter dem Zielwert bleibt.", "Une fois par impression, quand la buse reste plus de 15 °C sous sa consigne pendant une minute.", "Una vez por impresión, cuando la boquilla se mantiene más de 15 °C por debajo de su objetivo durante un minuto.", "Una volta per stampa, quando l’ugello resta per un minuto più di 15 °C sotto il valore impostato.", "Eén keer per print, als de nozzle een minuut lang meer dan 15 °C onder de doeltemperatuur blijft."],

        "ctl.pause": ["Pause", "Pausieren", "Pause", "Pausar", "Pausa", "Pauzeren"],
        "ctl.resume": ["Resume", "Fortsetzen", "Reprendre", "Reanudar", "Riprendi", "Hervatten"],
        "ctl.stop": ["Stop print", "Druck abbrechen", "Arrêter l’impression", "Detener impresión", "Interrompi stampa", "Print stoppen"],
        "ctl.stopTitle": ["Stop the print on %@?", "Druck auf %@ abbrechen?", "Arrêter l’impression sur %@ ?", "¿Detener la impresión en %@?", "Interrompere la stampa su %@?", "Print op %@ stoppen?"],
        "ctl.stopMessage": ["%@ is cancelled and can’t be resumed.", "%@ wird abgebrochen und kann nicht fortgesetzt werden.", "%@ sera annulé et ne pourra pas être repris.", "%@ se cancelará y no se podrá reanudar.", "%@ verrà annullato e non potrà essere ripreso.", "%@ wordt geannuleerd en kan niet worden hervat."],
        "ctl.pauseTitle": ["Pause the print on %@?", "Druck auf %@ pausieren?", "Mettre en pause l’impression sur %@ ?", "¿Pausar la impresión en %@?", "Mettere in pausa la stampa su %@?", "Print op %@ pauzeren?"],
        "ctl.pauseMessage": ["%@ pauses after the current move. You can resume it from the shelf.", "%@ pausiert nach der aktuellen Bewegung. Du kannst ihn im Shelf fortsetzen.", "%@ se met en pause après le mouvement en cours. Vous pouvez la reprendre depuis l’étagère.", "%@ se pausa tras el movimiento actual. Puedes reanudarla desde el estante.", "%@ va in pausa dopo il movimento in corso. Puoi riprenderla dal ripiano.", "%@ pauzeert na de huidige beweging. Je kunt hem op de plank hervatten."],
        "ctl.failed": ["%@ didn’t work", "%@ hat nicht geklappt", "%@ n’a pas fonctionné", "%@ no ha funcionado", "%@ non è riuscito", "%@ is niet gelukt"],
        "ctl.failedShort": ["Not sent", "Nicht gesendet", "Non envoyé", "No enviado", "Non inviato", "Niet verzonden"],

        "spool.left": ["%d g left", "noch %d g", "encore %d g", "quedan %d g", "restano %d g", "nog %d g"],
        "spool.low": ["Not enough filament", "Nicht genug Filament", "Pas assez de filament", "No hay suficiente filamento", "Filamento insufficiente", "Niet genoeg filament"],
        "spool.lowShort": ["Low", "Zu wenig", "Trop peu", "Poco", "Poco", "Te weinig"],
        "spool.link": ["Spool", "Spule", "Bobine", "Bobina", "Bobina", "Spoel"],
        "spool.linkDetail": ["The Spoolman spool loaded in this printer. The shelf shows what is left and warns when a print needs more.", "Die Spoolman-Spule in diesem Drucker. Das Shelf zeigt den Rest und warnt, wenn ein Druck mehr braucht.", "La bobine Spoolman chargée dans cette imprimante. L’étagère affiche le reste et prévient si une impression en demande plus.", "La bobina de Spoolman cargada en esta impresora. El estante muestra lo que queda y avisa si una impresión necesita más.", "La bobina Spoolman caricata in questa stampante. Il ripiano mostra quanto resta e avvisa se una stampa ne richiede di più.", "De Spoolman-spoel in deze printer. De plank toont wat er over is en waarschuwt als een print meer nodig heeft."],
        "spool.none": ["None", "Keine", "Aucune", "Ninguna", "Nessuna", "Geen"],
        "slot.empty": ["empty", "leer", "vide", "vacía", "vuoto", "leeg"],
        "slot.active": ["in use", "aktiv", "en cours", "en uso", "in uso", "in gebruik"],

        "spoolman.detail": ["Link your Spoolman server to see the remaining filament of each printer’s spool. Leave the address empty to turn it off.", "Verbinde deinen Spoolman-Server, um das restliche Filament der Spule jedes Druckers zu sehen. Lass die Adresse leer, um es auszuschalten.", "Reliez votre serveur Spoolman pour voir le filament restant sur la bobine de chaque imprimante. Laissez l’adresse vide pour le désactiver.", "Conecta tu servidor Spoolman para ver el filamento que queda en la bobina de cada impresora. Deja la dirección vacía para desactivarlo.", "Collega il tuo server Spoolman per vedere il filamento rimasto sulla bobina di ogni stampante. Lascia vuoto l’indirizzo per disattivarlo.", "Koppel je Spoolman-server om het resterende filament op de spoel van elke printer te zien. Laat het adres leeg om het uit te zetten."],
        "spoolman.address": ["Spoolman address", "Spoolman-Adresse", "Adresse de Spoolman", "Dirección de Spoolman", "Indirizzo di Spoolman", "Spoolman-adres"],
        "spoolman.test": ["Test", "Testen", "Tester", "Probar", "Prova", "Testen"],
        "spoolman.testing": ["Checking Spoolman", "Prüfe Spoolman", "Vérification de Spoolman", "Comprobando Spoolman", "Verifica di Spoolman", "Spoolman controleren"],
        "spoolman.ok": ["Spoolman is connected", "Spoolman ist verbunden", "Spoolman est connecté", "Spoolman está conectado", "Spoolman è collegato", "Spoolman is verbonden"],
        "spoolman.failed": ["Spoolman is not reachable", "Spoolman ist nicht erreichbar", "Spoolman est injoignable", "Spoolman no está disponible", "Spoolman non è raggiungibile", "Spoolman is niet bereikbaar"],
        "spoolman.count": ["%d spools", "%d Spulen", "%d bobines", "%d bobinas", "%d bobine", "%d spoelen"],

        "set.alerts": ["Alerts", "Meldungen", "Alertes", "Avisos", "Avvisi", "Meldingen"],
        "set.alertsDetail": ["Which moments show a card in the notch.", "Bei welchen Ereignissen eine Karte in der Notch erscheint.", "Les moments qui affichent une carte dans l’encoche.", "Qué momentos muestran una tarjeta en el notch.", "Quali momenti mostrano una scheda nel notch.", "Bij welke momenten een kaart in de notch verschijnt."],
        "set.history": ["History", "Verlauf", "Historique", "Historial", "Cronologia", "Geschiedenis"],
        "set.historyDetail": ["Prints that finished, failed or were stopped while Print Live was running. Stored only on this Mac.", "Drucke, die fertig wurden, fehlschlugen oder abgebrochen wurden, während Print Live lief. Nur auf diesem Mac gespeichert.", "Les impressions terminées, échouées ou arrêtées pendant que Print Live tournait. Enregistré uniquement sur ce Mac.", "Impresiones terminadas, fallidas o detenidas mientras Print Live estaba activo. Solo se guarda en este Mac.", "Stampe finite, fallite o interrotte mentre Print Live era attivo. Salvate solo su questo Mac.", "Prints die klaar waren, mislukten of werden gestopt terwijl Print Live draaide. Alleen op deze Mac bewaard."],
        "hist.prints": ["Prints", "Drucke", "Impressions", "Impresiones", "Stampe", "Prints"],
        "hist.success": ["Success rate", "Erfolgsquote", "Taux de réussite", "Tasa de éxito", "Percentuale di successo", "Slagingspercentage"],
        "hist.time": ["Total print time", "Druckzeit gesamt", "Temps d’impression total", "Tiempo total de impresión", "Tempo di stampa totale", "Totale printtijd"],
        "hist.filament": ["Filament used", "Verbrauchtes Filament", "Filament utilisé", "Filamento usado", "Filamento usato", "Gebruikt filament"],
        "hist.week": ["Print time, last 7 days", "Druckzeit der letzten 7 Tage", "Temps d’impression, 7 derniers jours", "Tiempo de impresión, últimos 7 días", "Tempo di stampa, ultimi 7 giorni", "Printtijd, afgelopen 7 dagen"],
        "hist.clear": ["Clear history", "Verlauf löschen", "Effacer l’historique", "Borrar historial", "Cancella cronologia", "Geschiedenis wissen"],
        "hist.clearButton": ["Clear", "Löschen", "Effacer", "Borrar", "Cancella", "Wissen"],
        "hist.clearTitle": ["Clear the print history?", "Druckverlauf löschen?", "Effacer l’historique des impressions ?", "¿Borrar el historial de impresiones?", "Cancellare la cronologia delle stampe?", "Printgeschiedenis wissen?"],
        "hist.clearMessage": ["All %d entries and the statistics are removed. This can’t be undone.", "Alle %d Einträge und die Statistik werden entfernt. Das lässt sich nicht rückgängig machen.", "Les %d entrées et les statistiques seront supprimées. Action irréversible.", "Se eliminarán las %d entradas y las estadísticas. No se puede deshacer.", "Tutte le %d voci e le statistiche verranno rimosse. Non si può annullare.", "Alle %d items en de statistieken worden verwijderd. Dit kan niet ongedaan worden gemaakt."],

        "set.whereCamera": ["Camera", "Kamera", "Caméra", "Cámara", "Fotocamera", "Camera"],
        "set.whereCameraValue": ["Live picture as a second shelf widget", "Livebild als zweites Shelf-Widget", "Image en direct dans un second widget", "Imagen en directo como segundo widget", "Immagine dal vivo come secondo widget", "Livebeeld als tweede widget"],
        "set.whereMenu": ["Menu bar", "Menüleiste", "Barre des menus", "Barra de menús", "Barra dei menu", "Menubalk"],
        "set.whereMenuValue": ["Every printer with progress and time left", "Alle Drucker mit Fortschritt und Restzeit", "Chaque imprimante avec progression et temps restant", "Cada impresora con progreso y tiempo restante", "Ogni stampante con avanzamento e tempo residuo", "Elke printer met voortgang en resterende tijd"],
    ]
}
