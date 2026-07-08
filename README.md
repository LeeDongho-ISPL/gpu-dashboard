# ISPL Server Dashboard

연구실 GPU/CPU 서버 실시간 모니터링 + 스케줄 관리 대시보드.
GitHub Pages로 호스팅, 연구실 Windows PC에서 `run_collector.sh` 루프로 자동 수집 (15분 간격).

> NIPA_server는 2026-07 지원 종료로 제거되었습니다.

## 서버 구성

| 이름 | 타입 | GPU |
|------|------|-----|
| ISPL | GPU | 8x 48GB |
| CPU1 ~ CPU4 | CPU | - |

> 서버 IP/포트 정보는 보안을 위해 `scripts/servers.conf`에 저장되며, `.gitignore`로 커밋되지 않습니다.

## 설정 방법

### 1. 수집용 PC에 레포 클론

```bash
git clone https://github.com/LeeDongho-ISPL/gpu-dashboard.git
cd gpu-dashboard
```

### 2. 서버 설정 파일 생성

```bash
cp scripts/servers.conf.example scripts/servers.conf
nano scripts/servers.conf  # 실제 IP 입력
```

### 3. SSH 키 설정

각 서버에 비밀번호 없이 접속할 수 있도록 SSH 키를 등록합니다:

```bash
# 키가 없으면 생성
ssh-keygen -t ed25519 -N ""

# 각 서버에 공개키 등록
ssh-copy-id -p <PORT> <USER>@<SERVER_IP>
```

### 4. Git push 설정

수집용 PC에서 GitHub에 push할 수 있도록 설정합니다:

```bash
git config user.name "ISPL Dashboard Bot"
git config user.email "dashboard@ispl.local"
```

GitHub Personal Access Token 또는 SSH deploy key를 설정하세요.

### 5. 수집 루프 실행 (Windows / Git Bash)

```bash
# 직접 실행 (15분 간격 무한 루프)
bash scripts/run_collector.sh

# 또는 백그라운드 실행 (창 없이)
# gpu-collector.bat 더블클릭 (내부에서 run_collector.sh 호출)
```

리눅스 서버에서 cron으로 돌리려면 `crontab -e`에 `collect_status.sh` + push를 감싼 래퍼를 등록하면 됩니다.

### 6. GitHub Pages 활성화

Repository > Settings > Pages:
- Source: Deploy from a branch
- Branch: `main` / `(root)`

## 스케줄 등록

- **GitHub Issue**: Issues > New Issue > "GPU/서버 예약" 템플릿
- **직접 편집**: `data/schedule.json` 수정 후 커밋
- **대시보드 UI**: "스케줄 관리" 탭

## 학회 캘린더 · 스페셜 이슈

- 학회 마감 데이터: `data/conferences.json` (index.html의 배열은 fetch 실패 시 fallback 전용)
- 스페셜 이슈 데이터: `data/special_issues.json`
  - IEEE SPS 공식 마감 페이지를 **매주 월요일** Actions(`calendar-sync.yml`)가 자동 수집
  - TCSVT·MDPI 등 자동 수집이 안 되는 저널은 `"source": "manual"`로 직접 추가 (자동 갱신에서 보존됨)
- 검증: 같은 워크플로가 [ccf-deadlines](https://github.com/ccfddl/ccf-deadlines)와 대조해 불일치 시 `cal-sync` 라벨 Issue를 자동 생성 → 공식 사이트 확인 후 수동 반영
- 스케줄 관리 탭 캘린더에도 학회·스페셜 이슈 마감이 뱃지로 표시되고, 마감 30일 이내 항목은 상단 배너에 노출

## 파일 구조

```
gpu-dashboard/
├── index.html                       # 대시보드 (GitHub Pages)
├── data/
│   ├── server_status.json           # 서버 상태 (자동 업데이트)
│   ├── schedule.json                # 스케줄 데이터
│   ├── conferences.json             # 학회 마감 데이터 (주간 대조 검증)
│   └── special_issues.json          # 저널 스페셜 이슈 (주간 자동 수집)
├── gpu-collector.bat                # Windows 백그라운드 실행기
├── scripts/
│   ├── collect_status.sh            # SSH 수집 스크립트
│   ├── run_collector.sh             # 수집 루프 (수집+push, 15분 간격)
│   ├── update_special_issues.py     # SPS 스페셜 이슈 파서 (Actions)
│   ├── check_conferences.py         # ccf-deadlines 대조 (Actions)
│   ├── servers.conf.example         # 설정 파일 예시
│   └── servers.conf                 # 실제 설정 (.gitignore)
├── .github/
│   ├── workflows/
│   │   ├── schedule-manage.yml      # Issue → 스케줄 자동 등록
│   │   └── calendar-sync.yml        # 주간 스페셜이슈 수집 + 캘린더 검증
│   └── ISSUE_TEMPLATE/
│       └── schedule.md
├── .gitignore
└── README.md
```
