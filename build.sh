#!/bin/bash

# ==========================================
# ⚙️ Global Configuration
# ==========================================
DEVICE="stone"
START_TIME=$(date +%s)

# 📱 Telegram Notification Setup
TELEGRAM_TOKEN="8801527482:AAGiuNQtKJka2bbOxeZap25PDsgYEoK77AQ"
TELEGRAM_CHAT_ID="-1003914151464"
# ==========================================

# Strict Execution: Abort on any failure
set -e

# ==========================================
# 📨 Telegram Helper Function & Error Trap
# ==========================================
# This function sends whatever message we give it safely
send_tg_msg() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=${MESSAGE}" > /dev/null
}

# This function is triggered ONLY if the script crashes
handle_error() {
    local FAILED_LINE="$1"
    echo "❌ CRITICAL: Build failed on line $FAILED_LINE!"

    local FAIL_MSG="❌ <b>Build FAILED!</b>%0A📱 <b>Device:</b> ${DEVICE}%0A⚠️ <b>Error at script line:</b> ${FAILED_LINE}%0A💻 Check Crave logs immediately."
    send_tg_msg "$FAIL_MSG"
    exit 1
}

# Set the trap! If any command fails, run handle_error and pass the line number
trap 'handle_error $LINENO' ERR
# ==========================================

# Read the ROM choice from the command line argument (Default to 1 if empty)
ROM_CHOICE=${1:-1}

echo "=========================================="
echo "🔍 Analyzing Build Request..."
echo "=========================================="

# ==========================================
# 🔀 The Switchboard (Define your ROMs here)
# ==========================================
case $ROM_CHOICE in
    1)
        ROM_NAME="LineageOS 23.2"
        ROM_VERSION="23.2"
        GH_REPO="mayuresh-releases/LineageOS_stone"

        REPO_INIT_URL="https://github.com/LineageOS/android.git"
        REPO_INIT_BRANCH="lineage-23.2"
        USE_LOCAL_MANIFEST="true"
        LOCAL_MANIFEST_BRANCH="lineage-16"
        BUILD_TARGET="lineage_stone-bp4a-userdebug"
        BUILD_COMMAND="m bacon"

        CUSTOM_REPOS=(
            "packages/apps/Updater|lineage_qpr2_packages_apps_Updater"
            "packages/apps/Launcher3|lineage_qpr2_packages_apps_Launcher3"
            "frameworks/native|lineage_qpr2_frameworks_native"
            "frameworks/base|lineage_qpr2_frameworks_base"
            "bionic|lineage_qpr2_bionic"
            "art|lineage_qpr2_from-aosp_art"
            "frameworks/libs/systemui|lineage_qpr2_frameworks_libs_systemui"
        )
        MANUAL_GIT_CLONES=()
        ;;

    2)
        ROM_NAME="YAAP 16.2"
        GH_REPO="mayuresh-releases/YAAP_stone"

        REPO_INIT_URL="https://github.com/yaap/manifest.git"
        REPO_INIT_BRANCH="sixteen"
        USE_LOCAL_MANIFEST="true"
        LOCAL_MANIFEST_BRANCH="yaap-16"
        BUILD_TARGET="yaap_stone-userdebug"
        BUILD_COMMAND="m yaap"

        CUSTOM_REPOS=(
            "build/soong|yaap_build_soong"
            "build/make|yaap_build_make"
        )
        MANUAL_GIT_CLONES=()
        ;;

    3)
        ROM_NAME="Infinity-X"
        GH_REPO="mayuresh-releases/Infinity-X_stone"

        REPO_INIT_URL="https://github.com/projectinfinity-X/manifest"
        REPO_INIT_BRANCH="16"
        USE_LOCAL_MANIFEST="false"
        LOCAL_MANIFEST_BRANCH=""
        BUILD_TARGET="infinity_stone-userdebug"
        BUILD_COMMAND="m bacon"
        CUSTOM_REPOS=()

        MANUAL_GIT_CLONES=(
            "git clone --depth=1 https://github.com/Infinity-X-Devices/device_xiaomi_stone.git device/xiaomi/stone"
            "git clone --depth=1 https://github.com/Infinity-X-Devices/vendor_xiaomi_stone.git vendor/xiaomi/stone"
            "git clone --depth=1 https://github.com/Infinity-X-Devices/kernel_xiaomi_stone.git kernel/xiaomi/stone"
            "git clone --depth=1 https://github.com/mayuresh-sources/hardware_dolby.git -b sony-1.0 hardware/dolby"
            "git clone --depth=1 https://github.com/LineageOS/android_hardware_xiaomi.git -b lineage-23.2 hardware/xiaomi"
            "git clone --depth=1 https://github.com/mayuresh-sources/packages_apps_ViPER4AndroidFX.git packages/apps/ViPER4AndroidFX"
        )
        ;;

    4)
        ROM_NAME="Project Matrixx"

        REPO_INIT_URL="https://github.com/ProjectMatrixx/android.git"
        REPO_INIT_BRANCH="16.2"
        USE_LOCAL_MANIFEST="true"
        LOCAL_MANIFEST_BRANCH="matrixx-16"
        BUILD_TARGET="matrixx_stone-bp4a-user"
        BUILD_COMMAND="make matrixx"

        CUSTOM_REPOS=()
        MANUAL_GIT_CLONES=()
        ;;

    *)
        echo "❌ Invalid ROM choice! Please use a valid number."
        exit 1
        ;;
esac

echo "✅ Selected ROM: $ROM_NAME"

# ==========================================
# 🚀 SEND START NOTIFICATION
# ==========================================
echo "📱 Sending 'Build Started' notification..."
START_MSG="⏳ <b>Build Started!</b>%0A📱 <b>Device:</b> ${DEVICE}%0A💿 <b>ROM:</b> ${ROM_NAME}%0A💻 <b>Host:</b> Crave"
send_tg_msg "$START_MSG"

echo "=========================================="
echo "🚀 Starting Build Environment Setup"
echo "=========================================="

# 1. Cleanup & Base Sync
repo init -u "$REPO_INIT_URL" -b "$REPO_INIT_BRANCH" --git-lfs

# Handle Local Manifests based on ROM choice
rm -rf .repo/local_manifests/
if [ "$USE_LOCAL_MANIFEST" == "true" ]; then
    echo "📄 Cloning local manifests..."
    git clone -b "$LOCAL_MANIFEST_BRANCH" https://github.com/Mayuresh2543/local_manifests.git .repo/local_manifests
else
    echo "⏭️ Skipping local manifests (Not supported by $ROM_NAME)."
fi

/opt/crave/resync.sh

# 1.5 Execute Manual Git Clones (If any are defined)
if [ ${#MANUAL_GIT_CLONES[@]} -gt 0 ]; then
    echo "=========================================="
    echo "📥 Executing Manual Source Clones..."
    for clone_cmd in "${MANUAL_GIT_CLONES[@]}"; do
        TARGET_DIR=$(echo "$clone_cmd" | awk '{print $NF}')
        echo "🧹 Cleaning $TARGET_DIR..."
        rm -rf "$TARGET_DIR"

        echo "🚀 Running: $clone_cmd"
        eval "$clone_cmd"
    done
    echo "✅ Manual clones completed."
fi

# 2. Parallel Custom Source Sync
if [ ${#CUSTOM_REPOS[@]} -gt 0 ]; then
    echo "=========================================="
    echo "Syncing custom repositories in parallel for $ROM_NAME..."
    BASE_URL="https://github.com/mayuresh-sources"

    for repo_info in "${CUSTOM_REPOS[@]}"; do
        DIR="${repo_info%%|*}"
        REPO_NAME="${repo_info##*|}"

        rm -rf "$DIR"
        git clone "$BASE_URL/$REPO_NAME.git" --depth=1 "$DIR" &
    done
    wait # Wait for all background tasks to finish
    echo "✅ Custom sources synced."
else
    echo "⏭️ No custom repos defined for $ROM_NAME. Skipping parallel sync."
fi

# 3. Environment Variables
export BUILD_USERNAME=mayuresh
export BUILD_HOSTNAME=crave
export TZ="Asia/Kolkata"

# 4. Setup & Lunch
source build/envsetup.sh
lunch "$BUILD_TARGET"

# 5. Prep the output directory
echo "Cleaning output directory..."
m installclean

# 6. Compilation with Logging
echo "=========================================="
echo "🔨 Starting compilation for $ROM_NAME..."
echo "⚙️ Executing: $BUILD_COMMAND"
echo "=========================================="

# Create a highly specific log file name
LOG_FILE="build_${DEVICE}_$(date +%Y%m%d_%H%M).log"

# Dynamically run whatever command the ROM needs, pipe to log
$BUILD_COMMAND 2>&1 | tee "$LOG_FILE"

# Calculate precise time taken
END_TIME=$(date +%s)
BUILD_MINUTES=$(((END_TIME - START_TIME) / 60))
echo "⏱️ Build finished in $BUILD_MINUTES minutes."

# ==========================================
# Post-Build Artifact Processing & Upload
# ==========================================
echo "=========================================="
echo "☁️ Preparing files for Gofile upload..."

if ! command -v jq &> /dev/null; then
    echo "⚠️ 'jq' is missing. Installing..."
    sudo apt-get install -y jq > /dev/null
fi

TARGET_DIR="out/target/product/${DEVICE}"
ROM_ZIP=$(ls -t ${TARGET_DIR}/*${DEVICE}*.zip 2>/dev/null | head -n 1)
FILES_TO_UPLOAD=()

if [ -n "$ROM_ZIP" ] && [ -f "$ROM_ZIP" ]; then
    FILES_TO_UPLOAD+=("$ROM_ZIP")
    echo "✅ Found ROM: $(basename "$ROM_ZIP")"
else
    # This will trigger the ERR trap we set at the top!
    echo "❌ ROM zip not found in ${TARGET_DIR}."
    exit 1
fi

# ==========================================
# 📝 OTA JSON Metadata Generation / Handling
# ==========================================
echo "=========================================="
echo "📝 Processing OTA JSON Metadata..."

FILE_NAME=$(basename "$ROM_ZIP")
REL_TAG=$(date +%y%m%d)

case $ROM_CHOICE in
    1)
        # 🟢 LineageOS Standard Structure
        echo "Generating standard stone.json for LineageOS..."
        FILE_SIZE=$(stat -c %s "$ROM_ZIP")
        FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
        BUILD_DATETIME=$(date +%s)
        GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
        JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

        jq -n \
          --arg dt "$BUILD_DATETIME" \
          --arg fn "$FILE_NAME" \
          --arg id "$FILE_HASH" \
          --arg rt "UNOFFICIAL" \
          --arg sz "$FILE_SIZE" \
          --arg url "$GH_DOWNLOAD_URL" \
          --arg ver "$ROM_VERSION" \
          '{
            response: [
              {
                datetime: ($dt | tonumber),
                filename: $fn,
                id: $id,
                romtype: $rt,
                size: ($sz | tonumber),
                url: $url,
                version: $ver
              }
            ]
          }' > "$JSON_FILE"

        echo "✅ Created $JSON_FILE"
        FILES_TO_UPLOAD+=("$JSON_FILE")
        ;;

    2)
        # 🔵 YAAP Offset Payload Structure
        echo "Generating payload-nested stone.json for YAAP..."
        BUILD_DATETIME=$(date +%s)
        JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

        # Extract payload properties from inside the zip safely without unpacking the whole ROM
        EXTRACT_DIR=$(mktemp -d)
        unzip -p "$ROM_ZIP" payload_properties.txt > "$EXTRACT_DIR/prop.txt" || true

        if [ -s "$EXTRACT_DIR/prop.txt" ]; then
            # Parse properties out of the text file
            OFFSET=$(grep "FILE_OFFSET=" "$EXTRACT_DIR/prop.txt" | cut -d= -f2)
            F_HASH=$(grep "FILE_HASH=" "$EXTRACT_DIR/prop.txt" | cut -d= -f2)
            F_SIZE=$(grep "FILE_SIZE=" "$EXTRACT_DIR/prop.txt" | cut -d= -f2)
            M_HASH=$(grep "METADATA_HASH=" "$EXTRACT_DIR/prop.txt" | cut -d= -f2)
            M_SIZE=$(grep "METADATA_SIZE=" "$EXTRACT_DIR/prop.txt" | cut -d= -f2)

            jq -n \
              --arg dt "$BUILD_DATETIME" \
              --arg fn "$FILE_NAME" \
              --arg off "$OFFSET" \
              --arg fh "$F_HASH" \
              --arg fs "$F_SIZE" \
              --arg mh "$M_HASH" \
              --arg ms "$M_SIZE" \
              '{
                response: [
                  {
                    datetime: ($dt | tonumber),
                    filename: $fn,
                    payload: [
                      {
                        offset: ($off | tonumber),
                        FILE_HASH: $fh,
                        FILE_SIZE: $fs,
                        METADATA_HASH: $mh,
                        METADATA_SIZE: $ms
                      }
                    ]
                  }
                ]
              }' > "$JSON_FILE"

            echo "✅ Created YAAP structure $(basename "$JSON_FILE")"
            FILES_TO_UPLOAD+=("$JSON_FILE")
        else
            echo "⚠️ Warning: payload_properties.txt not found inside zip. Skipping YAAP JSON generation."
        fi
        rm -rf "$EXTRACT_DIR"
        ;;

    3)
        # 🟡 Infinity-X Autogenerated Structure
        echo "Locating autogenerated JSON for Infinity-X..."
        AUTO_JSON="${ROM_ZIP%.zip}.json"

        if [ -f "$AUTO_JSON" ]; then
            echo "✅ Found autogenerated JSON: $(basename "$AUTO_JSON")"
            FILES_TO_UPLOAD+=("$AUTO_JSON")
        else
            echo "⚠️ Warning: Expected Infinity-X JSON at $(basename "$AUTO_JSON") but it was not found."
        fi
        ;;

    4)
        # 🟣 Project Matrixx Pre-built Structure
        echo "Locating pre-built OTA JSON for Project Matrixx..."
        JSON_FILE="vendor/MatrixxOTA/${DEVICE}.json"

        if [ -f "$JSON_FILE" ]; then
            echo "✅ Found Matrixx OTA JSON: $JSON_FILE"
            FILES_TO_UPLOAD+=("$JSON_FILE")
        else
            echo "⚠️ Warning: Expected Matrixx JSON at $JSON_FILE but it was not found."
        fi
        ;;
esac

# ==========================================
# Append essential partition images
# ==========================================
for IMG in boot.img dtb.img dtbo.img vendor_boot.img; do
    if [ -f "${TARGET_DIR}/$IMG" ]; then
        FILES_TO_UPLOAD+=("${TARGET_DIR}/$IMG")
        echo "✅ Found Image: $IMG"
    else
        echo "⚠️ Warning: $IMG not found. Skipping."
    fi
done

echo "------------------------------------------"
SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')

if [ -n "$SERVER" ] && [ "$SERVER" != "null" ]; then
    echo "☁️ Uploading to Server: $SERVER"
    echo "------------------------------------------"

    MASTER_LINK=""
    GUEST_TOKEN=""
    FOLDER_ID=""

    for FILE_PATH in "${FILES_TO_UPLOAD[@]}"; do
        FILE_NAME=$(basename "$FILE_PATH")
        echo "⬆️ Uploading $FILE_NAME..."

        if [ -n "$GUEST_TOKEN" ] && [ -n "$FOLDER_ID" ]; then
            UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                -F "token=$GUEST_TOKEN" \
                -F "folderId=$FOLDER_ID" \
                -F "file=@${FILE_PATH}" \
                "https://${SERVER}.gofile.io/contents/uploadfile")
        else
            UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                -F "file=@${FILE_PATH}" \
                "https://${SERVER}.gofile.io/contents/uploadfile")
        fi

        STATUS=$(echo "$UPLOAD_RES" | jq -r '.status')

        if [ "$STATUS" == "ok" ]; then
            echo "✅ Uploaded!"

            if [ -z "$GUEST_TOKEN" ]; then
                MASTER_LINK=$(echo "$UPLOAD_RES" | jq -r '.data.downloadPage')
                GUEST_TOKEN=$(echo "$UPLOAD_RES" | jq -r '.data.guestToken')
                FOLDER_ID=$(echo "$UPLOAD_RES" | jq -r '.data.parentFolder')
                echo "📁 Folder created! Grouping remaining files here..."
            fi
        else
            # Trigger error trap if upload fails
            echo "❌ Failed to upload $FILE_NAME"
            exit 1
        fi
        echo "------------------------------------------"
    done

    echo "🎉 Main uploads complete for $ROM_NAME!"
    echo "🔗 Master Link: $MASTER_LINK"

    # ==========================================
    # 📦 SECONDARY UPLOAD (Matrixx ZIP ONLY)
    # ==========================================
    SECONDARY_LINK=""
    if [ "$ROM_CHOICE" == "4" ]; then
        echo "=========================================="
        echo "☁️ Performing secondary upload for Matrixx ROM zip only..."
        FILE_NAME=$(basename "$ROM_ZIP")
        echo "⬆️ Uploading standalone zip: $FILE_NAME..."

        # Upload without folder tokens so it gets its own standalone link
        UPLOAD_RES_2=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
            -F "file=@${ROM_ZIP}" \
            "https://${SERVER}.gofile.io/contents/uploadfile")

        STATUS_2=$(echo "$UPLOAD_RES_2" | jq -r '.status')

        if [ "$STATUS_2" == "ok" ]; then
            echo "✅ Secondary Upload Successful!"
            SECONDARY_LINK=$(echo "$UPLOAD_RES_2" | jq -r '.data.downloadPage')
            echo "🔗 Secondary Link (Zip Only): $SECONDARY_LINK"
        else
            echo "❌ Secondary upload failed!"
            exit 1
        fi
    fi

    # ==========================================
    # 🚀 SEND SUCCESS NOTIFICATION
    # ==========================================
    if [ -n "$MASTER_LINK" ]; then
        echo "📱 Sending 'Build Success' notification..."

        # If secondary link exists (Matrixx), format message with both links
        if [ -n "$SECONDARY_LINK" ]; then
            SUCCESS_MSG="🚀 <b>Build Finished!</b>%0A📱 <b>Device:</b> ${DEVICE}%0A💿 <b>ROM:</b> ${ROM_NAME}%0A⏱️ <b>Time:</b> ${BUILD_MINUTES} minutes%0A📁 <a href=\"${MASTER_LINK}\">Download Folder (All Files)</a>%0A📦 <a href=\"${SECONDARY_LINK}\">Download ROM Zip Only</a>"
        else
            SUCCESS_MSG="🚀 <b>Build Finished!</b>%0A📱 <b>Device:</b> ${DEVICE}%0A💿 <b>ROM:</b> ${ROM_NAME}%0A⏱️ <b>Time:</b> ${BUILD_MINUTES} minutes%0A🔗 <a href=\"${MASTER_LINK}\">Download on Gofile</a>"
        fi

        send_tg_msg "$SUCCESS_MSG"
        echo "✅ Notification sent!"
    fi

else
    echo "❌ Failed to fetch a Gofile server. API might be down."
    exit 1
fi
echo "=========================================="
