# Release process

When user says "prepare release" or "cut release", follow `docs/release.md` step by step:

1. Run pre-release checks (uncommitted changes in worktrees, unmerged branches)
2. Ask user for version number (if not specified) and release notes
3. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `JustAboutTime.xcodeproj/project.pbxproj`
4. Commit version bump and tag
5. Run `scripts/release-notarized.sh` to build notarized DMG
6. Push tag, create GitHub release with DMG asset
7. Clone `moophis/homebrew-tap`, update cask version + sha256, push
8. Clean up
