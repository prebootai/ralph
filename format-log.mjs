import { createInterface } from "readline";

const rl = createInterface({ input: process.stdin });

let thinkingBuffer = "";
let assistantBuffer = "";
let lastAssistantHadModelCallId = false;

const dim = (s) => `\x1b[2m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;
const cyan = (s) => `\x1b[36m${s}\x1b[0m`;
const yellow = (s) => `\x1b[33m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const magenta = (s) => `\x1b[35m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;

const toolLabel = (toolCall) => {
  if (toolCall.readToolCall) return `Read ${dim(toolCall.readToolCall.args.path)}`;
  if (toolCall.writeToolCall) return `Write ${dim(toolCall.writeToolCall.args.path)}`;
  if (toolCall.editToolCall) return `Edit ${dim(toolCall.editToolCall.args.path)}`;
  if (toolCall.shellToolCall) return `Shell ${dim(truncate(toolCall.shellToolCall.args.command, 120))}`;
  if (toolCall.searchToolCall) return `Search ${dim(truncate(toolCall.searchToolCall.args.query, 120))}`;
  if (toolCall.grepToolCall) return `Grep ${dim(truncate(toolCall.grepToolCall.args.pattern, 120))}`;
  if (toolCall.globToolCall) return `Glob ${dim(toolCall.globToolCall.args.pattern)}`;
  if (toolCall.deleteToolCall) return `Delete ${dim(toolCall.deleteToolCall.args.path)}`;
  const key = Object.keys(toolCall)[0];
  return key ?? "unknown tool";
};

const toolResult = (toolCall) => {
  const inner = Object.values(toolCall)[0];
  if (!inner?.result) return "";
  if (inner.result.success) {
    const s = inner.result.success;
    if (typeof s.content === "string") return truncate(s.content, 200);
    if (typeof s === "string") return truncate(s, 200);
    return "ok";
  }
  if (inner.result.error) return `ERROR: ${truncate(String(inner.result.error), 200)}`;
  return "";
};

const truncate = (s, max) => {
  if (!s) return "";
  const oneLine = s.replace(/\n/g, " ").trim();
  return oneLine.length > max ? oneLine.slice(0, max) + "…" : oneLine;
};

const flushThinking = () => {
  if (!thinkingBuffer) return;
  process.stdout.write(`${magenta("[THINKING]")} ${thinkingBuffer.trim()}\n\n`);
  thinkingBuffer = "";
};

const flushAssistant = () => {
  if (!assistantBuffer) return;
  process.stdout.write(`${bold("[ASSISTANT]")} ${assistantBuffer.trim()}\n\n`);
  assistantBuffer = "";
};

rl.on("line", (line) => {
  if (!line.trim()) return;

  let event;
  try {
    event = JSON.parse(line);
  } catch {
    process.stdout.write(line + "\n");
    return;
  }

  switch (event.type) {
    case "system": {
      if (event.subtype === "init") {
        process.stdout.write(
          `${cyan("[INIT]")} model=${bold(event.model)} session=${dim(event.session_id)}\n` +
            `       cwd=${dim(event.cwd)}\n\n`
        );
      }
      break;
    }

    case "user": {
      const text = event.message?.content?.[0]?.text ?? "";
      process.stdout.write(`${yellow("[PROMPT]")} ${truncate(text, 200)}\n\n`);
      break;
    }

    case "thinking": {
      if (event.subtype === "delta") {
        thinkingBuffer += event.text;
      } else if (event.subtype === "completed") {
        flushThinking();
      }
      break;
    }

    case "assistant": {
      const text = event.message?.content?.[0]?.text ?? "";
      if (event.model_call_id) {
        if (!lastAssistantHadModelCallId) {
          flushAssistant();
        }
        lastAssistantHadModelCallId = true;
      } else {
        assistantBuffer += text;
        lastAssistantHadModelCallId = false;
      }
      break;
    }

    case "tool_call": {
      flushAssistant();
      if (event.subtype === "started") {
        process.stdout.write(`${green("[TOOL]")} ${toolLabel(event.tool_call)}\n`);
      } else if (event.subtype === "completed") {
        const result = toolResult(event.tool_call);
        if (result) {
          process.stdout.write(`${dim("  → " + result)}\n`);
        }
        process.stdout.write("\n");
      }
      break;
    }

    case "result": {
      flushAssistant();
      const text = event.result ?? event.message ?? "";
      if (text) process.stdout.write(`${bold("[RESULT]")} ${text}\n\n`);
      break;
    }

    case "error": {
      flushAssistant();
      const msg = event.error ?? event.message ?? JSON.stringify(event);
      process.stdout.write(`${red("[ERROR]")} ${msg}\n\n`);
      break;
    }
  }
});

rl.on("close", () => {
  flushThinking();
  flushAssistant();
});
