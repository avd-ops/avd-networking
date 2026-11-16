# avd-networking

Part of [avd-ops](https://avd-ops.dev/), the open toolkit for Azure Virtual Desktop.

Platform Connectivity control plane (`avd-networking`), orchestrated by [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone#readme) ([avd-ops docs](https://avd-ops.dev/docs/repos/avd-networking.html), [decision 0014](https://avd-ops.dev/docs/decisions/0014-add-avd-networking-connectivity-control-plane.html)).

> [!WARNING]
> **Personal project. Research and learning only. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time **for research and learning**. It is **not affiliated with, endorsed by or supported by my employer**, Liquidware, ServiceNow or Microsoft, and it does not represent their views, products or guidance.
> - **Do not run any of it in production** or against subscriptions and tenants that matter. Test it first in a dedicated lab subscription and tenant.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](LICENSE). You use it at your own risk.
> - **Contributions and forks are welcome and encouraged.** See [Contributing](#contributing).

## How it connects

| Direction | Repo | Relationship |
|---|---|---|
| Front door | [avd-ops](https://github.com/avd-ops/avd-ops#readme) | Overview, [repo page](https://avd-ops.dev/docs/repos/avd-networking.html), and platform decisions |
| Orchestrator | [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone#readme) | Invokes `avd-networking` for hub connectivity and spoke peering |
| Downstream | [avd-azure](https://github.com/avd-ops/avd-azure#readme) | Consumes `networking-outputs.json` (`C31`) in `HubPeered` mode |
| Standards | [avd-assess](https://github.com/avd-ops/avd-assess#readme) | Supplies endpoint and network posture standards (`methods/network.md`) |

## What it does

- Deploys an enterprise Hub VNet (`GatewaySubnet`, `AzureFirewallSubnet`, `AzureBastionSubnet`, DNS Private Resolver subnets, optional NVA untrusted/trusted subnets, and `additionalSubnets` for 3rd-party appliances) with `defaultOutboundAccess: false` — or wraps an existing/3rd-party hub VNet via `existingHubVnetResourceId`.
- Supports `firewallMode`: `'azure-firewall'` (`Basic` in `lab`, `Standard`/`Premium` with multi-PIP SNAT scaling in `enterprise`, aligned with [avd-assess](https://github.com/avd-ops/avd-assess#readme) required endpoints and optional RDP Shortpath UDP 3478), `'nva'` (3rd-party NVA/firewall private IP emitted as `hubFirewallPrivateIp` in C31), or `'none'`.
- Deploys central Private DNS zones (`file`, `keyVault`, `avd`, `avdGlobal`) for `commercial` and `usgov`, optional Azure DNS Private Resolver, and `customDnsServers` override for 3rd-party/on-prem DNS.
- Supports optional Standard Azure Bastion, VNet Flow Logs, and full VPN / ExpressRoute / coexistence (`Both`) gateway configurations (Active-Active VPN, BGP, Local Network Gateways, IPsec S2S connections, ExpressRoute circuits with FastPath and `ErGwScale`), off by default.
- Emits `networking-outputs.json` (`avd-networking-outputs/v1`, contract C31) consumed by [avd-azure](https://github.com/avd-ops/avd-azure#readme) in `HubPeered` mode, plus `Add-SpokeLink.ps1` for two-phase cross-subscription peering and DNS linking.

## Docs

- Agent instructions & guardrails: [AGENTS.md](AGENTS.md)
- Repo page on avd-ops: [avd-ops.dev/docs/repos/avd-networking](https://avd-ops.dev/docs/repos/avd-networking.html)

## Contributing

Fork it, open an issue or a pull request. Follow the family guardrails in [AGENTS.md](AGENTS.md): no tenant IDs, secrets, domains or customer names, and propose changes via pull request only. Contributions are accepted under the [MIT License](LICENSE).

## License and disclaimer

[MIT](LICENSE). Personal project, not for production, provided as is, not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
