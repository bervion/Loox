import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform text-input descriptors + view modifiers.
///
/// `keyboardType`, `textInputAutocapitalization`, and the `UIKeyboardType` /
/// `TextInputAutocapitalization` / `UITextContentType` types are all iOS-only
/// (no software keyboard on macOS). These wrappers let shared field views name an
/// input intent once and compile everywhere — the modifiers apply on iOS and are
/// no-ops on macOS. (Native macOS content-type autofill hinting arrives with the
/// macOS AutoFill work in a later phase.)

enum PlatformKeyboardType {
    case `default`, emailAddress, url, numberPad, decimalPad, numbersAndPunctuation, phonePad
    #if os(iOS)
    var uiKit: UIKeyboardType {
        switch self {
        case .default: .default
        case .emailAddress: .emailAddress
        case .url: .URL
        case .numberPad: .numberPad
        case .decimalPad: .decimalPad
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .phonePad: .phonePad
        }
    }
    #endif
}

enum PlatformAutocapitalization {
    case never, words, sentences, characters
    #if os(iOS)
    var swiftUI: TextInputAutocapitalization {
        switch self {
        case .never: .never
        case .words: .words
        case .sentences: .sentences
        case .characters: .characters
        }
    }
    #endif
}

enum PlatformTextContentType {
    case password, newPassword, username, emailAddress, name, oneTimeCode, url
    #if os(iOS)
    var uiKit: UITextContentType {
        switch self {
        case .password: .password
        case .newPassword: .newPassword
        case .username: .username
        case .emailAddress: .emailAddress
        case .name: .name
        case .oneTimeCode: .oneTimeCode
        case .url: .URL
        }
    }
    #endif
}

extension View {
    /// iOS software-keyboard type; no-op on macOS.
    func platformKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if os(iOS)
        return keyboardType(type.uiKit)
        #else
        return self
        #endif
    }

    /// iOS autocapitalization behavior; no-op on macOS.
    func platformAutocapitalization(_ mode: PlatformAutocapitalization) -> some View {
        #if os(iOS)
        return textInputAutocapitalization(mode.swiftUI)
        #else
        return self
        #endif
    }

    /// iOS content-type hint (autofill/keyboard); no-op on macOS for now.
    func platformTextContentType(_ type: PlatformTextContentType) -> some View {
        #if os(iOS)
        return textContentType(type.uiKit)
        #else
        return self
        #endif
    }
}
