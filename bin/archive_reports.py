"""Rotate daily reports using their reporting date in UTC+8."""

import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path


REPORTS = Path(__file__).resolve().parents[1] / "reports"
TODAY = datetime.now(timezone(timedelta(hours=8))).date()


def label_date(label):
    match = re.fullmatch(r"(?:backfill-)?(\d{4}-\d{2}-\d{2})", label)
    if match:
        return date.fromisoformat(match[1])


def destination(name, day):
    previous = TODAY.replace(day=1) - timedelta(days=1)
    cutoff = previous.replace(day=min(TODAY.day, previous.day))
    if day < cutoff:
        return REPORTS / "archive" / day.strftime("%Y-%m") / name
    return REPORTS / name


def rotate():
    for report in REPORTS.glob("*.md"):
        day = label_date(report.stem)
        if day is None:
            # Custom labels carry their creation date through fresh checkouts.
            with report.open(encoding="utf-8") as stream:
                marker = re.search(r"<!-- report-date: (\d{4}-\d{2}-\d{2}) -->\s*$", stream.read())
            if not marker:
                raise ValueError(f"missing reporting date in {report}")
            day = date.fromisoformat(marker[1])
        target = destination(report.name, day)
        if target != report:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                raise FileExistsError(f"archive already contains {target}")
            report.rename(target)


if __name__ == "__main__":
    rotate()
    if len(sys.argv) > 1:
        label = sys.argv[1]
        day = label_date(label) or TODAY
        target = destination(f"{label}.md", day)
        target.parent.mkdir(parents=True, exist_ok=True)
        print(target.relative_to(REPORTS.parent).as_posix())
