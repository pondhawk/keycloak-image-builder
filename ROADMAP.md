# KDT Roadmap

Milestones follow blueprint §19. Each must be independently reviewable and add
validation (ADR-0012).

| # | Milestone | Status |
|---|-----------|--------|
| 1 | ADRs | ✅ Complete (12/12 Accepted) |
| 2 | Repository scaffolding | 🚧 In progress |
| 3 | Installer | ⏳ Planned |
| 4 | Configuration | ⏳ Planned |
| 5 | systemd | ⏳ Planned |
| 6 | SELinux | ⏳ Planned |
| 7 | Validation | ⏳ Planned |
| 8 | Cluster support | ⏳ Planned |
| 9 | Upgrade framework | ⏳ Planned |
| 10 | Documentation | ⏳ Planned |
| 11 | Production hardening | ⏳ Planned |

## Subcommand implementation status

Implemented: `version` (+ dispatcher, `--help`).
Skeleton/pending: `install configure build check start stop restart status logs
journal health verify cluster upgrade rollback ami-clean`.
