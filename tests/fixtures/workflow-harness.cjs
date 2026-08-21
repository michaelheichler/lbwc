#!/usr/bin/env node

const fs = require("node:fs");

const workflowFile = process.argv[2];
const responses = JSON.parse(process.argv[3]);
const record = { agentCalls: [], phaseCalls: [], logs: [], result: null };
let responseIndex = 0;

const source = fs.readFileSync(workflowFile, "utf8");
const firstNewline = source.indexOf("\n");
const metaLine = source.slice(0, firstNewline);
const body = source.slice(firstNewline + 1);

if (!/^export const meta = .*;$/.test(metaLine)) {
  throw new Error("rendered file's first line is not the expected meta declaration");
}

const phase = async (title) => {
  record.phaseCalls.push(title);
};

const agent = async (prompt, opts) => {
  record.agentCalls.push({
    label: opts.label,
    phase: opts.phase,
    hasSchema: Object.prototype.hasOwnProperty.call(opts, "schema"),
    hasEffort: Object.prototype.hasOwnProperty.call(opts, "effort"),
  });
  if (responseIndex >= responses.length) {
    throw new Error(`no scripted response left for call ${responseIndex} (label ${opts.label})`);
  }
  return responses[responseIndex++];
};

const log = async (message) => {
  record.logs.push(message);
};

const runBody = new Function("phase", "agent", "log", `return (async () => {\n${body}\n})();`);

runBody(phase, agent, log)
  .then((result) => {
    record.result = result;
    process.stdout.write(JSON.stringify(record));
  })
  .catch((err) => {
    process.stderr.write(`${err && err.stack ? err.stack : err}\n`);
    process.exit(1);
  });
