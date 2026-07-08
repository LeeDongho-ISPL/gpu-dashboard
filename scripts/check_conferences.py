#!/usr/bin/env python3
"""check_conferences.py — data/conferences.json 을 커뮤니티 유지 ccf-deadlines
(https://github.com/ccfddl/ccf-deadlines) YAML과 대조해 불일치를 리포트한다.

- 자동 수정하지 않는다. 불일치는 cal_sync_report.json 으로 남기고,
  워크플로가 GitHub Issue 를 생성해 사람이 확인 후 conferences.json 을 고친다.
- ccfddl 에 없는 학회/연도는 조용히 건너뛴다 (리포트의 skipped 에 기록).
"""
import json
import sys
from pathlib import Path

import requests
import yaml

REPO = Path(__file__).resolve().parent.parent
CONF_JSON = REPO / "data" / "conferences.json"
REPORT = REPO / "cal_sync_report.json"   # .gitignore 대상 (커밋 안 함)

API_TREE = "https://api.github.com/repos/ccfddl/ccf-deadlines/git/trees/main?recursive=1"
RAW_BASE = "https://raw.githubusercontent.com/ccfddl/ccf-deadlines/main/"

# 대시보드 venue → ccfddl 파일명(소문자) 후보
VENUE_IDS = {
    "CVPR": ["cvpr"],
    "ICCV": ["iccv"],
    "ECCV": ["eccv"],
    "NeurIPS": ["neurips", "nips"],
    "ICML": ["icml"],
    "ICLR": ["iclr"],
    "AAAI": ["aaai"],
    "3DV": ["3dv", "threedv"],
    "SIGGRAPH": ["siggraph"],
    "SIGGRAPH Asia": ["siggraphasia", "siggraph-asia"],
}


def gh_get(url):
    r = requests.get(url, timeout=60, headers={"User-Agent": "ispl-dashboard-bot/1.0"})
    r.raise_for_status()
    return r


def find_yaml_paths():
    tree = gh_get(API_TREE).json().get("tree", [])
    paths = {}
    for node in tree:
        p = node.get("path", "")
        if p.startswith("conference/") and p.endswith(".yml"):
            stem = p.rsplit("/", 1)[-1][:-4].lower()
            paths.setdefault(stem, p)
    return paths


def ccf_deadline_for(yml_obj, year):
    """ccfddl YAML 구조에서 해당 연도 마감일(YYYY-MM-DD)을 추출."""
    entries = yml_obj if isinstance(yml_obj, list) else [yml_obj]
    for entry in entries:
        for conf in entry.get("confs", []) or []:
            if conf.get("year") != year:
                continue
            best = None
            for tl in conf.get("timeline", []) or []:
                d = str(tl.get("deadline", "")).strip()
                if not d or d.upper() == "TBD":
                    continue
                day = d.split()[0]
                if len(day) == 10 and day[4] == "-":
                    # 여러 라운드가 있으면 가장 늦은 마감을 대표값으로
                    if best is None or day > best:
                        best = day
            return best
    return None


def main():
    ours = json.loads(CONF_JSON.read_text(encoding="utf-8"))
    try:
        paths = find_yaml_paths()
    except Exception as e:
        print(f"ERROR: ccf-deadlines 트리 조회 실패: {e}", file=sys.stderr)
        REPORT.write_text(json.dumps({"error": str(e), "mismatches": []}, ensure_ascii=False, indent=2))
        return

    cache, mismatches, skipped = {}, [], []
    for item in ours:
        venue, year = item["venue"], item["year"]
        ids = VENUE_IDS.get(venue)
        if not ids:
            skipped.append(f"{venue} {year} (매핑 없음)")
            continue
        path = next((paths[i] for i in ids if i in paths), None)
        if not path:
            skipped.append(f"{venue} {year} (ccfddl에 파일 없음)")
            continue
        if path not in cache:
            try:
                cache[path] = yaml.safe_load(gh_get(RAW_BASE + path).text)
            except Exception as e:
                skipped.append(f"{venue} {year} (fetch 실패: {e})")
                cache[path] = None
                continue
        if cache[path] is None:
            continue
        ccf = ccf_deadline_for(cache[path], year)
        if ccf is None:
            skipped.append(f"{venue} {year} (ccfddl 미공지/TBD)")
            continue
        if ccf != item["ddl"]:
            mismatches.append({
                "venue": venue, "year": year,
                "ours": item["ddl"], "ours_cfd": item.get("cfd", "?"),
                "ccfddl": ccf,
                "severity": "high" if item.get("cfd") == "confirmed" else "info",
            })

    REPORT.write_text(json.dumps(
        {"mismatches": mismatches, "skipped": skipped}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")
    print(f"검사 완료: 불일치 {len(mismatches)}건, 건너뜀 {len(skipped)}건")
    for m in mismatches:
        print(f"  - {m['venue']} {m['year']}: ours {m['ours']} ({m['ours_cfd']}) vs ccfddl {m['ccfddl']}")


if __name__ == "__main__":
    main()
