#!/bin/bash

# Nazwa bucketu podawana jako argument
if [ $# -lt 1 ]; then
    echo "Błąd: Prosze podać bucket s3."
    echo "Użycie: $0 <nazwa_bucketu_s3> [nazwa_pliku_w_s3]"
    echo "Przykład: $0 mojado-bucket-info ec2_report.txt"
    exit 1
fi

S3_BUCKET="$1"
# Drugi Argument jako nazwa pliku
if [ $# -ge 2 ]; then
    S3_KEY="$2"
else
    S3_KEY="" 
fi


OUTPUT_FILE="/tmp/ec2_instance_info_$$ .txt" # $$ to PID procesu, unikalność
METADATA_URL="http://169.254.169.254/latest/meta-data"

# Funkcje



get_token() {
    # Pobranie tokena dla IMDSv2
    local token_response
    token_response=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    
    if [ -z "$token_response" ]; then
        echo "Błąd krytyczny: Nie udało się uzyskać tokena IMDSv2. Czy skrypt jest uruchomiony na instancji EC2?"
        exit 1
    fi
    export TOKEN="$token_response"
}

get_metadata() {
    local path=$1
    curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "$METADATA_URL/$path"
}

collect_data() {
    echo "=== Raport z Instancji EC2 ===" > "$OUTPUT_FILE"
    echo "Generowany: $(date)" >> "$OUTPUT_FILE"
    echo "----------------------------------------" >> "$OUTPUT_FILE"

    # Instance ID
    INSTANCE_ID=$(get_metadata "instance-id")
    echo "Instance ID: $INSTANCE_ID" >> "$OUTPUT_FILE"

    # Publiczny ip
    PUBLIC_IP=$(get_metadata "public-ipv4")
    echo "Public IP: ${PUBLIC_IP:-Brak}" >> "$OUTPUT_FILE"

    # Prywatny IP
    PRIVATE_IP=$(get_metadata "local-ipv4")
    echo "Private IP: $PRIVATE_IP" >> "$OUTPUT_FILE"

    # Security Groups
    echo "Security Groups:" >> "$OUTPUT_FILE"
    SG_LIST=$(get_metadata "security-groups")
    if [ -n "$SG_LIST" ]; then
        echo "$SG_LIST" | while read -r group; do
            echo "  - $group" >> "$OUTPUT_FILE"
        done
    else
        echo "  - Brak danych" >> "$OUTPUT_FILE"
    fi
    # System Operacyjny
    echo "System operacyjny:" >> "$OUTPUT_FILE"
    if [ -f /etc/os-release ]; then
        OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
        OS_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d'"' -f2)
        echo "  Name: $OS_NAME" >> "$OUTPUT_FILE"
        echo "  Version: $OS_VERSION" >> "$OUTPUT_FILE"
    else
        echo "  Nieznany (brak /etc/os-release)" >> "$OUTPUT_FILE"
    fi

    # Uzytkownik
    echo "Users (bash/sh):" >> "$OUTPUT_FILE"
    grep -E '/(bash|sh)$' /etc/passwd | cut -d':' -f1 | while read -r user; do
        echo "  - $user" >> "$OUTPUT_FILE"
    done

    echo "----------------------------------------" >> "$OUTPUT_FILE"
    echo "Koniec raportu." >> "$OUTPUT_FILE"
    
    # Jeśli użytkownik nie podał nazwy pliku w S3, generujemy ją na podstawie Instance ID
    if [ -z "$S3_KEY" ]; then
        S3_KEY="${INSTANCE_ID}_report_$(date +%Y%m%d_%H%M%S).txt"
    fi
}
main() {
    echo "Rozpoczynanie zbierania danych..."
    
    get_token
    collect_data
    upload_to_s3
    
    # Czyszczenie
    rm -f "$OUTPUT_FILE"
    echo "Zakończono."
}

main