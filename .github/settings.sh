#!/usr/bin/env bash
# Applies this repo's GitHub settings, which can't live in a file GitHub
# reads. Run it by hand with a gh login that is admin on the repo:
#
#   bash .github/settings.sh [owner/repo]
#
# Safe to re-run: every call sets a value, and the ruleset is updated in
# place by name.
set -euo pipefail

repo=${1:-SAUCE-2/saucefiguration}

# Squash only, titled by the (conventional) PR title. Merged branches are
# deleted, and PRs can be set to auto-merge once checks pass.
gh api -X PATCH "repos/$repo" --silent \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE \
  -F delete_branch_on_merge=true \
  -F allow_auto_merge=true \
  -F allow_update_branch=true \
  -F has_wiki=false \
  -F has_projects=false
echo "repo settings: ok"

gh api -X PUT "repos/$repo/vulnerability-alerts" --silent
gh api -X PUT "repos/$repo/automated-security-fixes" --silent
echo "dependabot alerts and security updates: ok"

# The default branch takes changes only through a squashed PR with green
# CI, and can't be force-pushed or deleted. Repo admins (you) bypass it,
# so direct pushes still work for you but not for bots and agents.
# 15368 is the GitHub Actions app, so only Actions can satisfy the checks.
ruleset=$(cat <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "checks (ubuntu-latest)", "integration_id": 15368 },
          { "context": "checks (macos-latest)", "integration_id": 15368 },
          { "context": "pr title", "integration_id": 15368 }
        ]
      }
    }
  ]
}
JSON
)

id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')
if [ -n "$id" ]; then
  gh api -X PUT "repos/$repo/rulesets/$id" --input - --silent <<<"$ruleset"
else
  gh api -X POST "repos/$repo/rulesets" --input - --silent <<<"$ruleset"
fi
echo "ruleset main: ok"
