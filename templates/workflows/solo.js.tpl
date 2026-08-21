const JOB = @@JOB@@;
const TASK_ID = @@TASK_ID@@;
const ROLE = @@ROLE@@;
const AGENT_TYPE = @@AGENT_TYPE@@;
const MODEL = @@MODEL@@;
const EFFORT = @@EFFORT@@;

const QA_VERDICT_SCHEMA = {
  type: "object",
  required: ["id", "type", "task", "author_role", "timestamp", "payload"],
  properties: {
    id: { type: "string" },
    type: { const: "qa_verdict" },
    phase: { type: "number" },
    task: { type: "string" },
    author_role: { type: "string" },
    timestamp: { type: "string" },
    schema_version: { type: "string" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    payload: {
      type: "object",
      required: ["result"],
      properties: {
        tier: { type: "string", enum: ["quick", "standard", "deep"] },
        result: { type: "string", enum: ["PASS", "FAIL", "PARTIAL"] },
        checks: { type: "object" },
        failures: { type: "array" },
        checks_detail: { type: "array" },
        body: { type: "string" },
        recommendations: { type: "array", items: { type: "string" } },
        pre_existing_issues: { type: "array" },
      },
    },
  },
};

const BASE_AGENT_OPTIONS = {
  agentType: AGENT_TYPE,
  label: ROLE,
  phase: "Execute",
  model: MODEL,
  ...(EFFORT === null ? {} : { effort: EFFORT }),
};
const AGENT_OPTIONS = ROLE === "qa" ? { ...BASE_AGENT_OPTIONS, schema: QA_VERDICT_SCHEMA } : BASE_AGENT_OPTIONS;

await phase("Execute");

const result = await agent(JOB, AGENT_OPTIONS);

return { status: "complete", task_id: TASK_ID, role: ROLE, result };
