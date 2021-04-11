#!/bin/sh

export POSIXLY_CORRECT=yes
export LC_NUMERIC=en_US.UTF-8

print_help()
{
  echo "Usage: tradelog [-h|--help] "
  echo "       tradelog [FILTER] [COMMAND] [LOG [LOG2 [...]]"
  echo ""
  echo "Filters:"
  echo "  -a DATETIME          after: records that are only AFTER this datetime (this datetime excluded) are used"
  echo "                       DATETIME is format is YYYY-MM-DD HH:MM:SS"
  echo "  -b DATETIME          before: records that are only BEFORE this datetime (this datetime excluded) are used"
  echo "                       DATETIME is format is YYYY-MM-DD HH:MM:SS"
  echo "  -t TICKER            records that corresponds to the TICKER are used"
  echo "  -w WIDTH             declares width of a graph when drawing graph"
  echo "  -h, --help           prints this help text"
  echo ""
  echo "Commands:"
  echo "  list-tick            prints list of tickers"
  echo "  profit               prints total profit from closed positions"
  echo "  pos                  prints values of currently held positions ordered from highest value"
  echo "  last-price           prints last known price for every ticker"
  echo "  hist-ord             prints histogram  of number of transactions to ticker"
  echo "  graph-pos            prints graph of values of held positions for ticker"
  echo ""
  echo "Script can work with any number of files. Script will use them in order as they were received. Logs can be read"
  echo "from .gz file."
}

COMMAND=""
WIDTH=""
LOG_FILES=""
GZ_LOG_FILES=""
TICKERS=""
AFTER_TIME="0000-00-00 00:00:00"
BEFORE_TIME="9999-12-31 23:59:59"

read_input()
{
  if [ "$GZ_LOG_FILES" = "" ]; then
    cat $LOG_FILES
  else
    gzip -d -c $GZ_LOG_FILES | cat $LOG_FILES -
  fi
}

tick_filter()
{
  grep -E "^.*;($TICKERS)"
}

time_filter()
{
  awk -F ';' "{if (\$1 > \"$AFTER_TIME\" && \$1 < \"$BEFORE_TIME\") print \$0;}"
}

read_filtered()
{
  read_input | time_filter | tick_filter
}

list_tick()
{
  read_filtered | cut -d ';' -f2 -s | sort | uniq
}

profit()
{
  read_filtered | sed 's/buy;/buy;-/' | awk -F ';' '{printf "%.2f\n", $4 * $6}' | awk '{sum+=$1} END {printf "%.2f\n",sum}'
}

ticker_value()
{
  awk -F ';' '{
    if ($3 == "buy") {tickrs[$2]+=$6} else {tickrs[$2]-=$6};
    tickrs_price[$2]=$4;
  }
  END { for (i in tickrs) {printf "%.2f;%s\n",tickrs[i]*tickrs_price[i],i}}'
}

pos()
{
  HIGHEST_TICKER=$(read_filtered | ticker_value  | cut -d ';' -f1 -s \
  | awk '{printf "%i\n",length($0)}' | sort -g | tail -n 1)

  read_filtered | ticker_value | sort -n -r \
  | awk -F ';' -v highest_ticker="$HIGHEST_TICKER" '{printf "%-10s: %*.2f\n",$2,highest_ticker,$1}'
}

last_price()
{
  HIGHEST_TICKER=$(read_filtered | sort \
  | awk -F ';' '{tickrs[$2]=$4} END {for (i in tickrs) {printf "%.2f;%s\n",tickrs[i],i}}' \
  | cut -d ';' -f1 -s | awk '{printf "%i\n",length($0)}' | sort -g | tail -n 1)

  read_filtered | sort | awk -F ';' '{tickrs[$2]=$4} END {for (i in tickrs) {printf "%.2f;%s\n",tickrs[i],i}}' \
  | awk -F ';' -v highest_ticker="$HIGHEST_TICKER" '{printf "%-10s: %*.2f\n",$2,highest_ticker,$1}' | sort
}

ord_print()
{
  awk -F ';' -v width=$WIDTH -v highest_ticker="$HIGHEST_TICKER" '{
    printf "%-10s: ", $1;
    for (i = 1; i <= ($2/(highest_ticker/width)); ++i) printf "#";
    printf "\n";
  };'
}

hist_ord()
{
  HIGHEST_TICKER=$(read_filtered | awk -F ';' '{tickrs[$2]+= 1}
  END {for (i in tickrs) {printf "%.0f;%s\n",tickrs[i],i}}' | cut -d ';' -f1 -s | sort -n | tail -n 1)

  if [ "$WIDTH" = "" ]; then
    WIDTH=$HIGHEST_TICKER
  fi

read_filtered | awk -F ';' '{tickrs[$2]+= 1} END {for (i in tickrs) {printf "%s;%.0f\n",i,tickrs[i]}}' | ord_print | sort
}

graph_print()
{
  awk -F ';' -v width="$WIDTH" -v highest_ticker="$HIGHEST_TICKER" '{
    printf "%-10s: ", $2;
    if ($1 < 0) { for (i=1; i <= -($1/(highest_ticker/width)); i++) printf "!";};
    if ($1 > 0) { for (i=1; i <= ($1/(highest_ticker/width)); i++) printf "#";};
    printf "\n";
  }'
}

graph_pos()
{
  HIGHEST_TICKER=$(read_filtered | ticker_value | awk '{if ($1 < 0) {printf "%.2f\n",-$1} else {printf "%.2f\n", $1}}' | sort -n | tail -n 1)

  if [ "$WIDTH" = "" ]; then
    WIDTH=1000
  fi

  read_filtered | ticker_value | graph_print | sort
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  list-tick | pos | profit | last-price | hist-ord | graph-pos)
    COMMAND="$1"
    shift
    ;;

  -h)
    print_help
    exit 0
    ;;

  -w)
    WIDTH="$2"
    shift
    shift
    ;;

  -t)
    if [ "$TICKERS" = "" ]; then
      TICKERS="$2"
    else
      TICKERS="$TICKERS|$2"
    fi
    shift
    shift
    ;;

  -a)
    AFTER_TIME="$2"
    shift
    shift
    ;;

  -b)
    BEFORE_TIME="$2"
    shift
    shift
    ;;

  *.log)
    LOG_FILES="$1"
    shift
    ;;

  *.gz)
    GZ_LOG_FILES="$1"
    shift
    ;;

  *)
    exit 1
    ;;
  esac
done

case "$COMMAND" in
  "list-tick")
    list_tick
    ;;

  "profit")
    profit
    ;;

  "pos")
    pos
    ;;

  "last-price")
    last_price
    ;;

  "hist-ord")
    hist_ord
    ;;

  "graph-pos")
    graph_pos "$WIDTH"
    ;;

  "")
    read_filtered
    ;;

  *)
    exit 1
    ;;
esac
