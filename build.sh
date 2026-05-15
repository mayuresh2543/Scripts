#!/bin/bash

# ==========================================
# ⚙️ Global Configuration
# ==========================================
DEVICE="spes"
START_TIME=$(date +%s)

# 📱 Telegram Notification Setup
TELEGRAM_TOKEN="8801527482:AAGiuNQtKJka2bbOxeZap25PDsgYEoK77AQ"
TELEGRAM_CHAT_ID="-1003914151464"
# ==========================================

# Strict Execution: Abort on any failure
# (-E and pipefail added to ensure Crave pipes trigger the trap correctly)
set -eE
set -o pipefail

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
    trap - ERR # Disable trap to prevent infinite loops
    set +eE    # 🛑 CRITICAL: Turn off strict mode inside the handler
    set +o pipefail # 🛑 Turn off pipefail so network errors don't kill the handler
    local FAILED_LINE="$1"
    echo "❌ CRITICAL: Build failed on line $FAILED_LINE!"

    local LOG_LINK=""
    
    # Try to upload the log file if it exists
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        echo "☁️ Attempting to upload error log to Gofile..."
        
        # Ensure jq is installed
        if ! command -v jq &> /dev/null; then
            sudo apt-get install -y jq > /dev/null 2>&1 || true
        fi
        
        if command -v jq &> /dev/null; then
            local SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name')
            if [ -n "$SERVER" ] && [ "$SERVER" != "null" ]; then
                local UPLOAD_RES=$(curl -s -F "file=@${LOG_FILE}" "https://${SERVER}.gofile.io/contents/uploadfile")
                local STATUS=$(echo "$UPLOAD_RES" | jq -r '.status')
                if [ "$STATUS" == "ok" ]; then
                    LOG_LINK=$(echo "$UPLOAD_RES" | jq -r '.data.downloadPage')
                    echo "✅ Error log uploaded successfully!"
                fi
            fi
        fi
    fi

    local END_TIME=$(date +%s)
    local ELAPSED_MINUTES=$(((END_TIME - START_TIME) / 60))
    local DISPLAY_ROM="${ROM_NAME:-Unknown}"
    
    local FAIL_MSG="BUILD FAILED ❌%0A├─ 📱 <b>Device:</b> ${DEVICE}%0A├─ 💿 <b>ROM:</b> ${DISPLAY_ROM}%0A├─ ⏱️ <b>Time:</b> ${ELAPSED_MINUTES}m%0A├─ ⚠️ <b>Error:</b> Line ${FAILED_LINE}"
    
    if [ -n "$LOG_LINK" ]; then
        FAIL_MSG="${FAIL_MSG}%0A└─ 📄 <a href=\"${LOG_LINK}\">View Crash Log</a>"
    else
        FAIL_MSG="${FAIL_MSG}%0A└─ 💻 Check Crave Logs"
    fi

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
        ROM_NAME="LineageOS 20"
        ROM_VERSION="20.0"
        GH_REPO="mayuresh-releases/LineageOS_spes"

        REPO_INIT_URL="https://github.com/LineageOS/android.git"
        REPO_INIT_BRANCH="lineage-20.0"

        USE_LOCAL_MANIFEST="true"
        LOCAL_MANIFEST_BRANCH="spes-13"

        BUILD_TARGET="lineage_spes-userdebug"
        BUILD_COMMAND="m bacon"

        # Specific files to remove to avoid conflicts
        MANUAL_REMOVALS=(
            "hardware/google/pixel/kernel_headers/Android.bp"
            "hardware/lineage/compat/Android.bp"
        )

        # Repos to sync in parallel from your specific organization
        CUSTOM_REPOS=(
            "packages/apps/Updater|lineage_packages_apps_Updater"
            "build|lineage_android_build"
        )

        # Emptied because the local manifest handles these now!
        MANUAL_GIT_CLONES=()
        ;;

    *)
        echo "❌ Invalid ROM choice! Please use a valid number."
        handle_error $LINENO
        ;;
esac

echo "✅ Selected ROM: $ROM_NAME"

# ==========================================
# 🚀 SEND START NOTIFICATION
# ==========================================
echo "📱 Sending 'Build Started' notification..."
START_MSG="BUILD STARTED ⏳%0A├─ 📱 <b>Device:</b> ${DEVICE}%0A├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A└─ 💻 <b>Host:</b> Crave"
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

# 1.4 Execute Manual Removals
if [ ${#MANUAL_REMOVALS[@]} -gt 0 ]; then
    echo "=========================================="
    echo "🧹 Executing Manual Conflict Removals..."
    for rm_target in "${MANUAL_REMOVALS[@]}"; do
        echo "🗑️ Removing $rm_target..."
        rm -rf "$rm_target"
    done
fi

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
    BASE_URL="https://github.com/mayuresh-spes-sources"

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
echo "=========================================="
echo "⚙️ Sourcing Environment..."

set +eE   # 🛑 Turn OFF strict mode

source build/envsetup.sh
lunch "$BUILD_TARGET"

set -eE   # 🟢 Turn strict mode back ON for the actual compilation

echo "✅ Environment sourced."

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
    handle_error $LINENO
fi

# ==========================================
# 📝 OTA JSON Metadata Generation / Handling
# ==========================================
echo "=========================================="
echo "📝 Processing OTA JSON Metadata..."

FILE_NAME=$(basename "$ROM_ZIP")
REL_TAG=$(date +%y%m%d)
JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

case $ROM_CHOICE in
    1)
        # 🟢 LineageOS Standard Structure
        echo "Generating standard spes.json for LineageOS..."
        FILE_SIZE=$(stat -c %s "$ROM_ZIP")
        FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
        BUILD_DATETIME=$(date +%s)
        GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"

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

    *)
        echo "⏭️ No JSON generation rule defined for ROM Choice $ROM_CHOICE. Skipping."
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
            handle_error $LINENO
        fi
        echo "------------------------------------------"
    done

    echo "🎉 Main uploads complete for $ROM_NAME!"
    echo "🔗 Master Link: $MASTER_LINK"

    # ==========================================
    # 🚀 SEND SUCCESS NOTIFICATION
    # ==========================================
    if [ -n "$MASTER_LINK" ]; then
        echo "📱 Sending 'Build Success' notification..."
        SUCCESS_MSG="BUILD SUCCESSFUL 🚀%0A├─ 📱 <b>Device:</b> ${DEVICE}%0A├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A├─ ⏱️ <b>Time:</b> ${BUILD_MINUTES}m%0A└─ 🔗 <a href=\"${MASTER_LINK}\">Download on Gofile</a>"

        send_tg_msg "$SUCCESS_MSG"
        echo "✅ Notification sent!"
    fi

else
    echo "❌ Failed to fetch a Gofile server. API might be down."
    handle_error $LINENO
fi
echo "=========================================="
