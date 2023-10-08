#!/usr/bin/env bash
# Enable strict error checking
set -euo pipefail

# Install ncu
npm i -g npm-check-updates
pushd dependencies

# Update all dependencies
echo "Installing NPM dependencies..."
npm install
echo "Updating NPM dependencies..."
ncu -u
echo "Removing existing lockfile..."
rm -rf package-lock.json
echo "Installing NPM dependencies..."
npm install

# Setup Git Config
echo "Configuring Git..."
git config --global user.email "infosulaimanbd@gmail.com"
git config --global user.name "Awesome-Linter Automation"

if [[ $(git status --porcelain) ]]; then
  # Push changes to remote
  echo "Pushing changes to remote..."
  git add .
  git commit -a -m "Update NPM dependencies"
  # shellcheck disable=SC2154
  git checkout -b "npm_deps_${id}"
  # shellcheck disable=SC2154
  git push origin "npm_deps_${id}"

  # Open pull request
  echo "Opening pull request..."
  # shellcheck disable=SC2154
  echo "${token}" | gh auth login --with-token
  gh pr create --title "Weekly NPM Updates" --body "Updates NPM dependencies" --base main --head "npm_deps_${id}"
else
  echo "No changes to commit"
fi
