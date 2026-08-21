const JOB = @@JOB@@;
const TASK_ID = @@TASK_ID@@;
const AUTONOMY = @@AUTONOMY@@;
const ENGINEER_AGENT_TYPE = @@ENGINEER_AGENT_TYPE@@;
const ENGINEER_MODEL = @@ENGINEER_MODEL@@;
const ENGINEER_EFFORT = @@ENGINEER_EFFORT@@;
const CRITIC_AGENT_TYPE = @@CRITIC_AGENT_TYPE@@;
const CRITIC_MODEL = @@CRITIC_MODEL@@;
const CRITIC_EFFORT = @@CRITIC_EFFORT@@;

const MAX_ROUNDS = 3;

const EXECUTION_UPDATE_SCHEMA = {
  type: "object",
  required: ["id", "type", "task", "author_role", "timestamp", "payload"],
  properties: {
    id: { type: "string" },
    type: { const: "execution_update" },
    phase: { type: "number" },
    task: { type: "string" },
    author_role: { type: "string" },
    timestamp: { type: "string" },
    schema_version: { type: "string" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    payload: {
      type: "object",
      required: ["task_id", "status", "files_modified", "evidence"],
      properties: {
        plan_id: { type: "string" },
        task_id: { type: "string" },
        status: { type: "string", enum: ["complete", "partial", "failed"] },
        commit: { type: "string" },
        files_modified: { type: "array", items: { type: "string" } },
        concerns: { type: "array", items: { type: "string" } },
        evidence: { type: "string" },
        pre_existing_issues: {
          type: "array",
          items: {
            type: "object",
            properties: {
              test: { type: "string" },
              file: { type: "string" },
              error: { type: "string" },
            },
          },
        },
      },
    },
  },
};

const CRITIC_VERDICT_SCHEMA = {
  type: "object",
  required: ["verdict"],
  properties: {
    verdict: { type: "string", enum: ["BLOCK", "PASS"] },
    findings: { type: "string" },
  },
};

function engineerPrompt(feedback) {
  return feedback
    ? `${JOB}\n\nThe critic found this on the prior round, fix every point before returning:\n${feedback}`
    : JOB;
}

function criticPrompt(engineerResult) {
  return `Review this execution_update payload for task ${TASK_ID}:\n\n${JSON.stringify(engineerResult)}`;
}

function withEffort(options, effort) {
  return effort === null ? options : { ...options, effort };
}

await phase("Implement");
await phase("Review");

let round = 0;
let engineerResult = null;
let critique = null;
let verdict = "BLOCK";
let feedback = "";

while (true) {
  round += 1;

  engineerResult = await agent(engineerPrompt(feedback), withEffort({
    agentType: ENGINEER_AGENT_TYPE,
    label: "engineer",
    phase: "Implement",
    schema: EXECUTION_UPDATE_SCHEMA,
    model: ENGINEER_MODEL,
  }, ENGINEER_EFFORT));

  critique = await agent(criticPrompt(engineerResult), withEffort({
    agentType: CRITIC_AGENT_TYPE,
    label: "critic",
    phase: "Review",
    schema: CRITIC_VERDICT_SCHEMA,
    model: CRITIC_MODEL,
  }, CRITIC_EFFORT));

  verdict = critique && critique.verdict === "PASS" ? "PASS" : "BLOCK";
  if (verdict === "PASS") {
    break;
  }

  feedback = (critique && critique.findings) || "";
  if (round >= MAX_ROUNDS && AUTONOMY !== "pure-vibe") {
    break;
  }
}

if (verdict === "PASS") {
  return {
    status: "complete",
    task_id: TASK_ID,
    round,
    engineer: engineerResult,
    critic: critique,
  };
}

return {
  status: "user_decision_required",
  decision: "workflow_gate_unresolved",
  question: `Round ${round} of remediation on ${TASK_ID} did not reach PASS. Continue remediation?`,
  choices: ["Continue remediation", "Stop and report"],
  context: feedback,
};
