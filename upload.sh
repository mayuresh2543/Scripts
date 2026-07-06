#!/bin/bash

DEVICE=${1:-"stone"}
ROM_CHOICE=${2:-1}

if [ -d "/opt/crave" ]; then
    export BUILD_HOSTNAME="crave"
else
    export BUILD_HOSTNAME=$(hostname)
fi

TELEGRAM_TOKEN="8801527482:AAF5qe0lz8eeJrpNVihctDcdaVox8dnJdjg"
TELEGRAM_CHAT_ID="-1003914151464"

send_tg_msg() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=${MESSAGE}" > /dev/null
}

handle_error() {
    echo "❌ Upload failed on line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

case "$DEVICE" in
    "stone")
        case "$ROM_CHOICE" in
            1)
                ROM_NAME="LineageOS 23.2"
                ANDROID_VERSION="16-QPR2"
                ROM_VERSION="23.2"
                GH_REPO="mayuresh-releases/LineageOS_stone"
                REPO_INIT_BRANCH="lineage-23.2"
                ;;

            2)
                ROM_NAME="YAAP 16.2"
                ANDROID_VERSION="16-QPR2"
                GH_REPO="mayuresh-releases/YAAP_stone"
                REPO_INIT_BRANCH="sixteen"
                ;;

            3)
                ROM_NAME="Infinity-X"
                ANDROID_VERSION="16-QPR2"
                GH_REPO="mayuresh-releases/Infinity-X_stone"
                REPO_INIT_BRANCH="16"
                ;;

            4)
                ROM_NAME="LineageOS 24.0"
                ANDROID_VERSION="17"
                ROM_VERSION="24.0"
                GH_REPO="mayuresh-releases/LineageOS_stone"
                REPO_INIT_BRANCH="lineage-24.0"
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
                ANDROID_VERSION="13"
                ROM_VERSION="20.0"
                GH_REPO="mayuresh-releases/LineageOS_spes"
                REPO_INIT_BRANCH="lineage-20.0"
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
echo "✅ Android Version: ${ANDROID_VERSION:-Unknown}"

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
        1|4)
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
              '[
                {
                  datetime: ($dt | tonumber),
                  type: $rt,
                  version: $ver,
                  files: [
                    {
                      filename: $fn,
                      sha256: $id,
                      size: ($sz | tonumber),
                      url: $url
                    }
                  ]
                }
              ]' > "$JSON_FILE"

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

    # ==========================================
    # Generate Changelog from Gerrit
    # ==========================================
    if [[ "$ROM_NAME" == *"LineageOS"* ]] && { [ "$DEVICE" == "stone" ] || [ "$DEVICE" == "spes" ]; }; then
        echo "=========================================="
        echo "📝 Generating Changelog from LineageOS Gerrit..."
        local branch="$REPO_INIT_BRANCH"
        if [ -z "$branch" ]; then
            branch="lineage-23.2"
        fi

        echo "# LineageOS Changelog (${branch})" > source_changelog.txt
        echo "Generated on $(date)" >> source_changelog.txt
        echo "" >> source_changelog.txt
        
        if curl -s -G "https://review.lineageos.org/changes/" --data-urlencode "q=status:merged branch:${branch} -project:^.*_device_.* -project:^.*_kernel_.*" -d "n=200" | sed '1d' | jq -r 'group_by(.project) | sort_by(.[0].submitted // .[0].updated // "") | reverse | .[] | "### " + .[0].project + "\n" + (map("- [" + ((.submitted // .updated // "Unknown") | .[0:10]) + "] " + .subject) | join("\n")) + "\n"' >> source_changelog.txt; then
            if [ -s source_changelog.txt ]; then
                echo "✅ Changelog saved to source_changelog.txt"
                FILES_TO_UPLOAD+=("source_changelog.txt")
            else
                echo "⚠️ Gerrit API returned empty or failed to parse."
            fi
        else
            echo "⚠️ Failed to fetch changelog from Gerrit."
        fi
    else
        echo "ℹ️ Skipping Changelog generation (Not LineageOS on stone/spes)"
    fi
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
    # 🚀 SEND SUCCESS NOTIFICATION
    # ==========================================
    if [ -n "$MASTER_LINK" ]; then
        echo "📱 Sending 'Build Success' notification..."

        SUCCESS_MSG="UPLOAD SUCCESSFUL 🚀%0A"
        SUCCESS_MSG+="├─ 📱 <b>Device:</b> ${DEVICE}%0A"
        SUCCESS_MSG+="├─ 💿 <b>ROM:</b> ${ROM_NAME}%0A"
        SUCCESS_MSG+="├─ 🤖 <b>Android:</b> ${ANDROID_VERSION}%0A"
        SUCCESS_MSG+="├─ 💻 <b>Host:</b> ${BUILD_HOSTNAME}%0A"
        SUCCESS_MSG+="├─ ⏱️ <b>Time:</b> ${DISPLAY_TIME}%0A"

        if [ -s source_changelog.txt ]; then
            CHANGELOG_URL=""
            
            # Upload changelog to paste.rs for a raw text preview link (GitHub Raw style)
            RES=$(curl -s --max-time 10 --data-binary @source_changelog.txt https://paste.rs/ || true)
            if [[ "$RES" == http* ]]; then
                CHANGELOG_URL=$(echo -n "$RES" | tr -d '\n\r')
            fi

            if [ -n "$CHANGELOG_URL" ]; then
                SUCCESS_MSG+="├─ 📜 <b>Changelog:</b> <a href=\"${CHANGELOG_URL}\">View Latest Changes</a>%0A"
            fi
        fi

        SUCCESS_MSG+="└─ 🔗 <a href=\"${MASTER_LINK}\">Download on Gofile</a>"

        send_tg_msg "$SUCCESS_MSG"
        echo "✅ Notification sent!"
    fi
    echo "=========================================="
}

TARGET_DIR="out/target/product/${DEVICE}"
FILES_TO_UPLOAD=()
DISPLAY_TIME="Unknown (Standalone Upload)"
process_artifacts
upload_and_notify
echo "✅ Standalone Upload Completed!"
