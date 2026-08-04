#!/usr/bin/env bash
# Fails when a target uses a required-reason API that its bundle's privacy
# manifest does not declare. Apple rejects that at upload, after the archive is
# already signed, so it is cheaper to catch here.
#
# Four targets, two manifests (source globs copied from Project.swift):
#   Vaultify (app)       Vaultify/** + VaultifyCore/**         Vaultify/Resources/PrivacyInfo.xcprivacy
#   VaultifyAutoFill     VaultifyAutoFill/** + VaultifyCore/** ExtensionResources/PrivacyInfo.xcprivacy
#   VaultifyAutoFillMac  VaultifyAutoFill/** + VaultifyCore/** ExtensionResources/PrivacyInfo.xcprivacy
#   VaultifySafari       VaultifySafari/** + VaultifyCore/**   ExtensionResources/PrivacyInfo.xcprivacy
set -euo pipefail
cd "$(dirname "$0")/../.."

# "<category-suffix> <ERE>". Each pattern names the actual API, not a word that
# merely reads like one — a CKRecord's `.creationDate` is not a file timestamp.
API_PATTERNS='UserDefaults UserDefaults
SystemBootTime systemUptime|mach_absolute_time|CACurrentMediaTime|uptimeNanoseconds
FileTimestamp creationDateKey|contentModificationDateKey|NSFileCreationDate|NSFileModificationDate|getattrlist\(|fstat\(|lstat\(
DiskSpace volumeAvailableCapacity|systemFreeSize|NSFileSystemFreeSize|statfs\(
ActiveKeyboards activeInputModes'

failed=0

check() { # $1 manifest, $2 label, $3… source dirs
  manifest="$1"; label="$2"; shift 2
  if [ ! -f "$manifest" ]; then
    echo "missing privacy manifest: $manifest ($label)" >&2; failed=1; return
  fi
  declared="$(plutil -extract NSPrivacyAccessedAPITypes json -o - "$manifest")"
  while read -r category pattern; do
    grep -rqE "$pattern" "$@" --include='*.swift' || continue
    case "$declared" in
      *"NSPrivacyAccessedAPICategory$category"*) ;;
      *)
        echo "$manifest ($label) must declare NSPrivacyAccessedAPICategory$category" >&2
        grep -rlE "$pattern" "$@" --include='*.swift' | sed 's/^/    used in /' >&2
        failed=1
        ;;
    esac
  done <<< "$API_PATTERNS"
}

check Vaultify/Resources/PrivacyInfo.xcprivacy app Vaultify VaultifyCore
check ExtensionResources/PrivacyInfo.xcprivacy appexes VaultifyCore VaultifyAutoFill VaultifySafari

[ "$failed" -eq 0 ] || { echo "privacy manifest check failed" >&2; exit 1; }
echo "privacy manifests cover every required-reason API in use"
