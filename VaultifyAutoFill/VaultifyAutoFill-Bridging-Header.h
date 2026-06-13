//
//  VaultifyAutoFill-Bridging-Header.h
//  Exposes the vendored Argon2id reference C implementation to the extension,
//  so it can unwrap the Vault Key from the shared key bundle. The C sources
//  live under VaultifyCore/CArgon2 (resolved via HEADER_SEARCH_PATHS).
//

#import "argon2.h"
