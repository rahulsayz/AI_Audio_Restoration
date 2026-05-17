# Playbook - Cryptographic Release Signing for Sangeet AI Updates

Sangeet AI uses **Sparkle 2.x** with EdDSA (Ed25519) signatures to guarantee the authenticity of software updates. When the app detects an update, it validates the update bundle's signature against our embedded public key. If the signature is missing or incorrect, the update is rejected to prevent tampering.

---

## 1. Key Generation and Storage

The key generation tool automatically stores the private signing key inside the macOS Keychain. This ensures that the private key is encrypted at rest, linked to your user account, and **never enters the Git repository**.

* **Key Type**: Ed25519 (EdDSA)
* **Keychain Service**: `Private key for signing Sparkle updates`
* **Keychain Account**: `ed25519`
* **Public Key**: `thhl0WF2JAWTfEHllsA84pVyObZ+ilt+hORgW+5Z+/k=`
* **Embedded Configuration**: Declared in Sangeet AI's target build settings (`project.pbxproj`) as `INFOPLIST_KEY_SUPublicEDKey`.

---

## 2. Backing Up and Transferring the Private Key

Because the private key is stored in your login keychain, it is safe from ordinary data exposure. However, if your development machine is lost or replaced, you must have a backup to sign future updates.

### Exporting the Key
Run this command to export your private key to a secure file. 

> [!CAUTION]
> Treat the exported private key file with the highest security. **Never commit it to git, upload it to slack, or send it over email.** Store it in an encrypted password manager or a secure off-line physical drive.

```bash
# Export from Keychain to a secure local file (outside the workspace)
/Users/rahulchaturvedi/Library/Developer/Xcode/DerivedData/SangeetAI-degymxqjqeetrkewkhkyppveapmg/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/.sangeet-keys/sangeet-private-key.key
```

### Importing the Key to a New Machine
If you need to sign releases on a different Mac, copy the private key file securely to that machine, then import it:

```bash
# Import the private key file back into the macOS Keychain
/Users/rahulchaturvedi/Library/Developer/Xcode/DerivedData/SangeetAI-degymxqjqeetrkewkhkyppveapmg/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -f ~/.sangeet-keys/sangeet-private-key.key

# Securely erase the temporary file from disk immediately after import
rm -f ~/.sangeet-keys/sangeet-private-key.key
```

---

## 3. Signing an Update Bundle

To distribute a new version of Sangeet AI:

1. **Build and Package**: Compile the release version of Sangeet AI and package it as a `.zip` file or `.dmg` (e.g., `SangeetAI-1.1.0.zip`).
2. **Sign the Archive**: Run the Sparkle `sign_update` tool to compute the Ed25519 signature for the packaged update.

```bash
# Execute the Sparkle signing tool on your packaged ZIP
/Users/rahulchaturvedi/Library/Developer/Xcode/DerivedData/SangeetAI-degymxqjqeetrkewkhkyppveapmg/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /path/to/SangeetAI-1.1.0.zip
```

This command will print a signature string resembling:
```text
sparkle:edSignature="base64_encoded_signature_hash_here" length="file_size_in_bytes"
```

Copy this output directly. You will paste this signature, signature length, and the file size into the corresponding `<enclosure>` tag in `appcast.xml` when deploying.
