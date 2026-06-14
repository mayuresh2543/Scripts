#!/bin/bash

# ==========================================
# ⚙️ Global Configuration
# ==========================================
DEVICE=${1:-"stone"}
ROM_CHOICE=${2:-1}
START_TIME=$(date +%s)
LOG_FILE="build_${DEVICE}_$(date +%Y%m%d_%H%M).log"
rm -f "/tmp/build_failed.lock"

# ==========================================
# 📝 Setup Full-Script Logging
# ==========================================
# Save original stdout/stderr to fd 3 and 4
exec 3>&1 4>&2
# Redirect all subsequent output to our log file via tee
exec 1> >(tee -a "$LOG_FILE") 2>&1

# 📱 Telegram Notification Setup
TELEGRAM_TOKEN="8801527482:AAGiuNQtKJka2bbOxeZap25PDsgYEoK77AQ"
TELEGRAM_CHAT_ID="-1003914151464"
# ==========================================

# Strict Execution: Abort on any failure
# (-E and pipefail added to ensure Crave pipes trigger the trap correctly)
set -eE
set -o pipefail

# ==========================================
# 📨 Core Helper Functions & Error Trap
# ==========================================
send_tg_msg() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=${MESSAGE}" > /dev/null
}

handle_error() {
    trap - ERR # Disable trap to prevent infinite loops
    set +eE    # 🛑 CRITICAL: Turn off strict mode inside the handler
    set +o pipefail # 🛑 Turn off pipefail so network errors don't kill the handler
    local FAILED_LINE="$1"

    # Restore standard output/error to safely terminate the background logger
    exec 1>&3 2>&4
    sleep 1 # Ensure tee finishes writing buffers to disk

    # Prevent duplicate error notifications from subshell inheritance
    if [ -f "/tmp/build_failed.lock" ]; then
        exit 1
    fi
    touch "/tmp/build_failed.lock"

    echo "❌ CRITICAL: Build failed on line $FAILED_LINE!"

    local LOG_LINK=""
    
    # Try to upload the log file if it exists
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        if command -v gzip &> /dev/null; then
            echo "🗜️ Compressing crash log..."
            gzip -9 "$LOG_FILE"
            LOG_FILE="${LOG_FILE}.gz"
        fi
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
    local ELAPSED_HOURS=$((ELAPSED_MINUTES / 60))
    local REM_MINUTES=$((ELAPSED_MINUTES % 60))
    
    local DISPLAY_TIME="${ELAPSED_MINUTES}m"
    if [ "$ELAPSED_HOURS" -gt 0 ]; then
        DISPLAY_TIME="${ELAPSED_HOURS}h ${REM_MINUTES}m"
    fi

    local DISPLAY_ROM="${ROM_NAME:-Unknown}"
    
    local FAIL_MSG="BUILD FAILED ❌%0A"
    FAIL_MSG+="├─ 📱 <b>Device:</b> ${DEVICE}%0A"
    FAIL_MSG+="├─ 💿 <b>ROM:</b> ${DISPLAY_ROM}%0A"
    FAIL_MSG+="├─ ⏱️ <b>Time:</b> ${DISPLAY_TIME}%0A"
    FAIL_MSG+="├─ ⚠️ <b>Error:</b> Line ${FAILED_LINE}"
    
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
# 🔀 The Switchboard (Define your ROMs here)
# ==========================================
echo "=========================================="
echo "🔍 Analyzing Build Request..."
echo "=========================================="

NEEDS_STANDALONE_ZIP="false"
MANUAL_REMOVALS=()
MANUAL_GIT_CLONES=()
CUSTOM_REPOS=()

case "$DEVICE" in
    "stone")
        case "$ROM_CHOICE" in
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

                MANUAL_GIT_CLONES=(
                    "https://github.com/Infinity-X-Devices/device_xiaomi_stone.git device/xiaomi/stone"
                    "https://github.com/Infinity-X-Devices/vendor_xiaomi_stone.git vendor/xiaomi/stone"
                    "https://github.com/Infinity-X-Devices/kernel_xiaomi_stone.git kernel/xiaomi/stone"
                    "https://github.com/mayuresh-sources/hardware_dolby.git -b sony-1.0 hardware/dolby"
                    "https://github.com/LineageOS/android_hardware_xiaomi.git -b lineage-23.2 hardware/xiaomi"
                    "https://github.com/mayuresh-sources/packages_apps_ViPER4AndroidFX.git packages/apps/ViPER4AndroidFX"
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

                NEEDS_STANDALONE_ZIP="true"
                ;;

            *)
                echo "❌ Invalid ROM choice for stone!"
                handle_error $LINENO
                ;;
        esac
        ;;

    "spes")
        case "$ROM_CHOICE" in
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

                MANUAL_REMOVALS=(
                    "hardware/google/pixel/kernel_headers/Android.bp"
                    "hardware/lineage/compat/Android.bp"
                )

                CUSTOM_REPOS=(
                    "packages/apps/Updater|lineage_packages_apps_Updater"
                    "build/make|lineage_android_build"
                )
                ;;

            *)
                echo "❌ Invalid ROM choice for spes! (Only LineageOS is supported)"
                handle_error $LINENO
                ;;
        esac
        ;;

    *)
        echo "❌ Invalid Device! Use 'stone' or 'spes'."
        handle_error $LINENO
        ;;
esac

echo "✅ Selected Device: $DEVICE"
echo "✅ Selected ROM: $ROM_NAME"

# ==========================================
# 🛠️ Modular Execution Functions
# ==========================================

send_start_notification() {
    echo "📱 Sending 'Build Started' notification..."
    START_MSG="BUILD STARTED ⏳%0A"
    START_MSG+="├─ 📱 <b>Device:</b> ${DEVICE}%0A"
    START_MSG+="├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A"
    START_MSG+="└─ 💻 <b>Host:</b> Crave"
    send_tg_msg "$START_MSG"
}

sync_repositories() {
    echo "=========================================="
    echo "🚀 Starting Build Environment Setup"
    echo "=========================================="

    # 1. Cleanup & Base Sync
    repo init -u "$REPO_INIT_URL" -b "$REPO_INIT_BRANCH" --git-lfs --depth=1

    # Handle Local Manifests based on ROM choice
    rm -rf .repo/local_manifests/
    if [ "$USE_LOCAL_MANIFEST" == "true" ]; then
        echo "📄 Cloning local manifests..."
        git clone --depth=1 -b "$LOCAL_MANIFEST_BRANCH" https://github.com/Mayuresh2543/local_manifests.git .repo/local_manifests
    else
        echo "⏭️ Skipping local manifests (Not supported by $ROM_NAME)."
    fi

    if [ -f /opt/crave/resync.sh ]; then
        echo "🚀 Running Crave resync..."
        /opt/crave/resync.sh
    else
        echo "🚀 Running standard repo sync..."
        repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
    fi

    # 1.4 Execute Manual Removals (If any are defined)
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
        echo "⬇️ Executing Manual Git Clones in parallel..."
        for clone_args in "${MANUAL_GIT_CLONES[@]}"; do
            TARGET_DIR=$(echo "$clone_args" | awk '{print $NF}')
            echo "🗑️ Removing $TARGET_DIR to prepare for clean clone..."
            rm -rf "$TARGET_DIR"
            
            # Execute unquoted clone_args to allow bash word splitting for URL, -b branch, and TARGET
            git clone --depth=1 $clone_args &
        done
        wait # Wait for all manual clones to finish
    fi

    # 2. Parallel Custom Source Sync
    if [ ${#CUSTOM_REPOS[@]} -gt 0 ]; then
        echo "=========================================="
        echo "Syncing custom repositories in parallel for $ROM_NAME..."
        
        if [ "$DEVICE" == "spes" ]; then
            BASE_URL="https://github.com/mayuresh-spes-sources"
        else
            BASE_URL="https://github.com/mayuresh-sources"
        fi

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

    # 3. Post-Sync Fixes for Android 13 (spes only)
    if [ "$DEVICE" == "spes" ]; then
        echo "🔧 Fixing unrecognized Soong properties for Android 13..."
        find packages/apps/ViPER4AndroidFX vendor/bcr -name "Android.bp" -exec sed -i '/preprocessed:/d' {} + 2>/dev/null || true
    fi
}

compile_rom() {
    # 3. Environment Variables
    export BUILD_USERNAME=mayuresh
    export BUILD_HOSTNAME=crave
    export TZ="Asia/Kolkata"

    # 📦 Install legacy Ncurses via apt as requested (spes only)
    if [ "$DEVICE" == "spes" ]; then
        if ! dpkg -s libncurses5 &> /dev/null; then
            echo "📦 Installing legacy libncurses5 dependencies via sudo..."
            sudo apt-get update -y
            sudo apt-get install -y libncurses5 libtinfo5 || true
        fi
        
        # 🔧 Fallback to System Symlink Hack if apt failed (Ubuntu 24.04 dropped it)
        if ! dpkg -s libncurses5 &> /dev/null; then
            echo "🔧 apt failed (likely Ubuntu 24.04). Applying ncurses6 system symlink hack..."
            NCURSES_LIB=$(find /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib /lib -maxdepth 2 -name "libncurses.so.6*" -print -quit 2>/dev/null)
            TINFO_LIB=$(find /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib /lib -maxdepth 2 -name "libtinfo.so.6*" -print -quit 2>/dev/null)
            
            if [ -n "$NCURSES_LIB" ]; then
                NCURSES_DIR=$(dirname "$NCURSES_LIB")
                sudo ln -sf "$NCURSES_LIB" "$NCURSES_DIR/libncurses.so.5"
            fi
            if [ -n "$TINFO_LIB" ]; then
                TINFO_DIR=$(dirname "$TINFO_LIB")
                sudo ln -sf "$TINFO_LIB" "$TINFO_DIR/libtinfo.so.5"
            fi
            sudo ldconfig || true
        fi
    fi

    # 4. Setup & Lunch
    set +eE   # 🛑 Turn OFF strict mode
    if [ "$DEVICE" == "spes" ]; then
        . build/envsetup.sh
    else
        source build/envsetup.sh
    fi
    lunch "$BUILD_TARGET"
    set -eE   # 🟢 Turn strict mode back ON for the actual compilation

    # 5. Prep the output directory
    echo "Cleaning output directory..."
    m installclean

    # 6. Compilation with Logging
    echo "=========================================="
    echo "🔨 Starting compilation for $ROM_NAME..."
    echo "🚀 Initiating Build for $BUILD_TARGET..."
    echo "=========================================="

    # Dynamically run whatever command the ROM needs
    $BUILD_COMMAND

    # Calculate precise time taken
    END_TIME=$(date +%s)
    BUILD_MINUTES=$(((END_TIME - START_TIME) / 60))
    BUILD_HOURS=$((BUILD_MINUTES / 60))
    REMAINING_MINUTES=$((BUILD_MINUTES % 60))

    DISPLAY_TIME="${BUILD_MINUTES}m"
    if [ "$BUILD_HOURS" -gt 0 ]; then
        DISPLAY_TIME="${BUILD_HOURS}h ${REMAINING_MINUTES}m"
    fi

    echo "⏱️ Build finished in $DISPLAY_TIME."
}

process_artifacts() {
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
    ROM_ZIP=$(ls -t ${TARGET_DIR}/*${DEVICE}*.zip 2>/dev/null | head -n 1 || true)
    FILES_TO_UPLOAD=()

    if [ -z "$ROM_ZIP" ] || [ ! -f "$ROM_ZIP" ]; then
        echo "❌ ROM zip not found in ${TARGET_DIR}."
        handle_error $LINENO
    fi

    FILES_TO_UPLOAD+=("$ROM_ZIP")
    echo "✅ Found ROM: $(basename "$ROM_ZIP")"

    # ==========================================
    # 📝 OTA JSON Metadata Generation / Handling
    # ==========================================
    echo "=========================================="
    echo "📝 Processing OTA JSON Metadata..."

    FILE_NAME=$(basename "$ROM_ZIP")
    REL_TAG=$(date +%y%m%d)

    # 🕒 Extract precise build datetime from ROM metadata
    EXTRACT_DIR=$(mktemp -d)
    unzip -p "$ROM_ZIP" META-INF/com/android/metadata > "$EXTRACT_DIR/metadata.txt" 2>/dev/null || true
    
    if grep -q "post-timestamp=" "$EXTRACT_DIR/metadata.txt" 2>/dev/null; then
        BUILD_DATETIME=$(grep "post-timestamp=" "$EXTRACT_DIR/metadata.txt" | cut -d= -f2 | tr -d '\r')
        echo "✅ Extracted precise build datetime from zip: $BUILD_DATETIME"
    else
        BUILD_DATETIME=$(date +%s)
        echo "⚠️ Warning: Could not extract precise datetime from zip, using current time: $BUILD_DATETIME"
    fi
    rm -rf "$EXTRACT_DIR"

    case $ROM_CHOICE in
        1)
            # 🟢 LineageOS Standard Structure
            echo "Generating standard ${DEVICE}.json for LineageOS..."
            FILE_SIZE=$(stat -c %s "$ROM_ZIP")
            FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
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
            echo "Generating payload-nested ${DEVICE}.json for YAAP..."
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
            # Infinity-X natively appends .json directly to the full zip filename (e.g., rom.zip.json)
            AUTO_JSON="${ROM_ZIP}.json"

            if [ -n "$AUTO_JSON" ] && [ -f "$AUTO_JSON" ]; then
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
}

upload_and_notify() {
    echo "------------------------------------------"
    SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name' || true)

    if [ -z "$SERVER" ] || [ "$SERVER" == "null" ]; then
        echo "❌ Failed to fetch a Gofile server. API might be down."
        handle_error $LINENO
    fi

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
                "https://${SERVER}.gofile.io/contents/uploadfile" || true)
        else
            UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                -F "file=@${FILE_PATH}" \
                "https://${SERVER}.gofile.io/contents/uploadfile" || true)
        fi

        STATUS=$(echo "$UPLOAD_RES" | jq -r '.status' || true)

        if [ "$STATUS" == "ok" ]; then
            echo "✅ Uploaded!"

            if [ -z "$GUEST_TOKEN" ]; then
                MASTER_LINK=$(echo "$UPLOAD_RES" | jq -r '.data.downloadPage' || true)
                GUEST_TOKEN=$(echo "$UPLOAD_RES" | jq -r '.data.guestToken' || true)
                FOLDER_ID=$(echo "$UPLOAD_RES" | jq -r '.data.parentFolder' || true)
                echo "📁 Folder created! Grouping remaining files here..."
            fi
        else
            echo "❌ Failed to upload $FILE_NAME"
            handle_error $LINENO
        fi
        echo "------------------------------------------"
    done

    echo "🎉 Main uploads complete for $ROM_NAME!"
    echo "🔗 Master Link: $MASTER_LINK"

    # ==========================================
    # 📦 SECONDARY UPLOAD (Standalone ZIP ONLY)
    # ==========================================
    SECONDARY_LINK=""
    if [ "$NEEDS_STANDALONE_ZIP" == "true" ]; then
        echo "=========================================="
        echo "☁️ Performing secondary upload for standalone ROM zip only..."
        FILE_NAME=$(basename "$ROM_ZIP")
        echo "⬆️ Uploading standalone zip: $FILE_NAME..."

        # Upload without folder tokens so it gets its own standalone link
        UPLOAD_RES_2=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
            -F "file=@${ROM_ZIP}" \
            "https://${SERVER}.gofile.io/contents/uploadfile" || true)

        STATUS_2=$(echo "$UPLOAD_RES_2" | jq -r '.status' || true)

        if [ "$STATUS_2" == "ok" ]; then
            echo "✅ Secondary Upload Successful!"
            SECONDARY_LINK=$(echo "$UPLOAD_RES_2" | jq -r '.data.downloadPage' || true)
            echo "🔗 Secondary Link (Zip Only): $SECONDARY_LINK"
        else
            echo "❌ Secondary upload failed!"
            handle_error $LINENO
        fi
    fi

    # ==========================================
    # 🚀 SEND SUCCESS NOTIFICATION
    # ==========================================
    if [ -n "$MASTER_LINK" ]; then
        echo "📱 Sending 'Build Success' notification..."

        # If secondary link exists (Matrixx), format message with both links
        if [ -n "$SECONDARY_LINK" ]; then
            SUCCESS_MSG="BUILD SUCCESSFUL 🚀%0A"
            SUCCESS_MSG+="├─ 📱 <b>Device:</b> ${DEVICE}%0A"
            SUCCESS_MSG+="├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A"
            SUCCESS_MSG+="├─ ⏱️ <b>Time:</b> ${DISPLAY_TIME}%0A"
            SUCCESS_MSG+="├─ 📁 <a href=\"${MASTER_LINK}\">Download Folder (All Files)</a>%0A"
            SUCCESS_MSG+="└─ 📦 <a href=\"${SECONDARY_LINK}\">Download ROM Zip Only</a>"
        else
            SUCCESS_MSG="BUILD SUCCESSFUL 🚀%0A"
            SUCCESS_MSG+="├─ 📱 <b>Device:</b> ${DEVICE}%0A"
            SUCCESS_MSG+="├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A"
            SUCCESS_MSG+="├─ ⏱️ <b>Time:</b> ${DISPLAY_TIME}%0A"
            SUCCESS_MSG+="└─ 🔗 <a href=\"${MASTER_LINK}\">Download on Gofile</a>"
        fi

        send_tg_msg "$SUCCESS_MSG"
        echo "✅ Notification sent!"
    fi
    echo "=========================================="
}

# ==========================================
# 🚀 MAIN EXECUTION PIPELINE
# ==========================================
send_start_notification
sync_repositories
compile_rom
process_artifacts

# ==========================================
# 🗜️ Finalize Logs & Upload
# ==========================================
# Restore original stdout/stderr (this gracefully terminates the background tee logger)
exec 1>&3 2>&4
sleep 1 # Flush buffers

if [ -f "$LOG_FILE" ] && command -v gzip &> /dev/null; then
    echo "=========================================="
    echo "🗜️ Compressing full execution log..."
    gzip -9 "$LOG_FILE"
    LOG_FILE="${LOG_FILE}.gz"
fi

# Append the compressed log file to the upload payload
FILES_TO_UPLOAD+=("$LOG_FILE")

upload_and_notify
