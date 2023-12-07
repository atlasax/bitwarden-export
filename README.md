# bitwarden-export

Export bitwarden/vaultwarden vaults including attachments to an encrypted archive.

## Usage

Install [bitwarden-cli](https://github.com/bitwarden/cli) on your system and log into your account using `bw login`. When using a vaultwarden instance, you might want to set a custom URL first using `bw config server <URL>`. Then set your configuration (see below) and run the script in `bash`. Note that any session token already exported will be destroyed on run if not explicitly set otherwise.

### Example

```sh
# Optional: Set session token first
export BW_SESSION=$(bw unlock --raw)
# Run the exporter without destroying the existing session we just set
# Also encrypt the vault file individually and export to /tmp/bw_export_<datetime>.tar.gz.gpg
BW_KEEP_SESSION=1 BW_ENC_VAULT=1 BW_EXPORT_DIR="/tmp" ./bw_export.sh
```

## Configuration/Environment

The script is configured using environment variables.

##### BW_ENC_PASS (string)
Password used to encrypt the exported tar file (and the included vault if BW_ENC_VAULT is set). If not provided, you will be prompted during execution.

##### BW_ENC_VAULT (any/bool)
If set, the vault file within the encrypted tar will be individually encrypted using BW_ENC_PASS. Note that any string attached to the variable will be counted as setting it.

##### BW_EXPORT_DIR (path)
If set, the exported tar archive will be created in the specified directory. Else, the PWD is used.

##### BW_SESSION (token)
If this already contains a valid session (via `export BW_SESSION=$(bw unlock --raw)`), that session will be used. Else, you will be prompted for authentication during execution.

##### BW_KEEP_SESSION (any/bool)
If unset, the token in BW_SESSION will be invalidated on script exit. Note that any string attached to the variable will be counted as setting it.

## Known issues

The code checks if BW_SESSION is valid by calling `bw unlock --check`. This command is currently [bugged](https://github.com/bitwarden/clients/issues/2729) and always returns a negative response.

## Attribution

To create this script, I used [ckabalan's export script](https://github.com/ckabalan/bitwarden-attachment-exporter/blob/master/bw-export.sh) (MIT licensed) as a baseline and added more informative output and stricter checking.
