# cost-reaper

Finds, and optionally deletes, billable AWS resources that are left behind after `make destroy`.

> **Status:** design. Built in Phase 2, when clusters start being created and destroyed.

## The problem

`terraform destroy` deletes only what is in Terraform state. On EKS, controllers running *inside* the cluster create AWS resources that Terraform has never seen:

| Created by | AWS resource | Typical cost if leaked (ap-south-1) |
|---|---|---|
| AWS Load Balancer Controller | Network Load Balancer, target groups, security groups | ~$18/month per NLB |
| Karpenter | EC2 instances, launch templates | $10–70/month per node |
| EBS CSI driver | EBS volumes for PersistentVolumeClaims | ~$0.09/GB-month |
| VPC CNI | Detached ENIs (they block VPC and subnet deletion) | $0, but `destroy` fails |
| Various | Unassociated Elastic IPs | ~$3.6/month each |
| Velero | EBS snapshots beyond retention | ~$0.05/GB-month |

If the cluster is destroyed before its controllers clean up, these resources keep billing quietly. On an ephemeral platform (ADR-0002) that is destroyed every session, this is the most likely way to get a surprise bill.

## What it does

```
make destroy ──► terraform destroy ──► cost-reaper report ──► Slack + exit code
                                              │
                         nightly GitHub Action ┘   (cost-reaper apply after the nightly destroy)
```

1. **Discovers** resources through the Resource Groups Tagging API and service-specific APIs, matching:
   - our tag `project=ledgerpay` (set as Terraform `default_tags` and passed to Karpenter, the Load Balancer Controller and the EBS CSI driver)
   - controller ownership tags: `elbv2.k8s.aws/cluster`, `karpenter.sh/nodepool`, `ebs.csi.aws.com/cluster`, `kubernetes.io/cluster/<name>`
   - untagged waste in the project VPC: available ENIs, unassociated EIPs
2. **Estimates cost** per resource from a small built-in price table for `ap-south-1`, clearly marked as approximate.
3. **Reports** a table to the console, JSON for CI, and a Slack message with the total $/month at risk.
4. **Deletes** only in `apply` mode, in dependency order:
   load balancers → target groups → EC2 instances (wait for termination) → ENIs → EBS volumes → Elastic IPs → security groups → expired snapshots.

## Safety rules

Deleting cloud resources automatically is risky, so the tool is conservative by design:

- **Dry run by default.** `report` never changes anything; deleting needs an explicit `apply`.
- **Refuses to delete while the cluster exists.** If the EKS cluster is still `ACTIVE`, those resources are probably in use, so `apply` exits with an error.
- **Protected resources are never touched:** anything tagged `ledgerpay/protected=true`, which covers the Terraform state bucket and lock table, the Velero bucket, ECR repositories, Secrets Manager secrets and KMS keys.
- **Project-scoped only:** it acts only on resources matching the tags above, never on "everything in the account".
- **Least-privilege IAM:** a dedicated role (`ledgerpay-cost-reaper`) assumed via GitHub OIDC. Delete actions are conditioned on resource tags wherever AWS supports it.
- **Every action is logged** as structured JSON with the resource ARN, so there's an audit trail.

## Usage (planned)

```bash
cost-reaper report  --region ap-south-1 --cluster ledgerpay-dev        # list leftovers + est. cost
cost-reaper report  --output json                                       # machine-readable, for CI
cost-reaper apply   --region ap-south-1 --cluster ledgerpay-dev         # delete (refuses if cluster is ACTIVE)
```

| Exit code | Meaning |
|---|---|
| 0 | Nothing left behind |
| 1 | Leftovers found (report mode), so CI can flag it |
| 2 | Error, or a safety rule blocked the run |

## Engineering

- Python 3.12; CLI built with **Typer**; AWS access through **boto3**
- Type hints throughout, checked by **mypy**; linted and formatted with **ruff**
- **pytest + moto** (mocked AWS), so tests create fake leaked resources and assert what gets reported and deleted, without touching a real account
- Packaged with `pyproject.toml`; the same CI security gates as the services (Gitleaks, Semgrep, Trivy fs)
- Runs from GitHub Actions (`workflow_dispatch` + nightly schedule) using OIDC, so there are no AWS keys
- The Slack webhook URL comes from Secrets Manager
