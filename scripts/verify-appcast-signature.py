#!/usr/bin/env python3
"""Verifies a published update the way the app will, from the public key alone.

    python3 scripts/verify-appcast-signature.py appcast.xml ImageShrink-1.1.0.dmg <SUPublicEDKey>

The signing script checks its own work, but it does that before publication, against the local
file, with the private key in the keychain. This checks what a stranger downloads, with nothing
but the public key the app carries — which is the only thing standing between a tampered
download and someone's Mac.

Needs `cryptography` (pip install cryptography); it is the ed25519 verification, nothing else.
"""
import base64
import pathlib
import re
import sys

try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
except ImportError:
    sys.exit("this needs the cryptography package: python3 -m pip install cryptography")

if len(sys.argv) != 4:
    sys.exit("usage: verify-appcast-signature.py <appcast.xml> <update.dmg> <public-key>")

appcast = pathlib.Path(sys.argv[1]).read_text()
update = pathlib.Path(sys.argv[2])
public_key_base64 = sys.argv[3].strip()

found = re.search(r'sparkle:edSignature="([^"]+)"', appcast)
if not found:
    sys.exit("the appcast carries no sparkle:edSignature")

try:
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_base64))
except (ValueError, TypeError) as error:
    sys.exit(f"that is not an ed25519 public key: {error}")

try:
    key.verify(base64.b64decode(found.group(1)), update.read_bytes())
except InvalidSignature:
    sys.exit("the signature does not verify against the app's own public key — "
             "an installed copy would refuse this update")
except (ValueError, TypeError) as error:
    sys.exit(f"the signature is malformed: {error}")

print(f"{update.name} verifies against {public_key_base64}")
