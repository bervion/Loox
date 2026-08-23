/* Loox App Store screenshots — all user-visible copy lives here.
   To add a language: copy a block, translate every value, add the code to `order`.
   "\n" inside a headline forces a line break.

   Keys are named after the frame they fill (hPrivate → frame 01), so reordering
   frames never silently swaps copy. Feature labels f1…f8 fill the last frame and
   use the same wording as the app's own UI (Localizable.xcstrings).

   Per-language type controls so you never have to touch the design:
     track      headline letter-spacing (Latin tight, CJK 0)
     titleScale headline size multiplier (base 124px iPhone / 146px iPad)
     lh         headline line-height                                        */

window.LOOX_STRINGS = {
  order: ["en", "vi", "ja"],

  en: {
    name: "EN",
    label: "English",
    track: "-0.045em",
    titleScale: 1,
    lh: 1.08,
    hPrivate: "Your passwords,\nfinally private.",
    hAutofill: "Sign in without\ntyping anything.",
    hVault: "One vault for\neverything you keep.",
    hCodes: "Your 2FA codes\nlive here too.",
    hWatchtower: "Find weak and\nreused passwords.",
    hShare: "Share a password.\nKeep control.",
    hGenerator: "Strong passwords,\none tap away.",
    hAll: "Everything you need.",
    foot: "No account. No servers. No tracking.\nYour vault never leaves the device unless you say so.",
    f1: "AutoFill",
    f2: "Passkeys",
    f3: "2FA codes",
    f4: "Security score",
    f5: "Approval sharing",
    f6: "Expiring links",
    f7: "Private email",
    f8: "Separate identities"
  },

  vi: {
    name: "VI",
    label: "Tiếng Việt",
    track: "-0.04em",
    titleScale: 0.94,
    lh: 1.1,
    hPrivate: "Mật khẩu của bạn,\nriêng tư thật sự.",
    hAutofill: "Đăng nhập\nkhông cần gõ gì.",
    hVault: "Tất cả, gọn trong\nmột kho duy nhất.",
    hCodes: "Mã xác minh cũng\nnằm ngay ở đây.",
    hWatchtower: "Tìm mật khẩu yếu\nvà bị dùng lại.",
    hShare: "Chia sẻ mật khẩu.\nGiữ toàn quyền.",
    hGenerator: "Mật khẩu mạnh,\nchỉ một chạm.",
    hAll: "Mọi thứ bạn cần.",
    foot: "Không tài khoản. Không máy chủ. Không theo dõi.\nKho của bạn không rời khỏi máy, trừ khi bạn cho phép.",
    f1: "Tự động điền",
    f2: "Passkey",
    f3: "Mã xác minh",
    f4: "Điểm bảo mật",
    f5: "Chế độ phê duyệt",
    f6: "Liên kết tự hết hạn",
    f7: "Email riêng tư",
    f8: "Danh tính riêng"
  },

  ja: {
    name: "JA",
    label: "日本語",
    track: "0em",
    titleScale: 0.8,
    lh: 1.4,
    hPrivate: "パスワードは、\nあなただけのもの。",
    hAutofill: "入力せずに\nサインイン。",
    hVault: "すべてを\nひとつの保管庫に。",
    hCodes: "2FAコードも\nここにまとめて。",
    hWatchtower: "弱い・使い回しの\nパスワードを発見。",
    hShare: "共有しても、\n主導権はあなた。",
    hGenerator: "強いパスワードを\nワンタップで。",
    hAll: "必要なものすべて。",
    foot: "アカウントなし。サーバーなし。追跡なし。\n許可しない限り、保管庫は端末から出ません。",
    f1: "自動入力",
    f2: "パスキー",
    f3: "2FAコード",
    f4: "セキュリティ診断",
    f5: "承認モード",
    f6: "期限付きリンク",
    f7: "プライベートメール",
    f8: "プロフィール分離"
  }
};
