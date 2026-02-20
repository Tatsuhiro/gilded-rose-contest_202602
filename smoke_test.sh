#!/bin/bash
# =============================================================
# GildedRose Refactoring Contest - Smoke Test
# =============================================================
# 全サービスが正しく動作するか確認します。
#
# Usage:
#   chmod +x smoke_test.sh
#   ./smoke_test.sh
# =============================================================

set -euo pipefail

PASS=0
FAIL=0
ERRORS=()

run_test() {
  local name="$1"
  local command="$2"
  local check="$3"

  printf "  %-40s" "$name"

  # stderrはdocker composeのコンテナ作成メッセージなので除外
  output=$(eval "$command" 2>/dev/null) || true

  if echo "$output" | grep -q "$check"; then
    echo "✅ PASS"
    PASS=$((PASS + 1))
  else
    echo "❌ FAIL"
    ERRORS+=("$name: expected '$check' in output")
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "======================================================="
echo "  🧪 GildedRose Contest - Smoke Test"
echo "======================================================="
echo ""

# -------------------------------------------------------
# 1. Docker build
# -------------------------------------------------------
echo "📦 Building Docker image..."
if docker compose build --quiet 2>/dev/null; then
  echo "  Build                                   ✅ PASS"
  PASS=$((PASS + 1))
else
  echo "  Build                                   ❌ FAIL"
  ERRORS+=("Docker build failed")
  FAIL=$((FAIL + 1))
  echo ""
  echo "Build failed. Cannot continue."
  exit 1
fi
echo ""

# -------------------------------------------------------
# 2. score
# -------------------------------------------------------
echo "📊 Testing: score"
run_test \
  "score: exits successfully" \
  "docker compose run --rm score" \
  "TOTAL SCORE:"

run_test \
  "score: shows Code Quality section" \
  "docker compose run --rm score" \
  "A. Code Quality"

run_test \
  "score: shows Tests section" \
  "docker compose run --rm score" \
  "B. Tests"

run_test \
  "score: shows Correctness section" \
  "docker compose run --rm score" \
  "C. Correctness"

run_test \
  "score: shows AI Agent Usage section" \
  "docker compose run --rm score" \
  "D. AI Agent Usage"

run_test \
  "score: correctness gate passes" \
  "docker compose run --rm score" \
  "PASS"

echo ""

# -------------------------------------------------------
# 3. score-json
# -------------------------------------------------------
echo "📊 Testing: score-json"
run_test \
  "score-json: returns valid JSON" \
  "docker compose run --rm score-json" \
  "total_score"

run_test \
  "score-json: contains scores object" \
  "docker compose run --rm score-json" \
  "\"scores\""

run_test \
  "score-json: contains details object" \
  "docker compose run --rm score-json" \
  "\"details\""

run_test \
  "score-json: contains timestamp" \
  "docker compose run --rm score-json" \
  "timestamp"

# JSON parse check
printf "  %-40s" "score-json: parseable JSON"
json_output=$(docker compose run --rm score-json 2>/dev/null) || true
if echo "$json_output" | ruby -rjson -e 'JSON.parse(STDIN.read)' 2>/dev/null; then
  echo "✅ PASS"
  PASS=$((PASS + 1))
else
  echo "❌ FAIL"
  ERRORS+=("score-json: output is not valid JSON")
  FAIL=$((FAIL + 1))
fi

echo ""

# -------------------------------------------------------
# 4. baseline
# -------------------------------------------------------
echo "📊 Testing: baseline"
run_test \
  "baseline: shows RuboCop offenses" \
  "docker compose run --rm baseline" \
  "RuboCop offenses"

run_test \
  "baseline: shows Flog total" \
  "docker compose run --rm baseline" \
  "Flog total"

run_test \
  "baseline: shows Flay total" \
  "docker compose run --rm baseline" \
  "Flay total"

echo ""

# -------------------------------------------------------
# 5. test
# -------------------------------------------------------
echo "📊 Testing: test"
run_test \
  "test: rspec runs successfully" \
  "docker compose run --rm test" \
  "example"

run_test \
  "test: golden master specs pass" \
  "docker compose run --rm test" \
  "Golden Master"

echo ""

# -------------------------------------------------------
# 6. lint
# -------------------------------------------------------
echo "📊 Testing: lint"
run_test \
  "lint: rubocop runs successfully" \
  "docker compose run --rm lint" \
  "offense"

echo ""

# -------------------------------------------------------
# Results
# -------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "======================================================="
echo "  Results: $PASS/$TOTAL passed"
echo "======================================================="

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "  Failures:"
  for err in "${ERRORS[@]}"; do
    echo "    ❌ $err"
  done
fi

echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "  🎉 All tests passed! Ready for the contest."
else
  echo "  ⚠  $FAIL test(s) failed. Please fix before distributing."
fi

echo ""
exit "$FAIL"
