//
//  Vaultify-Bridging-Header.h
//  Exposes the vendored Argon2id reference C implementation to Swift.
//
//  The C sources live under VaultifyCore/CArgon2 (canonical phc-winner-argon2,
//  portable `ref.c` build), shared by the app and the AutoFill extension.
//  Only the public header is imported here (resolved via HEADER_SEARCH_PATHS);
//  the Swift wrapper lives in VaultifyCore/Crypto/Argon2.swift.
//

#import "argon2.h"
