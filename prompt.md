Tôi muốn tạo 1 cái app giao diện đơn giản thôi, dùng để học tiếng anh, các tính năng bao gồm:
Luyện tập tiếng anh phản xạ: Gồm các flow:
1. Chuẩn bị:
Chọn chủ đề: tick vào các chủ đề fetch được (firebase)
Chọn level: A1 A2, B1, B2, C1, C2 
Chọn số lượng câu hỏi: Từ 1 đến 100: question_count
Chọn thời gian đếm ngược trước khi ghi âm: {t}
Chọn thời gian trả lời tối đa để tự ngắt: {d}
Có phát lại hay không: {r}
2. Bắt đầu: Flow
Khi nhấn bắt đầu: Đồng hồ sẽ đếm ngược 3 giây
Câu hỏi hiện ra: đồng hồ đếm ngược {t} giây - sau đó bắt đầu ghi âm
Thời gian ghi âm là {d}:
+ Hết {d} giây thì tự ngắt
+ Ngoài ra có 1 cái nút stop siêu to ở dưới màn hình để chủ động ngắt ghi âm
Phát lại đoạn ghi âm đó nếu {r}=true
Đồng hồ lại đếm ngược 3 giây để chuyển sang câu mới (lặp lại cho đến khi hết {question_count})
ở trên appbar lúc nào cũng có nút Pause/resume, stop. nhấn stop thì phải confirmation
* Note:
- Mỗi một lượt chơi đều được lưu lại và có thể nghe lại:
+ Excersize history: Sẽ list ra các lần học
khi nhấn vào exercise: Sẽ hiện thêm list các câu hỏi đã hỏi và đoạn ghi âm tương ứng, nhấn vào câu nào sẽ phát tiếng ghi âm của câu đó, mục đích là thật dễ dàng để nghe lại xem mình đã nói gì
Lịch sử học và bản ghi âm sẽ lưu local
Lưu liên tục theo quá trình học chứ không phải đợi học xong mới lưu, làm sao mà khi thoát app bất ngờ, vào lại vẫn thấy được history

List câu hỏi sẽ lưu firebase: Cấu trúc của câu hỏi sẽ là:
{
    "id":"",
    "content":"Nội dung câu hỏi",
    "subject":"chủ đề",
    "level": A1 đến C2,
    "created_at": ngày tạo
}
Sau khi làm app hãy cho tôi đoạn prompt để có thể Add vào bất kỳ AI nào để tạo ra data câu hỏi.
Khi tạo chủ đề hãy input vào prompt các chủ đề muốn tạo: Chỉ khoảng 10 chủ đề phổ biến tổng quát nhất thôi, như đời sống, du lịch, thể thao, ẩm thực,...

Làm thêm 1 tính năng là import file json để thêm vào ngân hàng câu hỏi.
Format là json list như trên (luôn phải theo format này, cái prompt ở trên cũng phải bắt các AI khác gen ra data như thế này), nhưng mỗi item chỉ cần có content, subject và level thôi:
``` json
{
    "data"=[
        {
            "content":"What's your name?",
            "subject":"Daily",
            "level":"A1"
        },
        {

        },
        ...
    ]
}
```

Thông tin app:
làm bằng flutter, app càng nhanh gọn càng tốt, càng ít code, giao diện đơn giản, cỡ chữ to, font đẹp, màu mè 1 tí
Như hoạt hình 
AI tự quyết định mọi thứ, không cần hỏi lại
Nhanh nhất có thể, ít code nhất có thể
Nhưng docs phải có đủ, 