# Changelog

All notable changes to KDT are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is SemVer.

## [Unreleased]

### Added
- Milestone 1: all 12 Architecture Decision Records (`docs/adr/`), Accepted.
- Type B rollback runbook (`docs/operations/rollback-with-db-restore.md`).
- Milestone 2: repository scaffolding — `kcadmin` dispatcher, `lib/` helpers,
  systemd units, config templates, SELinux fcontext, Bats test, Makefile,
  GitHub Actions (CI + release), `.claude/` standards.
- Milestone 3 (in progress): `kcadmin install` — ensures OpenJDK, the service
  user, the directory tree (ADR-0001), and a side-by-side Keycloak distribution
  with `current` symlink management. Idempotent, dry-run aware; Bats-tested.

## [0.1.0] - 2026-07-11
- Initial scaffold.
