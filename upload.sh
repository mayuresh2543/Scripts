#!/bin/bash

DEVICE=${1:-"stone"}
ROM_CHOICE=${2:-1}

if [ -d "/opt/crave" ]; then
    export BUILD_HOSTNAME="crave"
else
    export BUILD_HOSTNAME=$(hostname)
fi

# 📱 Telegram Notification Setup
TELEGRAM_TOKEN="8801527482:AAG76NnDPx5xo7rfT3JGXKmR774LDEQhsuI"
TELEGRAM_CHAT_ID="-1003914151464"

send_tg_msg() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=true" \
        -d "text=${MESSAGE}" > /dev/null
}

handle_error() {
    echo "❌ Upload failed on line $1"
    exit 1
}
trap 'handle_error $LINENO' ERR

case "$DEVICE" in
    "stone")
        DEVICE_NAME="Redmi Note 12 5G / Poco X5 5G (stone)"
        case "$ROM_CHOICE" in
            1)
                ROM_NAME="LineageOS 23.2"
                ANDROID_VERSION="16-QPR2"
                ROM_VERSION="23.2"
                GH_REPO="mayuresh-releases/LineageOS_stone"
                REPO_INIT_BRANCH="lineage-23.2"
                ;;

            2)
                ROM_NAME="LineageOS 22.2"
                ANDROID_VERSION="15"
                ROM_VERSION="22.2"
                GH_REPO="mayuresh-releases/LineageOS_stone"
                REPO_INIT_BRANCH="lineage-22.2"
                ;;

            3)
                ROM_NAME="YAAP 17"
                ANDROID_VERSION="17"
                GH_REPO="mayuresh-releases/YAAP_stone"
                REPO_INIT_BRANCH="seventeen"
                ;;

            4)
                ROM_NAME="Infinity-X"
                ANDROID_VERSION="16-QPR2"
                GH_REPO="mayuresh-releases/Infinity-X_stone"
                REPO_INIT_BRANCH="16"
                ;;

            5)
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
        DEVICE_NAME="Redmi Note 11 (spes)"
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

    # Compute checksums and size for Telegram notification
    ROM_SIZE_HUMAN=$(du -h "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    ROM_SHA256=$(sha256sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    ROM_MD5=$(md5sum "$ROM_ZIP" 2>/dev/null | awk '{print $1}' || echo "Unknown")

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
        1|5)
            # 🟢 LineageOS Standard Structure (23.2 & 24.0)
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
            # 🟢 LineageOS 22.2 Classic Response Structure
            echo "Generating classic response ${DEVICE}.json for LineageOS 22.2..."
            FILE_SIZE=$(stat -c %s "$ROM_ZIP")
            FILE_HASH=$(sha256sum "$ROM_ZIP" | awk '{print $1}')
            GH_DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${REL_TAG}/${FILE_NAME}"
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            jq -n \
              --arg dt "$BUILD_DATETIME" \
              --arg fn "$FILE_NAME" \
              --arg id "$FILE_HASH" \
              --arg rt "nightly" \
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

        3)
            # 🔵 YAAP Offset Payload Structure
            echo "Generating payload-nested ${DEVICE}.json for YAAP..."
            JSON_FILE="${TARGET_DIR}/${DEVICE}.json"

            python3 - <<EOF > "$JSON_FILE"
import zipfile, json

zip_path = "$ROM_ZIP"
filename = "$FILE_NAME"
datetime_val = int("$BUILD_DATETIME")

offset = 0
file_hash = ""
file_size = "0"
metadata_hash = ""
metadata_size = "0"

with zipfile.ZipFile(zip_path, 'r') as z:
    try:
        info = z.getinfo('payload.bin')
        offset = info.header_offset + 30 + len(info.filename) + len(info.extra)
    except KeyError:
        offset = 0

    try:
        with z.open('payload_properties.txt') as f:
            for line in f.read().decode('utf-8').splitlines():
                if '=' in line:
                    k, v = line.split('=', 1)
                    k = k.strip()
                    v = v.strip()
                    if k == 'FILE_HASH':
                        file_hash = v
                    elif k == 'FILE_SIZE':
                        file_size = v
                    elif k == 'METADATA_HASH':
                        metadata_hash = v
                    elif k == 'METADATA_SIZE':
                        metadata_size = v
    except KeyError:
        pass

data = {
    "response": [
        {
            "datetime": datetime_val,
            "filename": filename,
            "payload": [
                {
                    "offset": offset,
                    "FILE_HASH": file_hash,
                    "FILE_SIZE": file_size,
                    "METADATA_HASH": metadata_hash,
                    "METADATA_SIZE": metadata_size
                }
            ]
        }
    ]
}

print(json.dumps(data, indent=2))
EOF

            echo "✅ Created YAAP structure $(basename "$JSON_FILE")"
            FILES_TO_UPLOAD+=("$JSON_FILE")
            ;;

        4)
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
        
        if curl -s -G "https://review.lineageos.org/changes/" --data-urlencode "q=status:merged branch:${branch} -project:^.*_device_.* -project:^.*mainline.* (-project:^.*_kernel_.* OR project:^.*android_kernel_qcom_sm8350.*)" -d "n=200" | sed '1d' | jq -r 'group_by(.project) | sort_by(.[0].submitted // .[0].updated // "") | reverse | .[] | "### " + .[0].project + "\n" + (map("- [" + ((.submitted // .updated // "Unknown") | .[0:10]) + "] " + .subject) | join("\n")) + "\n"' >> source_changelog.txt; then
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
    SERVER=$(curl -s --connect-timeout 5 https://api.gofile.io/servers | jq -r '.data.servers[0].name' 2>/dev/null || true)
    USE_PIXELDRAIN=false
    PIXELDRAIN_API_KEY="89f5f646-bd8e-4210-826e-33f69930e0f7"

    if [ -z "$SERVER" ] || [ "$SERVER" == "null" ]; then
        echo "⚠️ Failed to fetch a Gofile server. API might be down. Falling back to Pixeldrain..."
        USE_PIXELDRAIN=true
    else
        echo "☁️ Uploading to Gofile Server: $SERVER"
    fi
    echo "------------------------------------------"

    MASTER_LINK=""
    GUEST_TOKEN=""
    FOLDER_ID=""
    UPLOADED_IDS=()

    if [ "$USE_PIXELDRAIN" == "true" ]; then
        echo "⚡ Uploading ${#FILES_TO_UPLOAD[@]} file(s) in parallel to Pixeldrain..."
        TMP_DIR=$(mktemp -d)

        for i in "${!FILES_TO_UPLOAD[@]}"; do
            (
                FILE_PATH="${FILES_TO_UPLOAD[$i]}"
                UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                    -u ":$PIXELDRAIN_API_KEY" \
                    -F "file=@${FILE_PATH}" \
                    "https://pixeldrain.com/api/file" || true)
                echo "$UPLOAD_RES" > "$TMP_DIR/res_$i.json"
            ) &
        done
        wait

        for i in "${!FILES_TO_UPLOAD[@]}"; do
            FILE_PATH="${FILES_TO_UPLOAD[$i]}"
            FILE_NAME=$(basename "$FILE_PATH")
            UPLOAD_RES=$(cat "$TMP_DIR/res_$i.json" 2>/dev/null || true)
            SUCCESS=$(echo "$UPLOAD_RES" | jq -r '.success' 2>/dev/null || true)

            if [ "$SUCCESS" == "true" ]; then
                FILE_ID=$(echo "$UPLOAD_RES" | jq -r '.id' 2>/dev/null || true)
                UPLOADED_IDS+=("$FILE_ID")
                echo "✅ Uploaded $FILE_NAME! ID: $FILE_ID"
            else
                echo "❌ Failed to upload $FILE_NAME to Pixeldrain"
                echo "Response: $UPLOAD_RES"
                rm -rf "$TMP_DIR"
                handle_error $LINENO
            fi
        done
        rm -rf "$TMP_DIR"

    else
        # Upload initial file to Gofile synchronously to establish folder & token
        FIRST_FILE="${FILES_TO_UPLOAD[0]}"
        FIRST_NAME=$(basename "$FIRST_FILE")
        echo "⬆️ Uploading $FIRST_NAME (initial file)..."

        UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
            -F "file=@${FIRST_FILE}" \
            "https://${SERVER}.gofile.io/contents/uploadfile" || true)

        STATUS=$(echo "$UPLOAD_RES" | jq -r '.status' 2>/dev/null || true)

        if [ "$STATUS" == "ok" ]; then
            echo "✅ Uploaded $FIRST_NAME!"
            MASTER_LINK=$(echo "$UPLOAD_RES" | jq -r '.data.downloadPage' 2>/dev/null || true)
            GUEST_TOKEN=$(echo "$UPLOAD_RES" | jq -r '.data.guestToken' 2>/dev/null || true)
            FOLDER_ID=$(echo "$UPLOAD_RES" | jq -r '.data.parentFolder' 2>/dev/null || true)
            echo "📁 Folder created! Grouping remaining files..."
        else
            echo "⚠️ Gofile upload failed for $FIRST_NAME. Switching to Pixeldrain fallback..."
            USE_PIXELDRAIN=true
        fi

        # Upload remaining files in parallel to Gofile
        if [ "$USE_PIXELDRAIN" == "false" ] && [ ${#FILES_TO_UPLOAD[@]} -gt 1 ]; then
            echo "⚡ Uploading remaining $((${#FILES_TO_UPLOAD[@]} - 1)) file(s) in parallel to Gofile..."
            TMP_DIR=$(mktemp -d)

            for i in $(seq 1 $((${#FILES_TO_UPLOAD[@]} - 1))); do
                (
                    FILE_PATH="${FILES_TO_UPLOAD[$i]}"
                    UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                        -F "token=$GUEST_TOKEN" \
                        -F "folderId=$FOLDER_ID" \
                        -F "file=@${FILE_PATH}" \
                        "https://${SERVER}.gofile.io/contents/uploadfile" || true)
                    echo "$UPLOAD_RES" > "$TMP_DIR/res_$i.json"
                ) &
            done
            wait

            for i in $(seq 1 $((${#FILES_TO_UPLOAD[@]} - 1))); do
                FILE_PATH="${FILES_TO_UPLOAD[$i]}"
                FILE_NAME=$(basename "$FILE_PATH")
                UPLOAD_RES=$(cat "$TMP_DIR/res_$i.json" 2>/dev/null || true)
                STATUS=$(echo "$UPLOAD_RES" | jq -r '.status' 2>/dev/null || true)

                if [ "$STATUS" == "ok" ]; then
                    echo "✅ Uploaded $FILE_NAME!"
                else
                    echo "⚠️ Gofile parallel upload failed for $FILE_NAME. Switching to Pixeldrain fallback..."
                    USE_PIXELDRAIN=true
                    break
                fi
            done
            rm -rf "$TMP_DIR"
        fi

        # If Gofile failed at any step, fallback to parallel Pixeldrain upload
        if [ "$USE_PIXELDRAIN" == "true" ]; then
            echo "⚡ Re-uploading all ${#FILES_TO_UPLOAD[@]} file(s) in parallel to Pixeldrain..."
            TMP_DIR=$(mktemp -d)
            UPLOADED_IDS=()

            for i in "${!FILES_TO_UPLOAD[@]}"; do
                (
                    FILE_PATH="${FILES_TO_UPLOAD[$i]}"
                    UPLOAD_RES=$(curl -s --retry 3 --connect-timeout 20 --max-time 1800 \
                        -u ":$PIXELDRAIN_API_KEY" \
                        -F "file=@${FILE_PATH}" \
                        "https://pixeldrain.com/api/file" || true)
                    echo "$UPLOAD_RES" > "$TMP_DIR/res_$i.json"
                ) &
            done
            wait

            for i in "${!FILES_TO_UPLOAD[@]}"; do
                FILE_PATH="${FILES_TO_UPLOAD[$i]}"
                FILE_NAME=$(basename "$FILE_PATH")
                UPLOAD_RES=$(cat "$TMP_DIR/res_$i.json" 2>/dev/null || true)
                SUCCESS=$(echo "$UPLOAD_RES" | jq -r '.success' 2>/dev/null || true)

                if [ "$SUCCESS" == "true" ]; then
                    FILE_ID=$(echo "$UPLOAD_RES" | jq -r '.id' 2>/dev/null || true)
                    UPLOADED_IDS+=("$FILE_ID")
                    echo "✅ Uploaded $FILE_NAME! ID: $FILE_ID"
                else
                    echo "❌ Failed to upload $FILE_NAME to Pixeldrain as well."
                    echo "Response: $UPLOAD_RES"
                    rm -rf "$TMP_DIR"
                    handle_error $LINENO
                fi
            done
            rm -rf "$TMP_DIR"
        fi
    fi

    if [ "$USE_PIXELDRAIN" == "true" ] && [ ${#UPLOADED_IDS[@]} -gt 0 ]; then
        echo "📁 Creating Pixeldrain List (Folder)..."
        
        FILES_JSON="["
        for i in "${!UPLOADED_IDS[@]}"; do
            FILES_JSON+="{\"id\":\"${UPLOADED_IDS[$i]}\", \"description\":\"\"}"
            if [ $i -lt $((${#UPLOADED_IDS[@]} - 1)) ]; then
                FILES_JSON+=","
            fi
        done
        FILES_JSON+="]"

        LIST_RES=$(curl -s -X POST -u ":$PIXELDRAIN_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"title\": \"$ROM_NAME Update\", \"files\": $FILES_JSON}" \
            "https://pixeldrain.com/api/list" || true)

        LIST_SUCCESS=$(echo "$LIST_RES" | jq -r '.success' 2>/dev/null || true)
        
        if [ "$LIST_SUCCESS" == "true" ]; then
            LIST_ID=$(echo "$LIST_RES" | jq -r '.id' 2>/dev/null || true)
            MASTER_LINK="https://pixeldrain.com/l/$LIST_ID"
            echo "✅ Folder created successfully!"
        else
            echo "⚠️ Failed to create folder list. Fallback to single file link."
            MASTER_LINK="https://pixeldrain.com/u/${UPLOADED_IDS[0]}"
        fi
    fi

    echo "🎉 Main uploads complete for $ROM_NAME!"
    echo "🔗 Master Link: $MASTER_LINK"

    # ==========================================
    # 🚀 SEND SUCCESS NOTIFICATION
    # ==========================================
    if [ -n "$MASTER_LINK" ]; then
        echo "📱 Sending 'Build Success' notification..."

        SUCCESS_MSG="🚀 <b>UPLOAD SUCCESSFUL</b>%0A%0A"
        SUCCESS_MSG+="<blockquote>• <b>Device:</b> ${DEVICE_NAME}%0A"
        SUCCESS_MSG+="• <b>ROM:</b> ${ROM_NAME}%0A"
        SUCCESS_MSG+="• <b>Android:</b> ${ANDROID_VERSION}%0A"
        SUCCESS_MSG+="• <b>Host:</b> ${BUILD_HOSTNAME}%0A"
        SUCCESS_MSG+="• <b>Time:</b> ${DISPLAY_TIME}%0A"
        if [ -n "$ROM_SIZE_HUMAN" ] && [ "$ROM_SIZE_HUMAN" != "Unknown" ]; then
            SUCCESS_MSG+="• <b>Size:</b> ${ROM_SIZE_HUMAN}%0A"
        fi
        if [ -n "$ROM_MD5" ] && [ "$ROM_MD5" != "Unknown" ]; then
            SUCCESS_MSG+="• <b>MD5:</b> <code>${ROM_MD5}</code>%0A"
        fi

        PROVIDER_NAME="Gofile"
        if [ "$USE_PIXELDRAIN" == "true" ] || [[ "$MASTER_LINK" == *"pixeldrain"* ]]; then
            PROVIDER_NAME="Pixeldrain"
        fi

        if [ -s source_changelog.txt ]; then
            CHANGELOG_URL=""
            
            # Upload changelog to paste.rs for a raw text preview link
            RES=$(curl -s --max-time 10 --data-binary @source_changelog.txt https://paste.rs/ || true)
            if [[ "$RES" == http* ]]; then
                CHANGELOG_URL=$(echo -n "$RES" | tr -d '\n\r')
            else
                # Fallback to dpaste.org
                RES=$(curl -s --max-time 10 -F "content=@source_changelog.txt" -F "format=url" -F "expiry_days=7" https://dpaste.org/api/ || true)
                if [[ "$RES" == http* ]]; then
                    CHANGELOG_URL=$(echo -n "$RES" | tr -d '\n\r')
                fi
            fi

            if [ -n "$CHANGELOG_URL" ]; then
                SUCCESS_MSG+="• <b>Changelog:</b> <a href=\"${CHANGELOG_URL}\">View Latest Changes</a>%0A"
            fi
        fi

        SUCCESS_MSG+="• <b>Download:</b> <a href=\"${MASTER_LINK}\">Download on ${PROVIDER_NAME}</a></blockquote>"

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
