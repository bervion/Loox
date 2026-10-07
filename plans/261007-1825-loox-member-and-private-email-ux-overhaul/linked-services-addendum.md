# Dịch vụ liên kết với email riêng tư

User refinement ngày 2026-10-07: xem Facebook/Gmail/GitHub đã lưu địa chỉ riêng tư, mở mục đăng nhập và gỡ liên kết với mục đó. Đây là cập nhật plan/prototype, chưa là tính năng đã triển khai.

## Luồng màn hình

| Điểm vào | Danh sách | Hành động |
|---|---|---|
| Email riêng tư → Dịch vụ liên kết | Mọi mục Login có private email liên kết trong hồ sơ đang dùng | Mở row để xem mục và địa chỉ |
| Chi tiết một địa chỉ → Dịch vụ liên kết | Chỉ các Login dùng địa chỉ đó | Mở mục đăng nhập, liên kết thêm, gỡ từng mục |
| Chi tiết một dịch vụ | Tên mục Login, website nếu có, địa chỉ riêng tư, trạng thái chuyển tiếp | Mở mục đăng nhập; Gỡ liên kết là quiet destructive action có xác nhận |

Root vẫn là danh sách địa chỉ; không trải mọi dịch vụ bên trong từng card. Row `Dịch vụ liên kết` có count, bấm mở danh sách. Alias detail có row/count tương ứng. Danh sách ưu tiên tên dịch vụ/mục (Facebook, Gmail, GitHub), alias là subtitle wrap. Nhiều tài khoản cùng dịch vụ là nhiều rows theo itemID, không gộp mất danh tính. Tất cả scoped theo persona hiện tại; đổi hồ sơ phải rebind projection/navigation.

Empty state: `Chưa có dịch vụ liên kết`, giải thích chọn mục đã lưu hoặc thêm mục đăng nhập; primary `Liên kết mục đăng nhập`. Một alias dùng nhiều nơi có thể xuất hiện ở nhiều Login. Địa chỉ theo dịch vụ khuyến nghị riêng từng dịch vụ, nhưng đó là cách dùng, không là ràng buộc storage 1:1.

## Nguồn dữ liệu

Không tự phát hiện bên ngoài app nơi địa chỉ đã được đăng ký. Danh sách chỉ chứng minh địa chỉ được liên kết/lưu trong các mục vault, không chứng minh tài khoản dịch vụ đã xác minh email hoặc đang đăng nhập.

Canonical projection dùng `items(for: persona)` và `Private email` field (kind `.email`, stable raw label `AliasWriteback.privateEmailLabel`), exact match trusted immutable alias address. Đây là field đã nằm trong sealed VaultItem; không cần thêm danh sách itemIDs vào sealed alias. Không quét username/Email chính/note để tự suy luận liên kết. Alias `boundItemId` hiện có chỉ là primary/legacy creation hint, không là toàn bộ danh sách dịch vụ.

Alias address chưa resolve/proof không đủ: không đoán suffix hoặc tự match sang alias khác. Legacy boundItemId còn tồn tại nhưng canonical field khác/mất: hiển thị cần kiểm tra liên kết, không claim đang dùng hoặc overwrite field. Deleted/missing-folder/foreign-persona Login không hiện trong list/count. Address không còn alias quản lý không tự gán cho alias đang có.

Dữ liệu 1.56.6 có thể dùng ordinary Email/username khi reuse alias, không có canonical field cho Login thứ hai. List không hứa tự nhận ra toàn bộ các mục cũ. Quiet `Rà soát mục đã lưu` là thao tác có chủ đích: tìm exact readable address matches trong ordinary Email/username cùng persona, hiển thị candidate cần xác nhận và mở Login/adopt canonical link. Không tự convert/delete hoặc tính candidate vào count đã liên kết; field không đọc được/Extra Protection không bị giải mã ngoài gate. Sau unlink không chạy scanner tự động để thêm lại association; review lại chỉ khi người dùng chủ động yêu cầu.

Link/reuse: guarded upsert canonical Private email trên Login sau save thành công, giữ Email/username thật. Login có private email khác vẫn block và hướng chọn mục khác. Protected/ciphertext field hoặc duplicate canonical fields là unknown/conflict, không coi slot trống; mở Login để unlock/repair bằng existing extra-protection gate trước mutation. Không blind gọi helper overwrite field đầu tiên. Alias đã bound item A có thể được lưu cho item B mà không repoint primary binding A; đối với alias chưa có primary binding có thể giữ pointer tạo lần đầu để tương thích. Suggester/editor phải dùng linked-item projection cho relation lookup; không tiếp tục coi `boundItemId == nil` là điều kiện để reuse toàn bộ. Link thêm alias đã active chỉ save local field, không re-activate/rotate backend.

## Gỡ liên kết

Confirmation nêu cụ thể Login và alias:

> Gỡ địa chỉ này khỏi mục GitHub trong vault. Địa chỉ vẫn nhận thư. Email đăng nhập trên GitHub không thay đổi.

Localized generic template dùng tên mục, không hardcode provider trong native. Primary `Gỡ liên kết`, quiet `Hủy`. Gỡ làm:

1. Re-read live Login/alias, validate owner và fieldID/value/operation revision còn khớp snapshot người dùng đã xác nhận.
2. Remove đúng canonical Private email field đang chứa địa chỉ này; không thay Email chính/username/password, không ghi lại whole stale item snapshot.
3. Nếu boundItemId legacy trỏ đúng Login đó, clear pointer bằng live-row patch **trong cùng repository transaction/save với field removal**. Stage/seal cả hai rồi một commit; rollback khi failure, reload/notify sau commit. Giữ domain/service label context; không gán pointer tùy tiện sang một Login khác.
4. List/count/suggestion cập nhật từ observed repository; Login và alias vẫn tồn tại, forwarding/status/domain/inbox không đổi. Không gọi pause/revoke/delete/rotate API cho việc unlink.

Field bị người dùng đổi trong lúc confirmation mở: không xóa giá trị mới, báo liên kết đã đổi và refresh. Missing/deleted Login chỉ cleanup pointer nếu phù hợp; không tạo lại Login. Nếu cleanup/persistence fail, rollback và giữ recovery/retry rõ, không báo full success; retry idempotent, không tạo địa chỉ mới. Link/unlink/writeback share relation revision; delayed activate/rotate/editor save phải revalidate relation intent trước viết field, không reattach từ old alias snapshot/pointer. Process interruption giữa các staged changes không commit partial state.

Unlink là local vault mutation, dùng được offline và khi relay user-off/maintenance/retired; không cần remote mutation permission. Locked vault hoặc unknown/protected field vẫn theo existing authentication policy. Không bypass Extra Protection để match/xóa một field chưa biết giá trị.

Nếu người dùng đang dùng alias làm Email chính/username ở tài khoản dịch vụ, gỡ liên kết không đổi những giá trị đó. Muốn đổi email đăng nhập phải thao tác trên dịch vụ. Muốn dừng nhận thư là thao tác `Tạm dừng chuyển tiếp` riêng trong alias detail, có scope/confirmation riêng.

## Implementation inventory / tests

P3 sở hữu proposed `Vaultify/Features/Personas/AliasLinkedServicesScreen.swift` và pure projection; reuse scoped Login chooser, ItemDetail và tokens/Polaris. Integration thêm EN/VI/JA. Modify alias overview/detail/editor, AliasSuggestion, writeback và sealed draft handoff theo existing P3 inventory. Không thêm backend provider-account integration.

Tests: một alias→ba Login; ba aliases→ba dịch vụ; hai tài khoản GitHub; reusable/per-service; unbound/legacy mismatch/unresolved suffix; foreign/missing-folder; link after draft restore; unlink một mục giữ hai mục khác; username/Email chính nguyên; stale confirmation/editor/relay writeback; atomic persistence failure/retry/relaunch/process interruption; protected/foreign L2/custom-code/duplicate fields; offline/user-off unlink; active/paused alias không đổi trạng thái; AutoFill mất riêng lựa chọn Private email vừa gỡ (ordinary username/Email vẫn nguyên). Không promise revoke email từng sender: pause alias ảnh hưởng mọi dịch vụ cùng dùng alias đó.

Copy glossary:

| English | VI | JA |
|---|---|---|
| Linked services | Dịch vụ liên kết | 関連付けられたサービス |
| No linked services | Chưa có dịch vụ liên kết | 関連付けられたサービスはありません |
| Open login | Mở mục đăng nhập | ログインを開く |
| Unlink | Gỡ liên kết | 関連付けを解除 |
| This removes the private email from this vault item. Forwarding and the service account stay unchanged. | Thao tác này gỡ email riêng tư khỏi mục trong vault. Chuyển tiếp thư và tài khoản dịch vụ giữ nguyên. | 保管庫の項目からプライベートメールを削除します。転送とサービスのアカウントは変更されません。 |

Effort P3 thêm khoảng 0,5–1 ngày công; QA case mới nằm trong P5. Native/user data chưa thay đổi.
