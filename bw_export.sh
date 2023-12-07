#!/bin/bash

## Export bitwarden vault items including attachments
## Based on https://github.com/ckabalan/bitwarden-attachment-exporter/blob/master/bw-export.sh
# 
# Creates a gpg-encrypted bw_export_<datetime>.tar.gz.gpg file in the specified export directory (or pwd).
# Contains a plaintext or encrypted vault.json as well as an attachments/<vault item id> folder for each vault entry,
# containing unencrypted attachments.
# 
# First, set up bitwarden with `bw login`, possibly after setting a custom vault URL with `bw config server <URL>`.
# Then run this script, optionally setting any of the following environment variables:
# 
# BW_ENC_PASS     | Password used to encrypt the exported tar file (and the included vault if BW_ENC_VAULT is set).
# BW_ENC_VAULT    | If set, the vault file within the encrypted tar will be individually encrypted using BW_ENC_PASS.
# BW_EXPORT_DIR   | If set, the exported tar will be created in this directory. Else, the PWD is used.
# BW_SESSION      | If this already contains a valid session, it will be used. Else, you will be prompted for authentication.
# BW_KEEP_SESSION | If unset, the token in BW_SESSION will be invalidated on script exit.

# Fail on error
set -e

# Check if the user is already logged in (i.e. has URL and user set up)
if ! bw login --check &> /dev/null; then
    echo 'Bitwarden is not set up. Please run `bw login`.' >&2
    exit 255
fi

# Create staging directory for unencrypted files
STAGEDIR=$(mktemp -d)
chmod 700 "$STAGEDIR"
echo "Using staging dir '$STAGEDIR'."
BUILDDIR="$STAGEDIR/raw"
mkdir -p "$BUILDDIR/attachments"

# Get a valid session token if the session is not already available
# You might want to use API key authentication for automated vault exports (or set BW_SESSION yourself)
if  bw unlock --check &> /dev/null; then # currently broken due to a bug in bw-cli vault locking
    echo 'No valid session available, prompting for password...'
    # A token can also be supplied explicitly using `bw <command> --session '<TOKEN>'`
    # This export is only valid within the scope of this script
    export BW_SESSION=$(bw unlock --raw)
    [ -z "$BW_SESSION" ] && echo 'Could not create session token.' && exit 254
fi

# Set exit trap to clean up
on_exit() {
    [ $? -gt 0 ] && echo 'Something went wrong! Aborting.'
    # Ignore errors in exit handler
    set +e
    # Remove staging dir with unencrypted data
    rm -rf -- "$STAGEDIR" &> /dev/null
    # Re-lock bitwarden to destroy used key
    if [ -z "$BW_KEEP_SESSION" ]; then
        bw lock &> /dev/null
        unset BW_SESSION
        echo 'Session token destroyed.'
    fi
    echo 'Clean-up complete.'
}
trap on_exit EXIT
trap 'echo -e "\nAborted by user."; exit 0' SIGINT

# Make sure the local vault state is current, then export
bw sync
sync_time=$(date "+%Y-%m-%d_%H-%M-%S")

# If not provided, prompt for an encryption password
if [ -z "$BW_ENC_PASS" ]; then
    read -sp "Choose a password for the export: " first_enc_pass; echo
    read -sp "Confirm your password: " BW_ENC_PASS; echo
    [ "$first_enc_pass" != "$BW_ENC_PASS" ] && echo 'Your passwords did not match.' && exit 253
fi

# Export the vault into a json file (encrypted depending on BW_ENC_VAULT)
if [ -n "$BW_ENC_VAULT" ]; then
    echo 'Staging base vault as encrypted json file using supplied password.'
    bw export --format encrypted_json --password "$BW_ENC_PASS" --output "$BUILDDIR/vault.json"
else
    echo 'Staging base vault as unencrypted json file (BW_ENC_VAULT not set).'
    bw export --format json --output "$BUILDDIR/vault.json"
fi

# Collect attachments for each vault item
# One attachment per line (format: "<item id>" "<attachment id>" "<attachment filename>")
# This will create problems for filenames including double quotes, so let's pretend those don't exist
attachment_data=$(
    bw list items | jq -r '.[] | select(.attachments != null) | . as $parent | .attachments[] |
    "\"\($parent.id)\" \"\(.id)\" \"\(.fileName)\""'
)

if [ -z "$attachment_data" ]; then
    echo No attachments found.
else
    # Download attachments to staging dir
    echo "Processing $(echo -e "$attachment_data" | wc -l) attachments..."
    echo -e "$attachment_data" | while IFS= read -r file_entry; do
        # Read in vars and trim quotes
        read -r item_id file_id file_name <<< "$file_entry"
        item_id=$(echo $item_id | tr -d '"')
        file_id=$(echo $file_id | tr -d '"')
        file_name=$(echo $file_name | tr -d '"')
        # Download attachments to staging dir
        bw get attachment "$file_id" --itemid "$item_id" --output "$BUILDDIR/attachments/$item_id/$file_name"
    done
    echo "Download of attachments complete."
fi

# Process staging dir into tar file
archive_name="bw_export_$sync_time.tar.gz"
tar czvf "$STAGEDIR/$archive_name" -C "$BUILDDIR" . &> /dev/null

# Encrypt tar file into export/local directory, cleanup will be handled by our trap
export_path="${BW_EXPORT_DIR:-.}/$archive_name.gpg"
gpg -c --cipher-algo AES256 --passphrase "$BW_ENC_PASS" --batch --yes -o "$export_path" "$STAGEDIR/$archive_name"
echo "Export to '$(realpath "$export_path" 2> /dev/null || echo "$export_path")' finished." 
