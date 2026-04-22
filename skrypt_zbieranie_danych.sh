#!/bin/bash

# Pierwszy argument to url do S3

if [ $# -lt 1 ]; then
    echo "Błąd: Brak wymaganego argumentu."
    echo "Użycie: $0 <nazwa_bucketu_s3> [nazwa_pliku_w_s3]"
    echo "Przykład: $0 applicant-task"
    exit 1
fi

S3_BUCKET="$1"
S3_KEY_ARG="$2"

TEMP_DIR="/tmp"
INSTANCE_ID=""
LOCAL_OUTPUT_FILE=""
METADATA_URL="http://169.254.169.254/latest/meta-data"


get_token() {
    local token_response
    token_response=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    
    if [ -z "$token_response" ]; then
        echo "Błąd krytyczny: Nie udało się uzyskać tokena IMDSv2."
        exit 1
    fi
    export TOKEN="$token_response"
}

get_metadata() {
    local path=$1
    curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "$METADATA_URL/$path"
}

collect_data() {
    INSTANCE_ID=$(get_metadata "instance-id")
    LOCAL_OUTPUT_FILE="${TEMP_DIR}/ec2_info_${INSTANCE_ID}.txt"
    
    echo "Zbieranie danych do pliku tymczasowego: $LOCAL_OUTPUT_FILE"

    {
        echo "=== Raport z Instancji EC2 ==="
        echo "Generowany: $(date)"
        echo "----------------------------------------"
        echo "Instance ID: $INSTANCE_ID"

        PUBLIC_IP=$(get_metadata "public-ipv4")
        echo "Public IP: ${PUBLIC_IP:-Brak}"

        PRIVATE_IP=$(get_metadata "local-ipv4")
        echo "Private IP: $PRIVATE_IP"

        echo "Security Groups:"
        SG_LIST=$(get_metadata "security-groups")
        if [ -n "$SG_LIST" ]; then
            echo "$SG_LIST" | while read -r group; do
                echo "  - $group"
            done
        else
            echo "  - Brak danych"
        fi

        echo "Operating System:"
        if [ -f /etc/os-release ]; then
            OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
            OS_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d'"' -f2)
            echo "  Name: $OS_NAME"
            echo "  Version: $OS_VERSION"
        else
            echo "  Nieznany"
        fi

        echo "Users (bash/sh):"
        grep -E '/(bash|sh)$' /etc/passwd | cut -d':' -f1 | while read -r user; do
            echo "  - $user"
        done

        echo "----------------------------------------"
        echo "Koniec raportu."
    } > "$LOCAL_OUTPUT_FILE"

    if [ -n "$S3_KEY_ARG" ]; then
        S3_KEY="$S3_KEY_ARG"
    else
        S3_KEY="${INSTANCE_ID}_report_$(date +%Y%m%d_%H%M%S).txt"
    fi
}

upload_to_s3() {
    echo "Przesyłanie do S3: s3://$S3_BUCKET/$S3_KEY"
    
    aws s3 cp "$LOCAL_OUTPUT_FILE" "s3://$S3_BUCKET/$S3_KEY"
    
    local status=$?
    if [ $status -eq 0 ]; then
        echo "Sukces! Plik zapisany w: s3://$S3_BUCKET/$S3_KEY"
    else
        echo "Błąd: Nie udało się przesłać pliku do S3."
        exit 1
    fi
}

cleanup() {
    if [ -f "$LOCAL_OUTPUT_FILE" ]; then
        rm -f "$LOCAL_OUTPUT_FILE"
        echo "Wyczyszczono plik tymczasowy: $LOCAL_OUTPUT_FILE"
    fi
}

main() {
    echo "Rozpoczynanie zbierania danych..."
    
    get_token
    collect_data
    upload_to_s3
    cleanup
    
    echo "Zakończono."
}

main