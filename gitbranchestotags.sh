#!/usr/bin/env bash
set -euo pipefail

REMOTE="origin"
DRY_RUN=false
FORCE=false
DELETE_BRANCH=false
BRANCH_FILE=""
BRANCHES=()

usage() {
  cat <<EOF
Usage: $0 [options] [branch1 branch2 ...]

Options:
  --remote NAME       Remote name to read branches from (default: origin)
  --file PATH         Read branch names (one per line) from file
  --force             Overwrite existing archive/<branch> tags
  --delete            Delete the branch (remote + local) after tagging
  --dry-run           Show actions but do not create tags, push, or delete
  -h, --help          Show this help
Notes:
  - Place flags before branch names, or anywhere; the script will detect flags even if placed after.
  - Use -- to explicitly end options: ./gitbranchestotags.sh --delete -- branch1 branch2
EOF
  exit 0
}

# First-pass parse: consume leading options until first non-option or --
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="$2"; shift 2 ;;
    --file) BRANCH_FILE="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --delete) DELETE_BRANCH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --) shift; break ;; # explicit end of options
    -h|--help) usage ;;
    --*) 
      # unknown long option -> treat as branch (will be sanitized later)
      BRANCHES+=("$1"); shift ;;
    *) 
      # first positional arg -> treat as branch; break to collect remaining as branches
      BRANCHES+=("$1"); shift
      # Collect remaining args as branches (they may include flags; we'll sanitize later)
      while [[ $# -gt 0 ]]; do
        BRANCHES+=("$1"); shift
      done
      break
      ;;
  esac
done

# If a branch file was provided, read branches from it
if [[ -n "$BRANCH_FILE" ]]; then
  if [[ ! -f "$BRANCH_FILE" ]]; then
    echo "Branch file not found: $BRANCH_FILE" >&2
    exit 1
  fi
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    BRANCHES+=("$line")
  done < "$BRANCH_FILE"
fi

# Sanitize BRANCHES: allow flags that were passed after branch names
SANITIZED=()
for item in "${BRANCHES[@]}"; do
  case "$item" in
    --force) FORCE=true; continue ;;
    --delete) DELETE_BRANCH=true; continue ;;
    --dry-run) DRY_RUN=true; continue ;;
    --remote) echo "Warning: --remote must be before branch list; ignoring here." >&2; continue ;;
    --file) echo "Warning: --file must be before branch list; ignoring here." >&2; continue ;;
    --help|-h) usage ;;
    *) SANITIZED+=("$item") ;;
  esac
done
BRANCHES=("${SANITIZED[@]}")

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
  echo "No branches provided. Use args or --file." >&2
  usage
fi

echo "Remote: $REMOTE"
$DRY_RUN && echo "DRY RUN: ON (no changes will be made)"
$DELETE_BRANCH && echo "DELETE_BRANCH: ON (branches will be deleted after tagging)"
$FORCE && echo "FORCE: ON (overwrite existing tags if present)"

# Ensure we have up-to-date remote refs
git fetch "$REMOTE" --prune

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD || echo "")

for branch in "${BRANCHES[@]}"; do
  tag="archive/${branch}"
  echo ""
  echo "Processing branch: $branch → tag: $tag"

  # Resolve commit: prefer remote branch tip, fallback to local
  commit_hash=$(git ls-remote "$REMOTE" "refs/heads/$branch" | awk '{print $1}')
  if [[ -z "$commit_hash" ]]; then
    echo "  Remote branch not found, checking local branch..."
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      commit_hash=$(git rev-parse "$branch")
      echo "  Using local branch tip: $commit_hash"
    else
      echo "  Branch '$branch' not found (remote or local). Skipping." >&2
      continue
    fi
  else
    echo "  Remote tip: $commit_hash"
  fi

  # Check existing tag
  if git show-ref --tags --quiet --verify "refs/tags/$tag"; then
    if $FORCE; then
      echo "  Tag $tag exists — will overwrite (force)."
      if ! $DRY_RUN; then
        git tag -d "$tag" || true
        git push "$REMOTE" --delete "refs/tags/$tag" || true
      fi
    else
      echo "  Tag $tag already exists — skipping (use --force to overwrite)."
      if $DELETE_BRANCH; then
        echo "  Skipping deletion of branch $branch because tag exists and --force not set."
      fi
      continue
    fi
  fi

  # Create annotated tag locally and push
  echo "  Creating annotated tag pointing to $commit_hash"
  if $DRY_RUN; then
    echo "    DRY: git tag -a \"$tag\" $commit_hash -m \"Archive of branch $branch ($(date -u +%Y-%m-%dT%H:%M:%SZ))\""
    echo "    DRY: git push $REMOTE refs/tags/$tag"
  else
    git tag -a "$tag" "$commit_hash" -m "Archive of branch $branch (archived on $(date -u +%Y-%m-%dT%H:%M:%SZ) by $(git config user.email || echo unknown))"
    git push "$REMOTE" "refs/tags/$tag"
    echo "  Pushed tag $tag to $REMOTE"
  fi

  # Optionally delete branch (remote + local)
  if $DELETE_BRANCH; then
    # Safety: avoid deleting protected branches unless --force
    if [[ "$branch" == "main" || "$branch" == "master" ]]; then
      if ! $FORCE; then
        echo "  Refusing to delete protected branch '$branch' (use --force to override)."
        continue
      fi
    fi

    echo "  Deleting remote branch $REMOTE/$branch"
    if $DRY_RUN; then
      echo "    DRY: git push $REMOTE --delete $branch"
    else
      git push "$REMOTE" --delete "$branch" || {
        echo "    Warning: failed to delete remote branch $REMOTE/$branch (it may not exist)"
      }
    fi

    # Delete local branch if present
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
        echo "  Local branch '$branch' is currently checked out (skipping local delete)."
      else
        echo "  Deleting local branch $branch"
        if $DRY_RUN; then
          echo "    DRY: git branch -D $branch"
        else
          git branch -D "$branch" || {
            echo "    Warning: failed to delete local branch $branch"
          }
        fi
      fi
    else
      echo "  No local branch named $branch"
    fi
  fi

  echo "  ✅ Done: $branch archived as $tag"
done

echo ""
echo "Done. Processed ${#BRANCHES[@]} branches."