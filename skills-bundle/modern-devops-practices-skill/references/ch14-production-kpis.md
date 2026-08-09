# Chapter 14: Understanding Key Performance Indicators (KPIs) for Your Production Service

> Part 5: Operating Applications in Production · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to define, calculate, or reason about production-reliability KPIs (SLIs, SLOs, SLAs, error budgets, RTO/RPO), or when planning how to operate a distributed/microservice application using SRE principles. This is a concepts/theory chapter (no code or config), so use it for definitions, formulas, target-setting, and SRE operating practices, not for tool commands.

## Core concepts
- **Reliability matters because** it drives user satisfaction, business reputation, financial outcomes, competitive advantage, productivity, security, regulatory compliance, customer trust, maintainability, and the ability to scale. Most production issues are *non-functional* (scaling, resource sizing, crashes) and surface only in prod because dev teams cannot fully simulate production conditions.
- **SRE (Site Reliability Engineering)**: Google's implementation of DevOps from an Ops perspective. Core idea: let software engineers run production. Encourages shared ownership, common tooling, and learning from failures. Goal: build dependable apps without sacrificing delivery speed ("better software faster"). Aims for systems that are not just automated but self-regulating.
- **SRE staffing model**: Ideal SRE quickly tires of manual work and automates it, and can build software for complex problems. Google caps total "Ops" work (tickets, on-call, manual tasks) at **50%** of an SRE's time, guaranteeing the rest goes to engineering that improves the service. A pure-Ops team scales linearly with traffic. An engineering-focused SRE team does not.
- **Toil**: repetitive manual work. SREs reduce toil through automation to prevent burnout.
- **SLI (Service-Level Indicator)**: the *indicator of availability*. A carefully defined quantitative measure of some aspect of service quality (e.g., request latency, failure rate, throughput). Tied to specific **user journeys**.
- **SLO (Service-Level Objective)**: the *definition of availability*. A target level of reliability: the percentage of time the SLI must be met. Internal goal, no customer-facing penalty for missing it.
- **SLA (Service-Level Agreement)**: the *consequence of unavailability*. A formal/implicit business commitment to customers with repercussions (e.g., service credits) if breached.
- **Error budget**: `100% − SLO`. The permissible amount of downtime/errors before the SLO is violated, the "risk budget" available for shipping features, maintenance, and absorbing disruptions.
- **Disaster recovery (DR)**: planning, policies, procedures, and tech to restore critical IT systems, data, and operations quickly after disruptive events (disasters, cyberattacks, failures).
- **RTO (Recovery Time Objective)**: maximum acceptable *downtime*, how fast the system must be restored after a disruption.
- **RPO (Recovery Point Objective)**: maximum tolerable *data loss*, the point in time to which data must be recoverable. Lower RPO needs more frequent backups/replication.

## Four Golden Signals (Google)
The four SLIs that apply to most user journeys:
- **Latency**: time to respond to user requests.
- **Errors**: percentage of failed requests.
- **Traffic**: demand directed at the service (usage level).
- **Saturation**: how fully infrastructure components are used.

## Key formulas
```
SLI          = (Good Events * 100) / Valid Events     # 100 = all good, 0 = widespread failure
Error Budget = 100% − SLO
```

### Error budget per month by SLO (30 days × 24h)
| SLO     | Error budget | Downtime / month |
|---------|--------------|------------------|
| 99%     | 1%           | 7.2 hours        |
| 99.9%   | 0.1%         | 43.2 minutes     |
| 99.99%  | 0.01%        | 4.32 minutes     |

Note: these are *actual downtime* figures. Redundancy, HA, and DR can effectively extend usable budget because the service stays up while you patch one server.

## Workflows (how-to)

### Define a good SLI
1. Tie the metric to a **user journey** (a sequence of user actions toward a goal, e.g., "create a new blog post").
2. Pick a metric that **correlates with customer satisfaction**. A lower SLI value must mean lower satisfaction. If there's no correlation, it's not worth measuring.
   - Example: **Latency is a good SLI**, satisfaction drops as latency rises (notably past 300ms and 500ms). **CPU use is a bad SLI**, no satisfaction correlation until ~80%.
3. Prefer the **Four Golden Signals** (latency, errors, traffic, saturation) over resource metrics (CPU/memory/disk).
4. **Limit to ~4-5 SLIs.** Too many cause confusion and false alarms.
5. **Prioritize user journeys**: weight critical journeys higher (e.g., create/update post) over minor ones (reviews/ratings).
6. Express SLIs precisely. Bad: "the website is slow." Good: "the 95th percentile of response time over a 15-minute window should not exceed 300ms."

### Set an SLO
1. Combine one or more SLIs into a target. Form: "Meet [SLI] **x%** of the time" (e.g., the 95th-percentile-latency-under-500ms-over-15min SLI must hold 99% of the time → 99% SLO).
2. **Do not aim for 100%.** It's costly, complex, usually unnecessary, and leaves no room to ship features (every change risks the service). Users can't distinguish 100% from 99.999% because intermediary systems (their PC, home Wi-Fi, ISP, power grid) are collectively far less reliable anyway.
3. Choosing the right target is a **product question**, not a technical one. Consider:
   - **User satisfaction**: what availability keeps users content given their usage patterns.
   - **Alternatives**: what dissatisfied users could switch to.
   - **User behavior**: how usage changes at different availability levels.
4. Make it **realistic and customer-aligned**: meeting the SLO should mean customers perceive no quality issues. Small dips below shouldn't trigger support tickets.
5. Get **organization-wide consensus** (devs, PMs, SREs, CTO). Missing the SLO has no customer penalty but typically forces fewer changes / reduced feature work and more focus on quality/testing.
6. Optionally maintain two SLOs: an **achievable** SLO (team target) and an **aspirational** SLO (stretch goal in continuous improvement).

### Set an SLA
1. Set the SLA at a **looser SLI threshold than the SLO** so meeting the SLO automatically satisfies the SLA (safety margin).
   - Example: latency SLO at **300ms**, SLA at **500ms**.
2. Set it just strict enough to keep customers from leaving. SLAs are external/business commitments with consequences (explicit: service credits, implicit: reputation damage, churn risk).

### Latency example: how customer experience maps to thresholds
- **≤ 300ms (SLO)**: all good.
- **300-500ms**: mild degradation, not bad enough to raise tickets. Set the **SLA at 500ms**.
- **> 500ms**: customers unhappy, start raising support tickets for slowness.
- **> 10s**: "everything is burning," Ops crisis.

### Calculate and use an error budget
1. `Error Budget = 100% − SLO`. Convert to a time allowance over your window (see table).
2. Treat failures as natural/expected. Spend the budget on releases, maintenance, enhancements, and absorbing infra/network disruptions.
3. **If the error budget is exhausted, freeze risky changes** and shift focus to stability/reliability over new features.
4. Decide how many "9s" to chase based on end users, business criticality, and availability needs, higher SLO means more cost/resources. Good architecture alone can often raise the achievable SLO.

### Plan disaster recovery (choose RTO/RPO)
1. Pick a DR mechanism along a cost/resilience spectrum: periodic **backups/snapshots** (cheaper, higher RTO/RPO) → **failover replicas** of production (most resilient, ~doubles infrastructure cost).
2. Set **RTO** = max acceptable downtime. **RPO** = max tolerable data loss. Lower RPO ⇒ more frequent backups/replication.
3. Shorter RTO/RPO ⇒ more robust DR plan ⇒ higher infra + people cost. Balance them against business needs.

### Run a distributed application in production (SRE checklist)
Microservices add complexity over monoliths. Apply SRE practices:
1. **SLOs**: define acceptable latency, error rate, availability.
2. **SLIs**: set quantifiable metrics (response times, error rates) to measure against SLOs.
3. **Error budgets**: balance reliability vs. innovation, exhausting the budget triggers a stability focus.
4. **Monitoring & alerting**: continuous tracking, alert on SLIs/SLOs. For microservices, a **service mesh (Istio or Linkerd)** gives a single pane of glass for observability and alerting. (Istio is the focus of the next chapter.)
5. **Capacity planning**: size infra for expected load, use cloud auto-scaling to absorb spikes.
6. **Automated remediation**: auto-scaling, self-healing, automated rollback to cut downtime.
7. **Chaos engineering**: inject controlled failures to expose weaknesses proactively.
8. **On-call & incident management**: 24/7 rotations, defined incident processes, learn from incidents (most SRE backlog originates here).
9. **Continuous improvement**: run **PIRs (post-incident reviews)** and **RCAs (root cause analyses)**, refine SLOs from lessons learned.
10. **Documentation & knowledge sharing**: runbooks and operational procedures, automate runbooks to minimize manual work and avoid siloed expertise.

## Decision guidance and best practices
- **Cap Ops work at 50%** of SRE time. The rest must be engineering/automation, or the team gets buried as the service grows.
- **Pick SLIs that track satisfaction** (latency, errors), not infrastructure metrics (CPU/memory) that don't correlate with user pain.
- **Keep SLIs to 4-5.** More = confusion and false alarms.
- **Never set a 100% SLO**: wasteful, blocks feature velocity, imperceptible to users.
- **SLA threshold should be looser than the SLO** so the SLO acts as an internal buffer protecting the external commitment.
- **Use error budgets as the throttle** between innovation and stability. When spent, stop shipping risky changes.
- **Match DR investment (RTO/RPO) to business criticality**: failover replicas only where the cost is justified.
- **For microservices, adopt a service mesh** (Istio/Linkerd) for unified monitoring/alerting.
- **Automate runbooks and remediation** to reduce toil and prevent SRE burnout.

## Pitfalls and gotchas
- Aiming for **100% reliability** is misguided: costly, technically complex, blocks new features, and indistinguishable from 99.999% to users behind unreliable ISPs/Wi-Fi/power.
- Using **CPU/memory use as an SLI**: no clear correlation with customer satisfaction until extreme thresholds (~80% CPU).
- **Vague SLIs** ("site is slow") are useless. Always specify percentile, window, and threshold.
- **Too many SLIs** cause alert fatigue and false alarms.
- **Setting SLA stricter than SLO** removes your safety margin. Do the reverse.
- Treating an unmet SLO as consequence-free: it should drive fewer changes and more testing/quality focus even though there's no customer penalty.
- **Confusing RTO and RPO**: RTO = downtime tolerance (time to restore), RPO = data-loss tolerance (recovery point).
- **A fully reliable system leaves no error budget** for change. Bake in margin.

## Quick-fact cheat-sheet
- **SLI**: quantitative reliability metric tied to a user journey, `SLI = (Good Events * 100) / Valid Events`.
- **SLO**: target % of time the SLI is met, internal, no customer penalty.
- **SLA**: external commitment with consequences, set looser than the SLO.
- **Error Budget**: `100% − SLO`, risk allowance for change.
- **Four Golden Signals**: Latency, Errors, Traffic, Saturation.
- **Toil**: repetitive manual work SREs automate away.
- **50% rule**: max Ops work share for an SRE.
- **RTO**: max downtime. **RPO**: max data loss.
- **PIR / RCA**: post-incident review / root cause analysis.
- **Service mesh**: Istio or Linkerd for distributed-app observability/alerting.
- **Chaos tools**: Chaos Monkey, Gremlin, Chaos Toolkit, Chaos Blade, Pumba, ToxiProxy, Chaos Mesh.

## Exam-style answer keys (from chapter)
- Good SLI example: "The 95th percentile of response time in a 15-minute window should not exceed 300ms."
- 100% SLO for a mature org? **False.**
- SLOs carry no customer-initiated punitive action? **True.**
- SLO decision factors: **user satisfaction, alternatives, user behavior** (not system capacity).
- SLAs are set to a stricter SLI value than SLOs? **False** (looser).
- SLI factors to consider: **latency, errors, traffic, saturation**.
- 1% error budget per month = **7.2 hours**.
- An SRE is a software developer doing Ops? **True.**
- Minimum SRE time on development work = **50%**.

## Where this is covered (topic index)
- **Why reliability matters / reliability importance** → Core concepts (first bullet) + reliability rationale list.
- **SRE / Site Reliability Engineering / Google SRE model / 50% rule / toil** → Core concepts, "50% rule" in cheat-sheet.
- **SLI / service-level indicator / how to calculate SLI** → Core concepts, Key formulas, "Define a good SLI."
- **Golden signals / latency, errors, traffic, saturation** → Four Golden Signals section.
- **SLO / service-level objective / why not 100% / achievable vs aspirational** → Core concepts, "Set an SLO."
- **SLA / service-level agreement / service credits** → Core concepts, "Set an SLA."
- **Error budget / 99 vs 99.9 vs 99.99 / downtime per month** → Error budget table, "Calculate and use an error budget."
- **Disaster recovery / RTO / RPO / backups vs failover replicas** → Core concepts, "Plan disaster recovery."
- **Microservices in production / distributed app SRE practices / monitoring / chaos engineering / on-call / PIR / RCA** → "Run a distributed application in production."
- **Service mesh / Istio / Linkerd (observability)** → distributed-app checklist step 4 (Istio detailed in Chapter 15).
- **User journeys** → "Define a good SLI" steps 1-2 and 5.
