# Cost risks for Microsoft Foundry workloads

Use this reference when a cost question is really a risk question: "what could make
this expensive?", "what could an agent/tool loop burn?", or "what cost is not visible
in the Azure meter estimate?"

References:

- [OWASP GenAI Security Project](https://genai.owasp.org/)
- [OWASP Agentic AI threats and mitigations](https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/)

## Direct vs indirect cost

| Cost type | What it is | Examples in this repo |
| --- | --- | --- |
| Direct Azure meter spend | Billable cloud usage or license/PAYG consumption | Foundry model tokens/PTUs, Azure AI Search, Log Analytics, Content Safety, Purview PAYG, Defender plans, APIM, hosted compute, memory |
| Indirect remediation/business cost | Cost caused by bad agent behavior, governance gaps, incidents, or cleanup | Investigating runaway agents, deleting leaked data, responding to policy violations, reindexing Search, incident response, tenant/admin review |

Do not mix these in one dollar total unless the user explicitly asks for a business
risk estimate. For normal deployment estimates, report indirect cost as risk, not
Azure spend.

## Agentic risk mapping

| Cost risk | Agentic / OWASP-style risk lens | Cost implication |
| --- | --- | --- |
| Runaway model/tool loops | Unbounded consumption, tool misuse, excessive agency | Token, hosted compute, tool, APIM, Search, and telemetry bills can grow without adding user value. |
| Prompt/tool manipulation | Prompt injection, goal hijacking, tool misuse | The agent can be induced to call expensive tools or retrieve/process unnecessary data. |
| Over-broad identity or permissions | Excessive agency, identity/privilege abuse | A compromised or over-privileged agent can access paid services or tenant features outside the intended workload. |
| Weak data boundaries | Sensitive information disclosure / unauthorized access | Remediation can involve Purview, eDiscovery, incident response, reindexing, and data cleanup costs. |
| Poor observability | Insufficient monitoring/oversight | Low telemetry hides runaway spend; excessive telemetry creates Log Analytics cost. |
| External tool/service dependencies | Supply-chain / third-party service risk | Costs may shift to APIM, SaaS licenses, MCP hosts, or external APIs not visible in Bicep. |
| Compliance-only confidence | Governance-control gap | Read-only or audit-only surfaces can create a false sense of control; remediation happens elsewhere and may cost more. |

## Cost review posture

- Treat cost-risk controls as part of agent safety, not just billing hygiene.
- Separate "this resource has a meter" from "this design can create runaway spend."
- Look for caps, quotas, rate limits, human review, narrow permissions, and telemetry
  proportional to the risk.
