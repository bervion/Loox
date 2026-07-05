# Runbook FE — invite.looxpassword.com (Cloudflare)

Mục tiêu: subdomain tĩnh phục vụ Universal Links cho app Loox. KHÔNG có logic backend,
KHÔNG nhận/lưu secret — chỉ 2 thứ: file AASA và landing page tĩnh.

## 1. DNS
Cloudflare dashboard → looxpassword.com → DNS:
- Thêm record cho `invite` trỏ vào Cloudflare Pages project (CNAME, proxied ☁️ ON).

## 2. AASA file (bắt buộc, quyết định Universal Link có chạy hay không)

Path phải CHÍNH XÁC: `https://invite.looxpassword.com/.well-known/apple-app-site-association`

Yêu cầu cứng của Apple:
- HTTPS, status 200, KHÔNG redirect (kể cả 301 www / trailing slash).
- `Content-Type: application/json` (không cần đuôi .json trong path).
- Không chặn bởi Bot Fight Mode / WAF / Access — Apple CDN (`applebot`) phải fetch được.
- File < 128KB.

Nội dung (TEAM ID `WDNL2F75V7`, bundle `com.bervion.vaultify`):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["WDNL2F75V7.com.bervion.vaultify"],
        "components": [
          { "/": "/i/*", "comment": "share invite tokens" }
        ]
      }
    ]
  }
}
```

Cách deploy trên Pages: đặt file tại `public/.well-known/apple-app-site-association`
(không đuôi). Thêm `_headers`:

```
/.well-known/apple-app-site-association
  Content-Type: application/json
```

Kiểm tra sau deploy:
```
curl -sI https://invite.looxpassword.com/.well-known/apple-app-site-association
# → 200, content-type: application/json, KHÔNG có Location:
```
Apple cache AASA qua CDN của họ (có thể trễ tới 24h; máy dev có thể ép bằng
associated domains developer mode: `applinks:invite.looxpassword.com?mode=developer`).
QA chính thức theo Apple technote về debug Universal Links (app-side sẽ làm) —
curl 200 chỉ là điều kiện cần, KHÔNG phải điều kiện đủ.

**Format token (`/i/<token>`):** token là random 192–256 bit Base64URL do app sinh —
KHÔNG BAO GIỜ sequential, KHÔNG derive từ email/tên. FE không cần biết cấu trúc token;
chỉ cần route `/i/*` về landing.

## 3. Landing page `/i/*` (fallback khi CHƯA cài app)

Universal Link chỉ mở app khi app đã cài; nếu chưa, Safari mở URL thật → cần landing:
- Route `/i/*` (Pages SPA fallback hoặc 1 file `i/[token].html` render tĩnh):
  - Tiêu đề: "Bạn được mời dùng chung một mục trong Loox Password".
  - Nút App Store (link TestFlight/App Store của app).
  - KHÔNG hiển thị hay decode token — token chỉ có nghĩa với app.
  - Copy nêu rõ: mở link này trên iPhone đã cài Loox để chấp nhận lời mời.
- Không log token vào analytics.

## 4. Những thứ KHÔNG làm ở FE
- Không tạo API nhận invite/token — nguồn dữ liệu là CloudKit public DB, app đọc trực tiếp.
- Không đụng api.looxpassword.com.
- Không thêm redirect rules áp lên `/.well-known/*`.

## 5. Bàn giao
Sau khi deploy xong, báo lại: URL AASA trả 200 + content-type đúng (kết quả curl ở bước 2).
Phía app (mình lo): bật Associated Domains capability trong Apple portal + Project.swift,
regenerate provisioning (fastlane match), handler NSUserActivity trong app.
