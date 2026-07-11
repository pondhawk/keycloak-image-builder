# KDT Roadmap

Milestones follow blueprint §19. Each must be independently reviewable and add
validation (ADR-0012).

| # | Milestone | Status |
|---|-----------|--------|
| 1 | ADRs | ✅ Complete (12/12 Accepted) |
| 2 | Repository scaffolding | ✅ Complete |
| 3 | Installer | ✅ Complete |
| 4 | Configuration | ✅ Complete |
| 5 | systemd | ✅ Complete |
| 6 | SELinux | ✅ Complete |
| 7 | Validation | ✅ Complete |
| 8 | Cluster support | ⏳ Planned |
| 9 | Upgrade framework | ⏳ Planned |
| 10 | Documentation | ⏳ Planned |
| 11 | Production hardening | ⏳ Planned |

## Subcommand implementation status

Implemented: `version`, `install`, `check`, `configure`, `start`, `stop`,
`restart`, `status`, `logs`, `journal`, `selinux`, `build`, `health`, `verify`
(+ dispatcher, `--help`).
Skeleton/pending: `cluster upgrade rollback ami-clean`.
