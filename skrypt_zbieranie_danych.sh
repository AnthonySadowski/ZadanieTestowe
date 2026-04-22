#!/bin/bash


if [ $# -lt 1 ]; then
    echo "Błąd: Brak wymaganego argumentu."
    echo "Użycie: $0 <nazwa_bucketu_s3> [nazwa_pliku_w_s3]"
    echo "Przykład: $0 mojado-bucket-info"
    exit 1
fi

S3_BUCKET="$1"
S3_KEY_ARG="$2" 


CURRENT_DIR="$(pwd)"

LOCAL_OUTPUT_FILE="" 

METADATA_URL="http://169.254.169.254/latest/meta-data"

# --- Funkcje ---

check_dependencies() {
    local pkg_manager=""
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    else
        echo "Ostrzeżenie: Nie wykryto menedżera pakietów (apt/yum)."
        return
    fi

    if ! command -v aws &> /dev/null; then
        echo "Instalacja AWS CLI..."
        $pkg_manager update -qq && $pkg_manager install -y awscli
    fi
    
    if ! command -v curl &> /dev/null; then
        echo "Instalacja curl..."
        $pkg_manager update -qq && $pkg_manager install -y curl
    fi
}

get_token() {
    local token_response
    token_response=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    
    if [ -z "$token_response" ]; then
        echo "Błąd krytyczny: Nie udało się uzyskać tokena IMDSv2. Czy skrypt jest na instancji EC2?"
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
    

    LOCAL_OUTPUT_FILE="${CURRENT_DIR}/ec2_info_${INSTANCE_ID}.txt"
    
    echo "Zapisywanie danych do: $LOCAL_OUTPUT_FILE"

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
            echo "  Nieznany (brak /etc/os-release)"
        fi

        # 6. Users
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