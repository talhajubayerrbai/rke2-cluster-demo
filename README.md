# rke2-cluster-demo

End-to-end automated deployment of a 2-node RKE2 Kubernetes cluster on AWS EC2, fronted by an Application Load Balancer, with a hello-world demo app reachable at `http://hello.<alb-dns-name>`.

## Architecture

```
Internet → ALB (port 80) → NodePort 30080 → nginx-ingress → hello-world pod
```

- **2 × EC2 t3.medium** (Ubuntu 22.04, default VPC, public subnets)
  - `rke2-server`: control-plane node
  - `rke2-agent`:  worker node
- **ALB**: internet-facing, listener on port 80, target group on NodePort 30080
- **RKE2**: lightweight Kubernetes distribution installed via Ansible
- **nginx-ingress**: NodePort service type, binds port 30080
- **hello-world**: custom Helm chart, Ingress with host `hello.<alb-dns>`

## Repository Layout

```
rke2-cluster-demo/
├── terraform/          # EC2 x2, ALB, SGs, key pair (default VPC)
├── ansible/
│   ├── inventory/      # generated at pipeline runtime
│   ├── roles/
│   │   ├── rke2_server/
│   │   └── rke2_agent/
│   └── site.yml
├── charts/
│   ├── nginx-ingress/  # values override: NodePort 30080
│   └── hello-world/    # Deployment + ConfigMap + Service + Ingress
└── .github/workflows/
    ├── deploy.yml      # 3-job pipeline
    └── destroy.yml     # teardown
```

## Pipeline Jobs

| Job | What it does |
|-----|-------------|
| `terraform` | Provisions VPC data, EC2 x2, ALB, SGs, key pair; outputs IPs + ALB DNS |
| `ansible` | Installs RKE2 server + agent, fetches/patches kubeconfig to runner |
| `helm-deploy` | Installs ingress-nginx (NodePort 30080) + hello-world; curls the app |

## Secrets Required

Wired via `set_pipeline_account` for the `udap-dev-aws` account:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` variable = `us-east-1`

## Access

After a successful pipeline run, the app is reachable at:
```
http://hello.<alb-dns-name>
```
The ALB DNS name is printed in the `helm-deploy` job logs.

## Teardown

Trigger the `destroy.yml` workflow with input `confirm=destroy` to run `terraform destroy`.
