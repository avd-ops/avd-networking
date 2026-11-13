# avd-networking

Part of [avd-ops](https://avd-ops.dev/), the open toolkit for Azure Virtual Desktop.

> [!WARNING]
> **Personal project. Research and learning only. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time **for research and learning**. It is **not affiliated with, endorsed by or supported by my employer**, Liquidware, ServiceNow or Microsoft, and it does not represent their views, products or guidance.
> - **Do not run any of it in production** or against subscriptions and tenants that matter. Test it first in a dedicated lab subscription and tenant.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](LICENSE). You use it at your own risk.
> - **Contributions and forks are welcome and encouraged.** See [Contributing](#contributing).

## Role in avd-ops

Platform Connectivity control plane (`avd-networking`), orchestrated by [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) ([decision 0014](https://avd-ops.dev/docs/decisions/0014-add-avd-networking-connectivity-control-plane.html)).

## What it does

- Deploys an enterprise Hub VNet (`GatewaySubnet`, `AzureFirewallSubnet`, `AzureBastionSubnet`, DNS Private Resolver subnets) with `defaultOutboundAccess: false`.
- Configures Azure Firewall (`Basic` in `lab`, `Standard`/`Premium` with multi-PIP SNAT scaling in `enterprise`) and Firewall Policy rules aligned with `avd-assess` required endpoints (including optional RDP Shortpath UDP 3478).
- Deploys central Private DNS zones (`file`, `keyVault`, `avd`, `avdGlobal`) for `commercial` and `usgov` and optional Azure DNS Private Resolver.
- Supports optional Standard Azure Bastion, optional VPN/ExpressRoute gateways (off by default), and VNet Flow Logs.
- Emits `networking-outputs.json` (`avd-networking-outputs/v1`, contract C31) consumed by `avd-azure` in `HubPeered` mode, plus `Add-SpokeLink.ps1` for two-phase cross-subscription peering and DNS linking.

## Contributing

Fork it, open an issue or a pull request. Follow the family guardrails in [AGENTS.md](AGENTS.md): no tenant IDs, secrets, domains or customer names, and propose changes via pull request only. Contributions are accepted under the [MIT License](LICENSE).

## License and disclaimer

[MIT](LICENSE). Personal project, not for production, provided as is, not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
