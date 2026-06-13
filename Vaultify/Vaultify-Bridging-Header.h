//
//  Vaultify-Bridging-Header.h
//  Exposes the vendored Argon2id reference C implementation to Swift.
//
//  The C sources live under Security/CArgon2 (canonical phc-winner-argon2,
//  portable `ref.c` build). Only the public header is imported here; the
//  Swift wrapper lives in Security/Crypto/Argon2.swift.
//

#import "Security/CArgon2/argon2.h"
