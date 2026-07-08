#!/usr/bin/env python3
"""update_special_issues.py — IEEE SPS 'Special Issue Deadlines' 페이지를 파싱해
data/special_issues.json 을 갱신한다. GitHub Actions(calendar-sync.yml)에서 매주 실행.

설계 원칙:
- 파싱 실패(항목 0개)이면 기존 auto 항목을 유지하고 경고만 남긴다 (데이터 소실 방지).
- "source":"manual" 항목은 절대 건드리지 않는다 (TCSVT/MDPI 등 수동 등록용).
- 마감이 14일 이상 지난 auto 항목은 제거한다.
"""
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from bs4 import BeautifulSoup

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "data" / "special_issues.json"
SRC = "https://signalprocessingsociety.org/publications-resources/special-issue-deadlines"

# 제목 → 저널 약칭 매핑 (앞부분 매칭, 순서 중요)
JOURNAL_PREFIXES = [
    ("IEEE TMM", "TMM"),
    ("IEEE Transactions on Multimedia", "TMM"),
    ("IEEE TIP", "TIP"),
    ("IEEE Transactions on Image Processing", "TIP"),
    ("IEEE JSTSP", "JSTSP"),
    ("IEEE Journal of Selected Topics in Signal Processing", "JSTSP"),
    ("IEEE Journal on Selected Topics in Signal Processing", "JSTSP"),
    ("IEEE SPM", "SPM"),
    ("IEEE Signal Processing Magazine", "SPM"),
    ("IEEE SPL", "SPL"),
    ("IEEE OJSP", "OJSP"),
    ("IEEE TASLP", "TASLP"),
    ("IEEE TCI", "TCI"),
    ("IEEE TIFS", "TIFS"),
    ("IEEE TSIPN", "TSIPN"),
    ("IEEE TSP", "TSP"),
]

# ISPL 관련성 키워드 (제목 소문자 매칭)
RELEVANT_KW = [
    "video", "image", "compression", "coding", "codec", "multimedia",
    "3d", "gaussian", "splat", "render", "point cloud", "immersive",
    "vision", "restoration", "super-resolution", "generative", "neural field",
    "world simulation", "quality assessment", "streaming",
]

MONTHS = {m.lower(): i + 1 for i, m in enumerate(
    ["January", "February", "March", "April", "May", "June",
     "July", "August", "September", "October", "November", "December"])}
for abbr in list(MONTHS):
    MONTHS[abbr[:3]] = MONTHS[abbr]

DDL_RE = re.compile(
    r"Submission\s+deadline[\s:*]*"         # 라벨 (굵게 표기 '**' 잔재 허용)
    r"(?:extended\s*(?:to)?[\s:*]*)?"       # 'extended to' 변형 허용
    r"(\d{1,2})[-\s]+([A-Za-z]+)[-\s]+(\d{4})", re.I)


def parse_ddl(text: str):
    m = DDL_RE.search(text)
    if not m:
        return None
    day, mon, year = m.group(1), m.group(2).lower(), m.group(3)
    if mon not in MONTHS:
        return None
    return f"{year}-{MONTHS[mon]:02d}-{int(day):02d}"


def journal_of(title: str) -> str:
    for prefix, ab in JOURNAL_PREFIXES:
        if title.lower().startswith(prefix.lower()):
            return ab
    return title.split()[0] if title else "?"


def clean_title(title: str, journal: str) -> str:
    """제목에서 'IEEE TMM ' 같은 저널 접두를 제거해 카드 제목만 남긴다."""
    for prefix, ab in JOURNAL_PREFIXES:
        if ab == journal and title.lower().startswith(prefix.lower()):
            return title[len(prefix):].lstrip(" :-–")
    return title


def is_relevant(title: str) -> bool:
    t = title.lower()
    return any(k in t for k in RELEVANT_KW)


def fetch_items():
    resp = requests.get(SRC, timeout=60, headers={"User-Agent": "ispl-dashboard-bot/1.0"})
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    items, seen = [], set()
    # 이벤트 링크 앵커 기준으로 블록 탐색
    for a in soup.select('a[href*="/events/"]'):
        href = a.get("href", "")
        title = a.get_text(" ", strip=True)
        if not title or len(title) < 15:          # 이미지 링크/짧은 링크 제외
            continue
        url = href if href.startswith("http") else "https://signalprocessingsociety.org" + href
        if url in seen:
            continue
        # 앵커 뒤쪽 텍스트에서 마감일 탐색 (다음 이벤트 전까지 대략 40개 텍스트 노드)
        tail = " ".join(t.strip() for t in a.find_all_next(string=True, limit=40))
        ddl = parse_ddl(tail)
        if not ddl:
            continue
        seen.add(url)
        journal = journal_of(title)
        items.append({
            "journal": journal,
            "title": clean_title(title, journal),
            "ddl": ddl,
            "url": url,
            "relevant": is_relevant(title),
            "source": "sps-auto",
        })
    return items


def main():
    old = {"items": []}
    if OUT.exists():
        try:
            old = json.loads(OUT.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"WARN: 기존 JSON 파싱 실패, 새로 생성: {e}", file=sys.stderr)

    manual = [x for x in old.get("items", []) if x.get("source") == "manual"]
    old_auto = [x for x in old.get("items", []) if x.get("source") != "manual"]

    try:
        auto = fetch_items()
    except Exception as e:
        print(f"ERROR: SPS 페이지 fetch 실패 — 기존 항목 유지: {e}", file=sys.stderr)
        auto = old_auto

    if not auto and old_auto:
        print("WARN: 파싱 결과 0건 — 페이지 구조 변경 가능성. 기존 auto 항목 유지.", file=sys.stderr)
        auto = old_auto

    # 기존 auto 항목의 수동 보강 필드(note, pub, relevant 수동조정) 보존
    old_by_url = {x.get("url"): x for x in old_auto}
    for it in auto:
        prev = old_by_url.get(it["url"])
        if prev:
            for k in ("note", "pub"):
                if prev.get(k) and not it.get(k):
                    it[k] = prev[k]
            if "relevant" in prev:           # 사람이 고친 relevant 우선
                it["relevant"] = prev["relevant"]

    cutoff = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%d")
    auto = [x for x in auto if x.get("ddl", "9999") >= cutoff]

    data = {
        "last_checked": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": SRC,
        "items": sorted(auto + manual, key=lambda x: x.get("ddl", "9999-99-99")),
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK: auto {len(auto)}건 + manual {len(manual)}건 → {OUT}")


if __name__ == "__main__":
    main()
