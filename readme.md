# Crave Scripts

> **Automated pipeline for building Android ROMs on Crave and uploading the output to Gofile.**

## 🛠️ About

This repository contains a single, focused `build.sh` script used to automate custom ROM compilation on Crave environments. It handles the complete build process, generates OTA metadata, uploads the final artifacts to Gofile, and sends an automated Telegram notification with the download links.

## 🚀 Triggering a Build

To start a build on your Crave environment, simply copy and paste the command for your desired ROM into your terminal:

### 📱 Xiaomi Poco X5 / Redmi Note 12 5G (`stone`)

**LineageOS 23.2**
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/mayuresh2543/Scripts/refs/heads/16/build.sh | bash -s stone 1"
```

**YAAP 16.2**
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/mayuresh2543/Scripts/refs/heads/16/build.sh | bash -s stone 2"
```

**Infinity-X**
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/mayuresh2543/Scripts/refs/heads/16/build.sh | bash -s stone 3"
```




### 📱 Xiaomi Redmi Note 11 (`spes`)

**LineageOS 20**
```bash
crave run --no-patch -- "curl -s https://raw.githubusercontent.com/mayuresh2543/Scripts/refs/heads/16/build.sh | bash -s spes 1"
```
