# Instructions for AI agents

Read this file first, then [CLAUDE.md](CLAUDE.md). Follow the avd-ops family rules at <https://github.com/avd-ops/avd-ops/blob/main/AGENTS.md>.

- **No spend without the owner's exact go.**
- **Never leave the meter running.** Hub resources (Firewall, Private Resolver, Bastion, Gateways) bill continuously; default `lab` profile to minimal spend and never leave gateways enabled by default.
- **Never delete the last copy** of data without a checked copy elsewhere or `-DiscardLastCopy`.
- **No secrets, IDs or names.** Use `contoso.com`, `<tenant-id>`, `10.x`.
- **Pull requests only; the owner merges.** Work on a branch and open a PR; never push directly to `main` after initial bootstrap.
- **Stay in your lane.** `avd-networking` owns Platform Connectivity only (hub VNet, Firewall, central Private DNS, Private Resolver, gateways, Bastion, hub monitoring) under [avd-ops decision 0014](https://avd-ops.dev/docs/decisions/0014-add-avd-networking-connectivity-control-plane.html). No AVD host pools, session hosts, or HCL/Terraform here.
- **Personal project, not for production, as is, not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.**
- **American English** in docs, output and comments.
