const JOB = @@JOB@@;
const TASK_ID = @@TASK_ID@@;
const AUTONOMY = @@AUTONOMY@@;
const ENGINEER_AGENT_TYPE = @@ENGINEER_AGENT_TYPE@@;
const ENGINEER_MODEL = @@ENGINEER_MODEL@@;
const ENGINEER_EFFORT = @@ENGINEER_EFFORT@@;
const CRITIC_AGENT_TYPE = @@CRITIC_AGENT_TYPE@@;
const CRITIC_MODEL = @@CRITIC_MODEL@@;
const CRITIC_EFFORT = @@CRITIC_EFFORT@@;
const TESTDEV_AGENT_TYPE = @@TESTDEV_AGENT_TYPE@@;
const TESTDEV_MODEL = @@TESTDEV_MODEL@@;
const TESTDEV_EFFORT = @@TESTDEV_EFFORT@@;

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

const TESTS_READY_SCHEMA = {
  type: "object",
  required: ["id", "type", "task", "author_role", "timestamp", "payload"],
  properties: {
    id: { type: "string" },
    type: { const: "tests_ready" },
    phase: { type: "number" },
    task: { type: "string" },
    author_role: { type: "string" },
    timestamp: { type: "string" },
    schema_version: { type: "string" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    payload: {
      type: "object",
      required: ["test_files", "failing_test_count", "test_command"],
      properties: {
        plan_id: { type: "string" },
        test_files: { type: "array", items: { type: "string" } },
        failing_test_count: { type: "number" },
        test_command: { type: "string" },
      },
    },
  },
};

const CRITIC_VERDICT_SCHEMA = {
  type: "object",
  required: ["verdict"],
  properties: {
    verdict: { type: "string", enum: ["BLOCK", "PASS"] },
    owner: { type: "string", enum: ["SOURCE", "TESTS", "BOTH"] },
    findings: { type: "string" },
  },
};

const VALID_OWNERS = ["SOURCE", "TESTS", "BOTH"];

function engineerPrompt(feedback) {
  return feedback
    ? `${JOB}\n\nThe critic found this on the prior round, fix every point before returning:\n${feedback}`
    : JOB;
}

function testDevPrompt(engineerResult, feedback) {
  const base = `Write or update the tests for this execution_update payload for task ${TASK_ID}:\n\n${JSON.stringify(engineerResult)}`;
  return feedback ? `${base}\n\nThe critic found this on the prior round, fix every point before returning:\n${feedback}` : base;
}

function criticPrompt(engineerResult, testsResult) {
  return `Review this execution_update payload and its tests_ready payload for task ${TASK_ID}:\n\nCode:\n${JSON.stringify(engineerResult)}\n\nTests:\n${JSON.stringify(testsResult)}`;
}

function withEffort(options, effort) {
  return effort === null ? options : { ...options, effort };
}

await phase("Implement");
await phase("Build Tests");
await phase("Verify");

let round = 0;
let engineerResult = null;
let testsResult = null;
let critique = null;
let verdict = "BLOCK";
let owner = "BOTH";
let engineerFeedback = "";
let testdevFeedback = "";
let critiqueFindings = "";

while (true) {
  round += 1;
  const rerunEngineer = round === 1 || owner === "SOURCE" || owner === "BOTH";
  const rerunTestDev = round === 1 || owner === "TESTS" || owner === "BOTH";

  if (rerunEngineer) {
    engineerResult = await agent(engineerPrompt(engineerFeedback), withEffort({
      agentType: ENGINEER_AGENT_TYPE,
      label: "engineer",
      phase: "Implement",
      schema: EXECUTION_UPDATE_SCHEMA,
      model: ENGINEER_MODEL,
    }, ENGINEER_EFFORT));
  }

  if (rerunTestDev) {
    testsResult = await agent(testDevPrompt(engineerResult, testdevFeedback), withEffort({
      agentType: TESTDEV_AGENT_TYPE,
      label: "test-dev",
      phase: "Build Tests",
      schema: TESTS_READY_SCHEMA,
      model: TESTDEV_MODEL,
    }, TESTDEV_EFFORT));
  }

  critique = await agent(criticPrompt(engineerResult, testsResult), withEffort({
    agentType: CRITIC_AGENT_TYPE,
    label: "critic",
    phase: "Verify",
    schema: CRITIC_VERDICT_SCHEMA,
    model: CRITIC_MODEL,
  }, CRITIC_EFFORT));

  verdict = critique && critique.verdict === "PASS" ? "PASS" : "BLOCK";
  if (verdict === "PASS") {
    break;
  }

  owner = critique && VALID_OWNERS.includes(critique.owner) ? critique.owner : "BOTH";
  critiqueFindings = (critique && critique.findings) || "";
  engineerFeedback = owner === "SOURCE" || owner === "BOTH" ? critiqueFindings : "";
  testdevFeedback = owner === "TESTS" || owner === "BOTH" ? critiqueFindings : "";

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
    tests: testsResult,
    critic: critique,
  };
}

return {
  status: "user_decision_required",
  decision: "workflow_gate_unresolved",
  question: `Round ${round} of remediation on ${TASK_ID} did not reach PASS. Continue remediation?`,
  choices: ["Continue remediation", "Stop and report"],
  context: critiqueFindings,
};
