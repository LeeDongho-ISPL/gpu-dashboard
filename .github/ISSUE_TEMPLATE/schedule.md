---
name: GPU/서버 예약
about: 서버 사용 스케줄을 등록합니다
title: "[Schedule] "
labels: schedule
---

```json
{
  "date": "2026-04-10",
  "user": "이름",
  "server": "NIPA_server",
  "start_time": "09:00",
  "end_time": "18:00",
  "gpus": [],
  "note": "실험 내용"
}
```

**서버 목록:**
- `NIPA_server` : GPU 1× 80GB
- `ISPL` : GPU 8× 48GB (gpus 필드에 사용할 GPU 번호 입력, 예: [0, 1, 2])
- `CPU1` ~ `CPU4` : CPU 서버

**gpus 필드:** ISPL 서버 사용 시 GPU 인덱스 배열 (0~7). 다른 서버는 빈 배열.
