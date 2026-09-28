#!/usr/bin/env bash
# tool-stats 报表（jq 聚合）
# 用法：
#   report.sh              # 当月
#   report.sh 2026-09      # 指定月
#   report.sh 2026-09-28   # 指定日
# 数据源：~/.local/share/opencode/tool-stats/YYYY-MM.jsonl
# 注：时间列为 UTC（jq todate 限制），其余为本地数据。
set -euo pipefail

DATA_DIR="$HOME/.local/share/opencode/tool-stats"
KEY="${1:-$(date +%Y-%m)}"
if [[ "$KEY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  MONTH="${KEY%-*}"
  FROM="$(date -d "$KEY 00:00:00" +%s)000"
  TO="$(date -d "$KEY 23:59:59" +%s)000"
else
  MONTH="$KEY"
  FROM=0
  TO=9999999999999
fi
FILE="$DATA_DIR/$MONTH.jsonl"
if [ ! -f "$FILE" ]; then
  echo "无数据：$FILE"
  exit 0
fi

echo "== 工具统计（$KEY）=="
jq -sr --argjson from "$FROM" --argjson to "$TO" '
  map(select(.ts >= $from and .ts <= $to)) as $r
  | "总量: \($r | length)",
    "── 次数排名（失败/均耗时取有记录项）──",
    ( $r | group_by(.tool)
      | map({
          tool: .[0].tool,
          n: length,
          fail: ([.[] | select(.status == "error")] | length),
          avg: ([.[] | select(.ms != null) | .ms] | if length > 0 then (add / length | round) else null end)
        })
      | sort_by(-.n)
      | .[] | "\(.n)\t\(.tool)\t失败 \(.fail)\t均 \(.avg // "-") ms" ),
    "── bash 命令词 top 20 ──",
    ( [$r[] | select(.w) | .w] | group_by(.)
      | map({ w: .[0], n: length }) | sort_by(-.n) | .[0:20][]
      | "\(.n)\t\(.w)" )
' "$FILE"

echo
echo "── 最慢 10 次调用（时间 UTC）──"
jq -sr --argjson from "$FROM" --argjson to "$TO" '
  map(select(.ts >= $from and .ts <= $to and .ms != null))
  | sort_by(-.ms) | .[0:10][]
  | "\(.ms)ms\t\(.tool)\t\(.ts / 1000 | todate)\t\(.w // "")"
' "$FILE"
