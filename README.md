# ISPL Server Dashboard

연구실 GPU/CPU 서버 실시간 모니터링 + 스케줄 관리 대시보드.
GitHub Pages로 호스팅, NIPA 서버에서 cron으로 자동 수집.

## 서버 구성

| 이름 | 타입 | GPU |
|------|------|-----|
| NIPA_server | GPU | 1x 80GB |
| ISPL | GPU | 8x 48GB |
| CPU1 ~ CPU4 | CPU | - |

> 서버 IP/포트 정보는 보안을 위해 `scripts/servers.conf`에 저장되며, `.gitignore`로 커밋되지 않습니다.

## 설정 방법

### 1. NIPA 서버에 레포 클론

```bash
cd ~
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

NIPA 서버에서 GitHub에 push할 수 있도록 설정합니다:

```bash
git config user.name "ISPL Dashboard Bot"
git config user.email "dashboard@ispl.local"
```

GitHub Personal Access Token 또는 SSH deploy key를 설정하세요.

### 5. Cron 등록

```bash
chmod +x scripts/nipa_cron.sh scripts/collect_status.sh

# 1분마다 수집
crontab -e
# 아래 줄 추가:
* * * * * /home/ispl/gpu-dashboard/scripts/nipa_cron.sh >> /home/ispl/gpu-dashboard/logs/cron.log 2>&1
```

### 6. GitHub Pages 활성화

Repository > Settings > Pages:
- Source: Deploy from a branch
- Branch: `main` / `(root)`

## 스케줄 등록

- **GitHub Issue**: Issues > New Issue > "GPU/서버 예약" 템플릿
- **직접 편집**: `data/schedule.json` 수정 후 커밋
- **대시보드 UI**: "스케줄 관리" 탭

## 파일 구조

```
gpu-dashboard/
├── index.html                       # 대시보드 (GitHub Pages)
├── data/
│   ├── server_status.json           # 서버 상태 (자동 업데이트)
│   └── schedule.json                # 스케줄 데이터
├── scripts/
│   ├── collect_status.sh            # SSH 수집 스크립트
│   ├── nipa_cron.sh                 # Cron 래퍼 (수집+push)
│   ├── servers.conf.example         # 설정 파일 예시
│   └── servers.conf                 # 실제 설정 (.gitignore)
├── .github/
│   ├── workflows/
│   │   ├── collect.yml              # Actions 백업용 (비활성)
│   │   └── schedule-manage.yml      # Issue → 스케줄 자동 등록
│   └── ISSUE_TEMPLATE/
│       └── schedule.md
├── .gitignore
└── README.md
```
