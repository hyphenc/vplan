#!/bin/bash
# if you don't properly set up the vars below, this is not gonna work.
set -eu -o pipefail
fullurl="" # full-formed url to untis interface containing http basic auth tokens
apicall="" # curl does a GET request to this url, the new 'data' is appended to this url
classfile="/w/w000XX.htm" # each class has a file
cachefile="./vpold.txt"
compfile="./vpnew.txt"
logfile="./logfile.log"
rssfile="" # path
htmlfile="" # path
rsslinkto=""
rssdate=$(date +%a,-%d-%b-%Y-%T-%z | sed -e 's/-/ /g') # rss lastbuild date
date=$(date +%d.%m)

[[ -f ./lock ]] && echo "lock present" && exit
touch ./lock
rm "$compfile" || true
# logging functions
intolog () {
  echo "$(date)"" -- ""$1" >> "$logfile"
}

logerror () {
  intolog "$1"
  rm ./lock
  exit 1
}

# supplementary functions for rss and html page generation
rssupd() {
  content=$(sed 's/^< /OUT: /i;s/^> /IN: /i' <<< "$1")
  sed -i '/<\/lastBuildDate>/a\\t\t<item>\n\t\t\t<title>'"$date"': '"$content"'<\/title>\n\t\t\t<guid isPermaLink=\"false\">'"$(date +%s)"'<\/guid>\n\t\t\t<link>'"$rsslinkto"'<\/link>\n\t\t\t<description><![CDATA[<p>'"$content"'<\/p>]]><\/description>\n\t\t\t<pubDate>'"$rssdate"'</pubDate>\n\t\t<\/item>' "$rssfile"
  sed -i "s/<lastBuildDate>.*<\/lastBuildDate>/<lastBuildDate>$rssdate<\/lastBuildDate>/gi" "$rssfile"
}

rsscleanup() {
  # VERY hacky way to cleanup up rss items older than 3 days
  mapfile -t guids <<< "$(grep -oP '(?<=guid isPermaLink="false">).*(?=</guid>)' "$rssfile")"
  for guid in "${guids[@]}"; do
    if [ "$guid" -lt $(( $(date +%s) - 259200 )) ]; then # if older than 3 days
      linenum=$(grep -n "$guid" "$rssfile" | sed 's/:.*//gi')
      upperlim=$(( $linenum - 2 ))
      lowerlim=$(( $linenum + 4 ))
      sed -i ''"$upperlim"','"$lowerlim"'d' "$rssfile"
    fi
  done
}

htmlgen() {
  file="$1"
  sorted="$(sed -r 's%^([0-9]{,2}) - ([0-9]{,2})%\1-\2%g' "$file" | sort -hk3 | sed -r 's%^([0-9]{,2})-([0-9]{,2})%\1 - \2%g')"
  mapfile -t items <<< "$sorted"
  sed 18q "$htmlfile" > ./htmlcut
  mv ./htmlcut "$htmlfile"
  for item in "${items[@]}"; do
    date="$(grep -Po '([0-9]{1,2}\.){2}' <<< "$item" | head -n 1)"
    when="$(grep -Po '^[\d - \d\0-9]*' <<< "$item" | sed 's/ $//gi')"
    what="$(grep -Po '(?<='"$when"').*?(?= '"$date"')' <<< "$item" | sed 's/^ //gi')"
    misc="$(grep -Po '(?<='"$date"' ).*?(?=$)' <<< "$item" | sed 's/^...//gi')"
    echo "<div class='"$date" item'><div><p class='when'>"$when"</p></div><div class='info'><p class='what'>"$what"</p><p class='misc'>"$misc"</p></div></div>" >> "$htmlfile"
  done
  echo "</div><div id='ft'> powered by sed and js <a id='code' href='https://github.com/hyphenc/vplan'>code</a><br><br>new info: "$(date '+%d/%m %H:%M:%S')"<br>last run: 00/00 00:00:00</div><script src='./script.js'></script></body></html>" >> "$htmlfile"
}
# 'magic' oneliner that does all the formatting
curl -k -s "$fullurl""$(date +%V)""$classfile" | iconv -f iso-8859-1 -t utf-8 | sed 's/<TR>//gi;/<\/font>.*<\/TD>/d;/<TD.*[<font\align.*].*/d;1,24d;$d;s/Vtr\. ohne Lehrer/EVA/' | head -n -4 | tr '\r\n' '#' | sed 's/<\/TR>/\n/gi;s/##/ /gi' | sed '1d;s/^ //;s/ ---//gi;s/[)\(\:]//gi;s/ \+/ /gi;s/ $//;s/ \+x *$//;s/).*?$//;s/^.*?(//' | sed -r 's/ \+//gi;s/([0-9]{1,2})-([0-9]{1,2})/\1 - \2/gi;s/([0-9]{1,2}[a-z]([, ]{1,6})){1,6}//' | sed -r 's/ x$//g' > "$compfile" || logerror "downloading and formatting data failed"
# add newline and do lookahead for next week, filter dups
sed -i -e '$a\' "$compfile"
curl -k -s "$fullurl""$(( $(date +%V) + 1 ))""$classfile" | iconv -f iso-8859-1 -t utf-8 | sed 's/<TR>//gi;/<\/font>.*<\/TD>/d;/<TD.*[<font\align.*].*/d;1,24d;$d;s/Vtr\. ohne Lehrer/EVA/' | head -n -4 | tr '\r\n' '#' | sed 's/<\/TR>/\n/gi;s/##/ /gi' | sed '1d;s/^ //;s/ ---//gi;s/[)\(\:]//gi;s/ \+/ /gi;s/ $//;s/ \+x *$//;s/).*?$//;s/^.*?(//' | sed -r 's/ \+//gi;s/([0-9]{1,2})-([0-9]{1,2})/\1 - \2/gi;s/([0-9]{1,2}[a-z]([, ]{1,6})){1,6}//' | sed -r 's/ x$//g' >> "$compfile" || logerror "downloading and formatting data failed (lookahead)"
gawk -i inplace '!a[$0]++' "$compfile" || logerror "gawk 'remove duplicates' failed"
if ! $(diff -w "$cachefile" "$compfile" > /dev/null 2>&1 ); then
  mapfile -t newitems <<< $(diff -w "$cachefile" "$compfile" | grep -P "[<\>] *")
  for newitem in "${newitems[@]}"; do
    if [ "$(cat -e <<< "$newitem")" = "$" ]; then continue; fi
    formatted=$(sed 's/%1B%5B32m//gi;s/%20%1B%5B0m%0A//gi' <<< "$newitem") || logerror "couldn't create formatted string for ""$newitem"
    urlencoded=$(jq -sRr @uri <<< "$formatted") || logerror "couldn't urlencode ""$formatted"
    rssupd "$formatted" || intolog "rssupd error"
    curl "$apicall""$urlencoded" || intolog "curl-ing API failed"
    sleep 1
  done
  mv "$compfile" "$cachefile"
  htmlgen "$cachefile" || intolog "htmlgen error"
  rsscleanup || intolog "rss feed cleanup failed"
fi
# cleanup
[[ -f "$compfile" ]] && rm "$compfile"
rm ./lock
# update 'last run' on site
sed -r -i "s;last run: [0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2};last run: $(date '+%d/%m %H:%M:%S;i')" "$htmlfile"
intolog "exit 0: SUCCESS"
