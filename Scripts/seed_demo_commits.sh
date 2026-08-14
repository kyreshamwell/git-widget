#!/usr/bin/env bash
#
# Seeds a demo repository with real commits so the App Review demo account has a
# contribution graph worth showing.
#
# For GitHub to count a commit on the profile graph, all of these must hold:
#   - the author email is a verified email on the demo GitHub account
#   - the commit is on the repo's default branch
#   - the repo is owned by (or has the account as a collaborator) and is NOT a fork
#   - if the repo is private, "Include private contributions on my profile" is on
#     in the account's profile settings — otherwise use a public repo
#
# The author email is passed in and applied per-commit, so your global
# git config is never touched.
#
# Usage:
#   Scripts/seed_demo_commits.sh --email demo@example.com [options]
#
#   --email ADDR         Author email. Required. Must be verified on the demo account.
#   --name NAME          Author name. Default: "Pushed Demo".
#   --repo PATH          Repo to commit into. Default: current directory.
#   --days N             Commit on each of N consecutive days. Default: 21.
#   --ending-days-ago K  Last commit day is K days ago. Default: 0 (today).
#   --per-day M          Commits per day. Default: 0 = random 1-4, for varied
#                        green intensity so the graph doesn't look synthetic.
#   --file NAME          File to append to. Default: demo-activity.md.
#   --push               Push to origin when done. Off by default.
#   --dry-run            Print what would happen, change nothing.
#
# Examples:
#   # 21-day streak ending yesterday — the state that makes the app's
#   # "your streak ends at midnight" reminder fire during a recording.
#   Scripts/seed_demo_commits.sh --email demo@example.com --days 21 --ending-days-ago 1 --push
#
#   # One commit today — the "watch the square turn green" beat.
#   Scripts/seed_demo_commits.sh --email demo@example.com --days 1 --per-day 1 --push

set -euo pipefail

EMAIL=""
NAME="Pushed Demo"
REPO="."
DAYS=21
ENDING_DAYS_AGO=0
PER_DAY=0
LOG_FILE="demo-activity.md"
PUSH=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email)            EMAIL="$2"; shift 2 ;;
        --name)             NAME="$2"; shift 2 ;;
        --repo)             REPO="$2"; shift 2 ;;
        --days)             DAYS="$2"; shift 2 ;;
        --ending-days-ago)  ENDING_DAYS_AGO="$2"; shift 2 ;;
        --per-day)          PER_DAY="$2"; shift 2 ;;
        --file)             LOG_FILE="$2"; shift 2 ;;
        --push)             PUSH=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -h|--help)          sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$EMAIL" ]]; then
    echo "error: --email is required (must be a verified email on the demo GitHub account)" >&2
    echo "       run with --help for usage" >&2
    exit 1
fi

cd "$REPO"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: $REPO is not a git repository" >&2; exit 1; }

BRANCH="$(git symbolic-ref --short HEAD)"
DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"

# Commits only count toward the graph on the default branch, and this script is
# easy to point at the wrong checkout — so say so rather than producing a
# hundred invisible commits.
if [[ -n "$DEFAULT_BRANCH" && "$BRANCH" != "$DEFAULT_BRANCH" ]]; then
    echo "warning: on '$BRANCH' but origin's default branch is '$DEFAULT_BRANCH'." >&2
    echo "         GitHub only counts default-branch commits on the contribution graph." >&2
    read -r -p "         Continue anyway? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || exit 1
fi

TOTAL=0

echo "repo:   $(pwd) (branch $BRANCH)"
echo "author: $NAME <$EMAIL>"
echo "file:   $LOG_FILE"
echo "range:  $DAYS day(s), ending $ENDING_DAYS_AGO day(s) ago"
$DRY_RUN && echo "-- dry run, nothing will be written --"
echo

for (( offset = DAYS - 1 + ENDING_DAYS_AGO; offset >= ENDING_DAYS_AGO; offset-- )); do
    DAY="$(date -v-"${offset}"d +%Y-%m-%d)"

    if [[ "$PER_DAY" -gt 0 ]]; then
        COUNT="$PER_DAY"
    else
        # Varied counts land the days in different GitHub quartiles, so the
        # graph shows a range of greens instead of one flat shade.
        COUNT=$(( (RANDOM % 4) + 1 ))
    fi

    for (( i = 1; i <= COUNT; i++ )); do
        # Spread through the working day so the timestamps aren't all identical.
        STAMP="${DAY}T$(printf '%02d' $(( 9 + (i * 2) % 10 ))):$(printf '%02d' $(( RANDOM % 60 ))):00"
        LINE="- ${STAMP} — demo activity ${i}/${COUNT}"

        if $DRY_RUN; then
            echo "would commit: $STAMP"
        else
            echo "$LINE" >> "$LOG_FILE"
            git add "$LOG_FILE"
            GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" GIT_AUTHOR_DATE="$STAMP" \
            GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL" GIT_COMMITTER_DATE="$STAMP" \
                git commit --quiet -m "Demo activity for ${DAY} (${i}/${COUNT})"
        fi
        TOTAL=$(( TOTAL + 1 ))
    done
    echo "  ${DAY}: ${COUNT} commit(s)"
done

echo
echo "$TOTAL commit(s) created."

if $PUSH && ! $DRY_RUN; then
    echo "pushing to origin/$BRANCH..."
    git push origin "$BRANCH"
    echo
    echo "Pushed. The contribution graph usually catches up within a minute or two;"
    echo "hit \"Refresh now\" in the app rather than waiting for the widget's own cycle."
elif ! $DRY_RUN; then
    echo "Not pushed — nothing counts toward the graph until it reaches GitHub."
    echo "Run: git push origin $BRANCH"
fi
