//
//  VaultifySafari-Bridging-Header.h
//  Exposes the vendored Argon2id reference C implementation to the extension.
//  VaultifyCore compiles into this target, so its crypto layer needs the
//  header even though the KDF is never invoked from the Safari handler.
//  The C sources live under VaultifyCore/CArgon2 (resolved via HEADER_SEARCH_PATHS).
//

#import "argon2.h"
