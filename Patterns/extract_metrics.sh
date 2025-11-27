#!/bin/bash
cd /mnt/c/newTrader9/Patterns

echo "Pattern|Year|NetProfit|ProfitFactor|TotalTrades|WinRate"

for f in *_202*.html; do
  pattern=$(echo "$f" | sed 's/_202[0-9]\.html//')
  year=$(echo "$f" | grep -oE '202[0-9]')
  content=$(cat "$f" | sed 's/\x00//g')

  net_profit=$(echo "$content" | grep -A1 "Total Net Profit:" | tail -1 | grep -oE "[-0-9]+\.[0-9]+" | head -1)
  profit_factor=$(echo "$content" | grep -A1 "Profit Factor:" | tail -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
  total_trades=$(echo "$content" | grep -A1 "Total Trades:" | tail -1 | grep -oE "[0-9]+" | head -1)
  win_rate=$(echo "$content" | grep -A1 "Profit Trades" | tail -1 | grep -oE "[0-9]+\.[0-9]+%" | head -1)

  echo "$pattern|$year|$net_profit|$profit_factor|$total_trades|$win_rate"
done
