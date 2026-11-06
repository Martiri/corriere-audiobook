#!/usr/bin/env bash
set -e

# ==============================================================================
# Script per la generazione sicura del Keystore permanente RSA-2048
# Regola Globale: permessi chmod 600 per proteggere le credenziali e i segreti
# ==============================================================================

KEYSTORE_DIR="android/app/keystore"
KEYSTORE_FILE="$KEYSTORE_DIR/release-key.jks"
ALIAS="corrierekey"
VALIDITY_DAYS=10000

echo "=== Generazione Keystore di Release per Corriere Audiobook ==="

mkdir -p "$KEYSTORE_DIR"

if [ -f "$KEYSTORE_FILE" ]; then
    echo "⚠️  Il keystore $KEYSTORE_FILE esiste già!"
    echo "Per ricrearlo rimuovilo prima manualmente."
    exit 0
fi

read -s -p "Inserisci la password per il Keystore (min. 6 caratteri): " PASSWORD
echo ""

if [ -z "$PASSWORD" ]; then
    echo "❌ Password non valida. Operazione annullata."
    exit 1
fi

keytool -genkeypair -v \
  -keystore "$KEYSTORE_FILE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storepass "$PASSWORD" \
  -keypass "$PASSWORD" \
  -dname "CN=Franco, OU=Development, O=Personal, L=Bologna, ST=BO, C=IT"

# Imposta permessi restrittivi 600 in accordo con la Regola Globale di sicurezza
chmod 600 "$KEYSTORE_FILE"

echo ""
echo "✅ Keystore generato con successo in: $KEYSTORE_FILE"
echo "🔒 Permessi impostati a 600 (-rw-------)"
echo ""
echo "Per configurare il rilascio su GitHub Actions:"
echo "1. Vai su GitHub > Repository Settings > Secrets and variables > Actions"
echo "2. Crea i seguenti repository secrets:"
echo "   - KEYSTORE_PASSWORD: $PASSWORD"
echo "   - KEY_ALIAS: $ALIAS"
echo "   - KEY_PASSWORD: $PASSWORD"
echo "   - KEYSTORE_BASE64: (esegui il comando seguente per ottenerlo)"
echo ""
echo "Comando per copiare KEYSTORE_BASE64 negli appunti:"
echo "base64 -w 0 $KEYSTORE_FILE"
echo "=============================================================="
