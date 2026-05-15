# Crave Scripts

> **Automated pipeline for building Android ROMs on Crave and uploading the output to Gofile.**

## 🛠️ About

This repository contains a single, focused `build.sh` script used to automate custom ROM compilation on Crave environments. It handles the complete build process, generates OTA metadata, uploads the final artifacts to Gofile, and sends an automated Telegram notification with the download links.

## 🚀 Triggering a Build

To start a build on your Crave environment, simply run the following command in your terminal:

```
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/mayuresh2543/Scripts/refs/heads/13-spes/build.sh | bash -s 1"
```
