#!/usr/bin/env bash
# scripts/patch-engine.sh
# Run from inside the cloned target repo's root.
# Writes ./.patch-status with one of:
#   SUCCESS_WITH_CHANGES | NO_CHANGES | BUILD_FAILED | TEST_FAILED | UNSUPPORTED_ECOSYSTEM

set -uo pipefail   # NOTE: deliberately omit -e — we handle failures explicitly per step
STATUS_FILE=".patch-status"
SUMMARY_FILE=".patch-summary.md"

fail() {
  echo "$1" > "$STATUS_FILE"
  echo "## Security Patch — Halted" > "$SUMMARY_FILE"
  echo "" >> "$SUMMARY_FILE"
  echo "Reason: **$1**" >> "$SUMMARY_FILE"
  echo "$2" >> "$SUMMARY_FILE"
  echo "❌ $1: $2"
  exit 0   # graceful — let the calling workflow step succeed and read the status file
}

succeed_with_changes() {
  echo "SUCCESS_WITH_CHANGES" > "$STATUS_FILE"
  {
    echo "## Security Patch — Automated Vulnerability Fixes"
    echo ""
    echo "**Ecosystem:** $1"
    echo ""
    echo "**Summary of changes:**"
    echo '```'
    git diff --stat
    echo '```'
    echo ""
    echo "Build and tests passed before this PR was opened."
  } > "$SUMMARY_FILE"
  exit 0
}

run_step() {
  # run_step <label> <command...>
  local label="$1"; shift
  echo "▶ $label: $*"
  if ! "$@"; then
    return 1
  fi
  return 0
}

has_git_changes() {
  ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git status --porcelain)" ]]
}

# -----------------------------------------------------------------------
# 1. ECOSYSTEM DETECTION (priority order matters when multiple match)
# -----------------------------------------------------------------------
ECOSYSTEM=""
if [[ -f "package.json" ]]; then
  ECOSYSTEM="node"
elif [[ -f "pom.xml" ]]; then
  ECOSYSTEM="maven"
elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
  ECOSYSTEM="gradle"
elif compgen -G "*.csproj" > /dev/null || compgen -G "*.sln" > /dev/null; then
  ECOSYSTEM="dotnet"
elif [[ -f "requirements.txt" || -f "pyproject.toml" ]]; then
  ECOSYSTEM="python"
fi

if [[ -z "$ECOSYSTEM" ]]; then
  fail "UNSUPPORTED_ECOSYSTEM" "No recognized manifest found at repo root (package.json, pom.xml, build.gradle*, *.csproj/.sln, requirements.txt/pyproject.toml)."
fi
echo "Detected ecosystem: $ECOSYSTEM"

# -----------------------------------------------------------------------
# 2. FIX -> BUILD -> TEST, per ecosystem
# -----------------------------------------------------------------------
case "$ECOSYSTEM" in

  node)
    if ! run_step "npm ci" npm ci; then
      fail "BUILD_FAILED" "Initial 'npm ci' failed before any patching was attempted."
    fi

    npm audit fix --force || true   # audit fix can exit non-zero even on partial success; don't trust exit code alone

    if ! has_git_changes; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "No vulnerable packages required updates." > "$SUMMARY_FILE"
      exit 0
    fi

    if ! run_step "npm run build" npm run build --if-present; then
      fail "BUILD_FAILED" "Build failed after dependency updates. Changes discarded."
    fi
    if ! run_step "npm test" npm test --if-present; then
      fail "TEST_FAILED" "Test suite failed after dependency updates. Changes discarded."
    fi
    succeed_with_changes "Node.js / npm"
    ;;

  maven)
    if ! run_step "mvn versions:use-latest-releases" \
        mvn -B versions:use-latest-releases -DallowSnapshots=false; then
      fail "BUILD_FAILED" "Maven versions plugin failed to run."
    fi

    if ! has_git_changes; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "No dependency version bumps were applicable." > "$SUMMARY_FILE"
      exit 0
    fi

    if ! run_step "mvn clean test" mvn -B clean test; then
      fail "TEST_FAILED" "'mvn clean test' failed after dependency updates. Changes discarded."
    fi
    succeed_with_changes "Java / Maven"
    ;;

  gradle)
    GRADLE_CMD="./gradlew"
    [[ -x "$GRADLE_CMD" ]] || GRADLE_CMD="gradle"

    # Requires the 'com.github.ben-manes.versions' plugin or similar to be present;
    # if not configured in the target repo, this step is a no-op detector, not an installer
    # (we don't inject build.gradle changes to add plugins — out of scope/zero-file-footprint).
    if ! run_step "gradle dependencyUpdates" "$GRADLE_CMD" dependencyUpdates -DoutputFormatter=json; then
      echo "Warning: dependencyUpdates task unavailable; skipping automated bump for Gradle." >&2
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "Gradle repo does not expose a dependency-update task; no changes made." > "$SUMMARY_FILE"
      exit 0
    fi

    if ! has_git_changes; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "No dependency updates were applicable." > "$SUMMARY_FILE"
      exit 0
    fi

    if ! run_step "gradle build" "$GRADLE_CMD" build; then
      fail "BUILD_FAILED" "'./gradlew build' failed after dependency updates. Changes discarded."
    fi
    succeed_with_changes "Java / Gradle"
    ;;

  dotnet)
    VULN_OUTPUT=$(dotnet list package --vulnerable --include-transitive 2>&1) || true
    echo "$VULN_OUTPUT"

    if ! echo "$VULN_OUTPUT" | grep -qi "has the following vulnerable packages"; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "No vulnerable NuGet packages detected." > "$SUMMARY_FILE"
      exit 0
    fi

    # Parse package names and update each to latest (simplified — production version
    # should parse the table properly rather than grep)
    mapfile -t PKGS < <(echo "$VULN_OUTPUT" | grep -oP '^\s*>\s*\K[A-Za-z0-9_.\-]+' || true)
    for proj in $(find . -name "*.csproj"); do
      for pkg in "${PKGS[@]}"; do
        dotnet add "$proj" package "$pkg" || true
      done
    done

    if ! has_git_changes; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "Vulnerable packages detected but no updates applied (no fixed version available)." > "$SUMMARY_FILE"
      exit 0
    fi

    if ! run_step "dotnet build" dotnet build; then
      fail "BUILD_FAILED" "'dotnet build' failed after package updates. Changes discarded."
    fi
    if ! run_step "dotnet test" dotnet test; then
      fail "TEST_FAILED" "'dotnet test' failed after package updates. Changes discarded."
    fi
    succeed_with_changes ".NET"
    ;;

  python)
    python -m pip install --quiet --upgrade pip pip-review || true

    if [[ -f "requirements.txt" ]]; then
      pip-review --auto || true
    elif [[ -f "pyproject.toml" ]]; then
      # pip-review doesn't understand pyproject directly; fall back to pip-compile/poetry
      # depending on what's present, kept minimal here for breadth.
      if command -v poetry >/dev/null 2>&1 && grep -q "\[tool.poetry\]" pyproject.toml; then
        poetry update || true
      else
        echo "pyproject.toml present without Poetry — skipping auto-upgrade (manual review needed)." >&2
      fi
    fi

    if ! has_git_changes; then
      echo "NO_CHANGES" > "$STATUS_FILE"
      echo "No outdated/vulnerable Python packages required updates." > "$SUMMARY_FILE"
      exit 0
    fi

    pip install -r requirements.txt --quiet 2>/dev/null || true

    TEST_CMD="pytest"
    if [[ -f "tox.ini" ]]; then TEST_CMD="tox"; fi

    if ! run_step "python tests ($TEST_CMD)" $TEST_CMD; then
      fail "TEST_FAILED" "'$TEST_CMD' failed after dependency updates. Changes discarded."
    fi
    succeed_with_changes "Python"
    ;;

esac