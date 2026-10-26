<div align="center">

<img src="docs/images/icon.png" width="128" alt="Print Live icon">

# Print Live for Droppy

**Your 3D prints, live in the notch.**

A [Droppy](https://getdroppy.app) droplet that shows every 3D printer on your network, and Anycubic printers in online mode:
progress next to the notch, all printers on the shelf, and an alert the moment a print is done.

[![Version](https://img.shields.io/badge/version-1.1.0-ff8a00?style=flat-square)](CHANGELOG.md)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Droppy](https://img.shields.io/badge/Droppy-15.3%2B-2f7cf6?style=flat-square)](https://getdroppy.app)
[![OctoPrint](https://img.shields.io/badge/OctoPrint-supported-13c100?style=flat-square)](#octoprint)
[![Bambu Lab](https://img.shields.io/badge/Bambu%20Lab-supported-00ae42?style=flat-square)](#bambu-lab)
[![Anycubic](https://img.shields.io/badge/Anycubic-supported-0a6cff?style=flat-square)](#anycubic)
[![Klipper](https://img.shields.io/badge/Klipper-supported-b12f36?style=flat-square)](#klipper)
[![Anycubic Cloud](https://img.shields.io/badge/Anycubic%20Cloud-supported-5856d6?style=flat-square)](#anycubic-cloud)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

</div>

---

<p align="center">
  <img src="docs/images/shelf.png" width="620" alt="All printers on the Droppy shelf">
</p>

## Features

- 🖨️ **Five printer types**: OctoPrint, Bambu Lab, Anycubic, Klipper (Moonraker) and Anycubic Cloud, side by side
- ⏱️ **Live in the notch**: a progress ring with percent and time left, right next to the notch
- 🗂️ **Shelf overview**: every printer with state, file, time left, finish time, layers and temperatures
- 🔔 **Notch alerts**: a card when a print is done, paused or fails
- 🔒 **Lock screen**: progress of the current print as a line or a ring
- 🏠 **Local first**: talks to your printers on your own network, no cloud, no account
- ☁️ **Anycubic Cloud**: Anycubic printers in normal online mode, without LAN mode, using your account's web token
- 🔑 **Keychain**: API keys, access codes and tokens are stored in the macOS Keychain
- 🌍 **Six languages**: English, Deutsch, Français, Español, Italiano, Nederlands

## Screenshots

| In the notch | On the Dynamic Island |
| :---: | :---: |
| <img src="docs/images/notch.png" width="420" alt="Progress in the notch"> | <img src="docs/images/island.png" width="260" alt="Progress on the island"> |

<p align="center">
  <img src="docs/images/hud.png" width="520" alt="Print done alert"><br>
  <sub>The alert when a print is done</sub>
</p>

<p align="center">
  <img src="docs/images/lock-screen.png" width="760" alt="Lock screen status"><br>
  <sub>Progress on Droppy's lock screen</sub>
</p>

<details>
<summary><b>Settings</b></summary>
<br>
<p align="center"><img src="docs/images/settings.png" width="640" alt="Settings page"></p>
</details>

## Supported printers

| | Connection | What you need |
| --- | --- | --- |
| <a id="octoprint"></a>**OctoPrint** | REST API over HTTP | Address (for example `octopi.local`) and an API key |
| <a id="bambu-lab"></a>**Bambu Lab** (X1, P1, A1 series) | Local MQTT over TLS, port 8883 | LAN mode on, IP address, serial number, access code |
| <a id="anycubic"></a>**Anycubic** (Kobra S1, Kobra 3 and other models with LAN mode) | Local handshake on port 18910, then MQTT over TLS on port 9883 | LAN mode on, IP address |
| <a id="klipper"></a>**Klipper** (Moonraker, for example Mainsail, Fluidd, Creality K1, Sovol) | REST API over HTTP, port 7125 | Address (for example `mainsailos.local`), optional API key |
| <a id="anycubic-cloud"></a>**Anycubic Cloud** (Kobra S1 and other Anycubic printers in online mode) | Anycubic's web API over HTTPS, polled every 30 to 60 seconds | Web token of your Anycubic account, optional printer name |

Print Live only **reads** status. It never starts, pauses or stops a print.

## Requirements

- macOS 14 Sonoma or later
- [Droppy](https://getdroppy.app) 15.3 or later
- Printers on the same network as your Mac (Anycubic Cloud only needs internet access)

## Installation

1. Download **`PrintLive.droplet.zip`** from the [latest release](https://github.com/janluca22467/droppy-3dprint/releases/latest) and unzip it.
2. In Droppy, open **Settings › Store › Local droplets** and drop **`PrintLive.droplet`** onto it.
3. Approve the droplet when Droppy asks.

> [!TIP]
> Try it first in the free [Droppy Playground](https://getdroppy.app/download/playground):
> copy the bundle to `~/Library/Application Support/Droppy Playground/Droplets/print-live/` and relaunch the Playground.

## Setup

Open **Print Live** in Droppy's settings and choose **Add printer**.

### OctoPrint

1. In OctoPrint, open **Settings › Application Keys** and create a key.
2. Enter the address of your OctoPrint, for example `octopi.local` or `192.168.1.30`, and paste the key.

### Bambu Lab

1. On the printer, open **Settings › Network** and turn on **LAN mode**.
2. Note the **IP address**, the **access code** and the **serial number** (Settings › Device).
3. Enter all three in Print Live.

### Anycubic

1. On the printer, turn on **LAN mode**.
2. Enter the printer's **IP address**. Print Live reads everything else from the printer.

### Klipper (Moonraker)

1. Make sure Moonraker is running. It comes with Mainsail, Fluidd and printers such as the Creality K1 or Sovol.
2. Enter the address, for example `mainsailos.local` or `192.168.1.60`. Port 7125 is used unless you add another one, for example `mainsailos.local:7130`.
3. If Moonraker requires an API key, paste it. Otherwise leave the field empty.

### Anycubic Cloud (online mode)

Use this when your Anycubic printer stays in normal online mode and LAN mode is off.

1. Sign in at [cloud-universe.anycubic.com](https://cloud-universe.anycubic.com) in your browser.
2. Open the browser's developer console and run `window.localStorage["XX-Token"]`.
3. Copy the value without the quotes and paste it as **Web token**.
4. If your account has more than one printer, enter its name as **Printer name**. Otherwise leave it empty and the first printer is used.

When the token expires, Print Live shows *Token expired, paste a new one*. Repeat the steps and paste the new token.

> [!NOTE]
> Anycubic Cloud uses Anycubic's unofficial web API. Anycubic can change it at any time, which may break this printer type until Print Live is updated.

## Privacy

- Print Live connects only to the addresses you enter. It makes no other network connections.
- API keys, access codes and tokens are stored in the macOS Keychain on this Mac.
- OctoPrint, Bambu Lab, Anycubic and Klipper printers stay local. Nothing is sent to Anycubic, Bambu Lab or any other cloud.
- Anycubic Cloud is the only exception: it talks to Anycubic's servers with your token to read the printer status.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| *Not reachable* | Check the address and that the Mac and printer are on the same network |
| *API key rejected* | Create a new application key in OctoPrint, or check the Moonraker API key |
| *Klipper is not ready* | Moonraker answers, but Klipper is not running or reports an error. Check Mainsail or Fluidd |
| *Access code rejected* | The Bambu access code changes when LAN mode is toggled. Enter the current one |
| *Printer is in cloud mode. Add it as Anycubic Cloud* | The Anycubic printer is not in LAN mode. Switch it to LAN mode, or add it as Anycubic Cloud |
| *Token expired, paste a new one* | The Anycubic Cloud token is no longer valid. Get a new one as described above |
| *Anycubic Cloud is busy, retrying* | Anycubic's servers rejected the request for now. Print Live tries again in two minutes |
| *No printer found in this account* | Check the printer name, or leave it empty to use the first printer of the account |
| Nothing in the notch | The notch only shows a printer while it prints, and for ten minutes after it is done |

## Build from source

Print Live is a Swift package built with [DroppyKit](https://getdroppy.app/docs/droppykit).

```bash
git clone https://gitlab.com/droppyformac1/droppykit.git
export PATH="$PWD/droppykit/Scripts:$PATH"

git clone https://github.com/janluca22467/droppy-3dprint.git
cd droppy-3dprint
droppykit build
droppykit validate
droppykit run
```

<details>
<summary><b>Project layout</b></summary>

```
droplet.json                     manifest: id, version, capabilities, surfaces
Package.swift                    the droplet library and its harness
Sources/PrintLive/
  PrintLiveDroplet.swift         printers, state, notch, shelf, alerts, lock screen
  PrinterModels.swift            printer settings and print status
  OctoPrintConnection.swift      OctoPrint REST client
  BambuConnection.swift          Bambu Lab local MQTT client
  AnycubicConnection.swift       Anycubic LAN handshake and MQTT client
  MoonrakerConnection.swift      Klipper (Moonraker) REST client
  AnycubicCloudConnection.swift  Anycubic Cloud web API client
  MQTTClient.swift               small MQTT 3.1.1 client over TLS
  PrintViews.swift               notch, shelf and alert views
  PrintLiveSettings.swift        settings page
  SecretStore.swift              Keychain storage
  Localization.swift             the six languages
PrintLive.icon/                  app icon
```
</details>

## License

[MIT](LICENSE) © [Jan-Luca](https://github.com/janluca22467)

Print Live is an independent project and is not affiliated with Droppy, OctoPrint, Bambu Lab, Anycubic, Klipper or Moonraker.
