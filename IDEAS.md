# crate — Tool Ideas Backlog

Tools worth adding in future, roughly prioritized. Not installed yet.

## Demo & API tooling
- **httpie** or **xh** — friendlier than curl for live API demos in front of customers
- **websocat** — WebSocket testing; relevant for Workers + Durable Objects demos
- **k6** — load testing CLI; great for showing Cloudflare performance/caching wins
- **grpcurl** — gRPC testing if customers are doing Workers + gRPC
- **bun** — fast JS runtime + package manager; increasingly common in Workers-adjacent projects

## Data / observability
- **jless** — interactive terminal JSON explorer; pairs well with jq for live API demos
- **duckdb** — in-process analytics SQL; useful for demoing D1-adjacent data stories
- **sqlite3** — D1 is SQLite under the hood; useful for local schema/query prototyping

## IaC / platform
- **direnv** — auto-load `.envrc` per project; great for managing multiple customer account credentials cleanly
- **pulumi** CLI — some customers use it; Cloudflare has a Pulumi provider

## Networking / security diagnostics
- **mtr** — better traceroute; great for showing routing/latency wins to customers
- **dog** or **drill** — modern DNS query tools; relevant for Cloudflare DNS/Zero Trust demos
- **nmap** — useful for security posture demos

## Explicitly excluded
- **kubectl**, **helm**, **k9s**, **kubectx/kubens** — Cloudflare Workers + Containers is the story; k8s tooling would send the wrong message
- **OpenTofu** — HashiCorp BSL does not affect personal use or SE demos; Terraform is fine
