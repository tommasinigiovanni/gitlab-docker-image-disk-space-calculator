#!/bin/bash

# CONFIGURATION
TOKEN="YOUR_TOKEN"
GITLAB_HOST="YOUR_GITLAB_HOST"
PER_PAGE=100
LIMIT=0


# Default options
OUTPUT_MODE="terminal"
OUTPUT_FILE=""
INCLUDE_ARCHIVED=false
VISIBILITY="all"
QUIET_MODE=false
GROUP_PATH=""
SORT_BY_SIZE=false
DEBUG=false

print_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "This script fetches Docker image tag sizes from GitLab and outputs summary."
  echo ""
  echo "Options:"
  echo "  --output terminal|pdf|csv   Output destination (default: terminal)"
  echo "  --file FILE                 Output file for pdf/csv formats"
  echo "  --include-archived          Include archived projects"
  echo "  --visibility VALUE          Filter projects by visibility (private|internal|public|all)"
  echo "  --quiet                     Suppress log output, show stats only"
  echo "  --group GROUP_PATH          Process only projects in this group"
  echo "  --sort-by-size              Sort output by size"
  echo "  --debug                     Print debug information"
  echo "  -h, --help                  Show this help message"
  exit 0
}

validate_output_mode() {
  case "$1" in
    terminal|pdf|csv) return 0 ;;
    *) echo "Error: output mode must be one of: terminal, pdf, csv" >&2; exit 1 ;;
  esac
}

validate_visibility() {
  case "$1" in
    private|internal|public|all) return 0 ;;
    *) echo "Error: visibility must be one of: private, internal, public, all" >&2; exit 1 ;;
  esac
}

log() {
  if [ "$QUIET_MODE" = false ]; then
    if [ "$OUTPUT_MODE" = "pdf" ]; then
      # Add two spaces at the end of each line for markdown line breaks
      echo "$1  " >> "$LOGFILE"
      # Add an extra newline after each log entry
      echo "" >> "$LOGFILE"
    elif [ "$OUTPUT_MODE" = "terminal" ]; then
      echo "$1"
    fi
  fi
}

write_output() {
  if [ "$OUTPUT_MODE" = "csv" ]; then
    echo "$1" >> "$OUTPUT_FILE"
  fi
}

check_dependencies() {
  for cmd in jq bc curl; do
    if ! command -v $cmd >/dev/null 2>&1; then
      echo "Missing command: $cmd" >&2
      exit 1
    fi
  done
  if [ "$OUTPUT_MODE" = "pdf" ]; then
    if ! command -v pandoc >/dev/null 2>&1; then
      echo "Missing command: pandoc (required for PDF export)" >&2
      exit 1
    fi
    # Check for at least one PDF engine
    if command -v weasyprint >/dev/null 2>&1; then
      PDF_ENGINE="weasyprint"
    elif command -v pdflatex >/dev/null 2>&1; then
      PDF_ENGINE="pdflatex"
    else
      echo "Error: No PDF engine found. Please install one of: weasyprint or pdflatex" >&2
      echo "For example:" >&2
      echo "  - Using pip: pip install weasyprint" >&2
      echo "  - macOS: brew install pandoc" >&2
      echo "  - Ubuntu/Debian: sudo apt-get install python3-weasyprint" >&2
      echo "  - Fedora: sudo dnf install python3-weasyprint" >&2
      exit 1
    fi
  fi
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --output) validate_output_mode "$2"; OUTPUT_MODE="$2"; shift;;
    --file) OUTPUT_FILE="$2"; shift;;
    --include-archived) INCLUDE_ARCHIVED=true;;
    --visibility) validate_visibility "$2"; VISIBILITY="$2"; shift;;
    --quiet) QUIET_MODE=true;;
    --group) GROUP_PATH="$2"; shift;;
    --sort-by-size) SORT_BY_SIZE=true;;
    --debug) DEBUG=true;;
    -h|--help) print_help;;
    *) echo "Unknown option: $1"; print_help;;
  esac
  shift
done

# Validate output configuration
if [ "$OUTPUT_MODE" != "terminal" ]; then
  if [ -z "$OUTPUT_FILE" ]; then
    echo "Error: --file option is required for $OUTPUT_MODE output" >&2
    exit 1
  fi
fi

check_dependencies

# Initialize output files
if [ "$OUTPUT_MODE" = "csv" ]; then
  echo "Group,Project,ProjectID,RepoID,Tag,SizeBytes,SizeMB,CreatedAt" > "$OUTPUT_FILE"
elif [ "$OUTPUT_MODE" = "pdf" ]; then
  LOGFILE=$(mktemp)
  if [ $? -ne 0 ]; then
    echo "Error: Could not create temporary file" >&2
    exit 1
  fi
  # Create a simple CSS style for PDF
  cat > "$LOGFILE.css" << 'EOF'
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.6;
  max-width: 900px;
  margin: 0 auto;
  padding: 32px;
}
pre {
  background: #f5f5f5;
  border: 1px solid #ddd;
  border-radius: 4px;
  padding: 16px;
  white-space: pre-wrap;
  word-wrap: break-word;
  margin: 16px 0;
}
code {
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
  font-size: 0.9em;
  background: #f5f5f5;
  padding: 2px 4px;
  border-radius: 3px;
}
table {
  border-collapse: collapse;
  width: 100%;
  margin: 16px 0;
}
th, td {
  border: 1px solid #ddd;
  padding: 8px;
  text-align: left;
}
th {
  background-color: #f5f5f5;
}
h1, h2 {
  border-bottom: 1px solid #eee;
  padding-bottom: 8px;
  margin-top: 24px;
  margin-bottom: 16px;
}
p {
  margin: 16px 0;
}
EOF
  # Ensure we clean up both temp files on exit
  trap 'rm -f "$LOGFILE" "$LOGFILE.css"' EXIT
  
  # Add title to the report
  echo "# GitLab Docker Image Analysis Report  " > "$LOGFILE"
  echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')  " >> "$LOGFILE"
  echo "" >> "$LOGFILE"
fi

TOTAL_TAGS=0
TOTAL_SIZE=0
TOTAL_PROJECTS=0
TMP_SIZE_FILE=$(mktemp)

api_call() {
  local url=$1
  local result
  result=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: $TOKEN" "$url")
  local status_code=$(echo "$result" | tail -n1)
  local response=$(echo "$result" | sed '$d')

  if [ "$DEBUG" = true ]; then
    echo "URL: $url" >&2
    echo "Status: $status_code" >&2
    echo "Response: $response" >&2
  fi

  if [ "$status_code" -ne 200 ]; then
    echo "API Error: Status $status_code" >&2
    echo "[]"
  else
    echo "$response"
  fi
}

page=1
while :; do
  URL="https://$GITLAB_HOST/api/v4/projects?per_page=$PER_PAGE&page=$page&archived=$INCLUDE_ARCHIVED"
  [ "$VISIBILITY" != "all" ] && URL="${URL}&visibility=$VISIBILITY"
  PROJECTS=$(api_call "$URL")
  COUNT=$(echo "$PROJECTS" | jq length)
  [ "$COUNT" -eq 0 ] && break

  for i in $(seq 0 $((COUNT - 1))); do
    pid=$(echo "$PROJECTS" | jq -r ".[$i].id")
    pname=$(echo "$PROJECTS" | jq -r ".[$i].name")
    full_path=$(echo "$PROJECTS" | jq -r ".[$i].path_with_namespace")
    group=$(dirname "$full_path")

    [ -n "$GROUP_PATH" ] && [[ "$full_path" != $GROUP_PATH* ]] && continue
    [ "$LIMIT" -gt 0 ] && [ "$TOTAL_PROJECTS" -ge "$LIMIT" ] && break 2

    log "🔧 Project: $pname ($pid)"
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))
    psize=0

    REPOS=$(api_call "https://$GITLAB_HOST/api/v4/projects/$pid/registry/repositories")
    for j in $(echo "$REPOS" | jq -r '.[].id'); do
      log "  📦 Repository: $j"
      TAGS=$(api_call "https://$GITLAB_HOST/api/v4/projects/$pid/registry/repositories/$j/tags")
      for tag in $(echo "$TAGS" | jq -r '.[].name'); do
        INFO=$(api_call "https://$GITLAB_HOST/api/v4/projects/$pid/registry/repositories/$j/tags/$tag")
        SIZE=$(echo "$INFO" | jq '.total_size')
        [ "$SIZE" == "null" ] && continue
        MB=$(echo "scale=2; $SIZE / 1024 / 1024" | bc)
        CREATED_AT=$(echo "$INFO" | jq -r '.created_at')
        # Convert UTC timestamp to local time
        CREATED_AT_LOCAL=$(date -d "$CREATED_AT" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S.000Z' "$CREATED_AT" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "$CREATED_AT")
        psize=$((psize + SIZE))
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
        TOTAL_TAGS=$((TOTAL_TAGS + 1))

        log "    🏷️ $tag - $MB MB ($SIZE bytes) - Created: $CREATED_AT_LOCAL"
        [ "$OUTPUT_MODE" = "csv" ] && write_output "$group,$pname,$pid,$j,$tag,$SIZE,$MB,$CREATED_AT"
      done
    done
    echo -e "$psize\t$group/$pname ($pid)" >> "$TMP_SIZE_FILE"
  done

  page=$((page + 1))
done

total_mb=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc)
total_gb=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024 / 1024" | bc)
log ""
log "📊 FINAL STATISTICS"
log "----------------------"
log "Projects analyzed: $TOTAL_PROJECTS"
log "Tags analyzed:     $TOTAL_TAGS"
log "Total size used:   $total_gb GB / $total_mb MB / $TOTAL_SIZE bytes"

if [ "$SORT_BY_SIZE" = true ]; then
  log "\n📦 Projects sorted by size:"
  sort -nr "$TMP_SIZE_FILE" | while read -r line; do
    size=$(echo "$line" | cut -f1)
    info=$(echo "$line" | cut -f2-)
    mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
    log "  $info - $mb MB"
  done
fi

# Generate final output
if [ "$OUTPUT_MODE" = "pdf" ]; then
  if [ -f "$LOGFILE" ]; then
    echo "Generating PDF using $PDF_ENGINE..."
    if pandoc "$LOGFILE" \
      -f markdown \
      -t pdf \
      --pdf-engine="$PDF_ENGINE" \
      --css="$LOGFILE.css" \
      -V margin-top=20 \
      -V margin-bottom=20 \
      -V margin-left=20 \
      -V margin-right=20 \
      -o "$OUTPUT_FILE"; then
      echo "📄 PDF report saved: $OUTPUT_FILE"
    else
      echo "Error: Failed to generate PDF" >&2
      exit 1
    fi
  else
    echo "Error: Log file not found" >&2
    exit 1
  fi
fi

# Clean up
rm -f "$TMP_SIZE_FILE"
