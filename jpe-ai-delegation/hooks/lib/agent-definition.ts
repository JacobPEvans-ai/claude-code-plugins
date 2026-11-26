import type { HarnessMcpServer, Sandbox } from './policy'

export type AgentDefinition = { model?: string; prompt: string; tools?: string[]; disallowedTools?: string[]; egress?: 'network'; mcpServers?: Record<string, HarnessMcpServer> }
const WRITERS = ['Edit', 'Write', 'NotebookEdit', 'Bash']
const CODEX_TOOLS = ['Read', 'Grep', 'Glob', ...WRITERS]

// Decode YAML scalar escapes without requiring a parser in the hook VM.
function quotedScalar(raw: string): string {
  if (!raw.startsWith('"')) return raw.startsWith("'") ? raw.slice(1, -1).replace(/''/g, "'") : raw
  const escapes: Record<string, string> = { '0': '\0', a: '\x07', b: '\b', t: '\t', n: '\n', v: '\v', f: '\f', r: '\r', e: '\x1b', ' ': ' ', '"': '"', '/': '/', '\\': '\\', N: '\x85', _: '\u00a0', L: '\u2028', P: '\u2029' }
  return raw.slice(1, -1).replace(/\\(x[\da-fA-F]{2}|u[\da-fA-F]{4}|U[\da-fA-F]{8}|.)/g, (_, escaped: string) => {
    if (/^[xuU]/.test(escaped)) return String.fromCodePoint(parseInt(escaped.slice(1), 16))
    if (!(escaped in escapes)) throw new Error('invalid quoted agent scalar')
    return escapes[escaped]!
  })
}

function scalar(raw: string, tool = false): string {
  let value = raw.trim()
  const quoted = value.match(/^("(?:[^"\\]|\\.)*"|'(?:[^']|'')*')(?:[ \t]+#.*)?$/)
  if (quoted) return quotedScalar(quoted[1]!)
  value = value.replace(/[ \t]+#.*$/, '').trim()
  if (!value || /^[\[\]{}&*!|>'"`]/.test(value) || (!tool && (/[\[\]{}&*!|>'"`\n\r]/.test(value) || /:\s/.test(value)))) throw new Error('unsupported frontmatter scalar')
  return value
}

// Commas inside a quoted entry or a tool selector belong to that entry.
function toolEntries(value: string): string[] {
  const entries: string[] = []
  let start = 0
  let depth = 0
  let quote = ''
  for (let i = 0; i < value.length; i++) {
    const char = value[i]
    if (quote) {
      if (char === '\\' && quote === '"') i++
      else if (char === quote) {
        if (quote === "'" && value[i + 1] === "'") i++
        else quote = ''
      }
    } else if (char === '"' || char === "'") quote = char
    else if (char === '(') depth++
    else if (char === ')') {
      if (--depth < 0) throw new Error('invalid tool selector')
    } else if (char === ',' && depth === 0) {
      entries.push(value.slice(start, i).trim())
      start = i + 1
    }
  }
  if (quote || depth) throw new Error('unterminated tool entry')
  entries.push(value.slice(start).trim())
  return entries
}

function validateTools(tools: string[]): string[] {
  if (tools.some((tool) => /^(?:null|true|false|yes|no|on|off)$/i.test(tool) || !/^(?:\*|mcp__[\w-]+__(?:[\w-]+\*?|\*)|[A-Za-z]\w*(?:\([^\r\n]*\))?)$/.test(tool))) throw new Error('invalid tool name')
  return tools
}

function toolList(raw: string): string[] {
  const value = raw.trim()
  let tools: string[]
  if (value.startsWith('[')) {
    const list = value.match(/^\[([\s\S]*)\](?:[ \t]+#.*)?$/)
    if (!list) throw new Error('invalid tool list')
    const body = list[1]!.trim().replace(/,\s*$/, '')
    tools = body ? toolEntries(body).map((entry) => scalar(entry, true)) : []
  } else {
    tools = toolEntries(scalar(value, true))
  }
  return validateTools(tools)
}

function flowParts(raw: string): string[] {
  const parts: string[] = []
  let start = 0
  let square = 0
  let curly = 0
  let quote = ''
  for (let i = 0; i < raw.length; i++) {
    const char = raw[i]
    if (quote) {
      if (char === '\\' && quote === '"') i++
      else if (char === quote) {
        if (quote === "'" && raw[i + 1] === "'") i++
        else quote = ''
      }
    } else if (char === '"' || char === "'") quote = char
    else if (char === '[') square++
    else if (char === ']') { if (--square < 0) throw new Error('invalid MCP flow value') }
    else if (char === '{') curly++
    else if (char === '}') { if (--curly < 0) throw new Error('invalid MCP flow value') }
    else if (char === ',' && square === 0 && curly === 0) { parts.push(raw.slice(start, i).trim()); start = i + 1 }
  }
  if (quote || square || curly) throw new Error('invalid MCP flow value')
  parts.push(raw.slice(start).trim())
  if (parts.some((part) => !part)) throw new Error('invalid MCP flow value')
  return parts
}

function pair(raw: string): [string, string] {
  let quote = ''
  for (let i = 0; i < raw.length; i++) {
    const char = raw[i]
    if (quote) {
      if (char === '\\' && quote === '"') i++
      else if (char === quote) quote = ''
    } else if (char === '"' || char === "'") quote = char
    else if (char === ':') return [raw.slice(0, i).trim(), raw.slice(i + 1).trim()]
  }
  throw new Error('invalid MCP mapping')
}

function plainString(raw: string): string {
  const value = scalar(raw)
  if (/^(?:~|null|true|false|yes|no|on|off|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?|0[xX][\da-fA-F]+|0[oO][0-7]+|0[bB][01]+|\d{4}-\d{2}-\d{2}(?:[Tt ]|$))$/i.test(value)) throw new Error('MCP value is not a string')
  return value
}

function cleanValue(raw: string): string {
  return raw.startsWith('"') || raw.startsWith("'") ? raw : raw.replace(/[ \t]+#.*$/, '').trim()
}

function flowMap(raw: string): [string, string][] {
  const value = raw.trim()
  if (!value.startsWith('{') || !value.endsWith('}')) throw new Error('invalid MCP mapping')
  const body = value.slice(1, -1).trim()
  return body ? flowParts(body).map(pair) : []
}

function flowStrings(raw: string): string[] {
  const value = raw.trim()
  if (!value.startsWith('[') || !value.endsWith(']')) throw new Error('invalid MCP string list')
  const body = value.slice(1, -1).trim()
  return body ? flowParts(body).map(plainString) : []
}

function stringMap(pairs: [string, string][]): Record<string, string> {
  const result = Object.create(null) as Record<string, string>
  for (const [rawKey, rawValue] of pairs) {
    const key = plainString(rawKey)
    if (Object.prototype.hasOwnProperty.call(result, key)) throw new Error('duplicate MCP environment key')
    const value = cleanValue(rawValue)
    if (!value) throw new Error('MCP environment values must be strings')
    result[key] = plainString(value)
  }
  return result
}

function serverField(key: string, raw: string): unknown {
  const value = cleanValue(raw)
  if (!value) throw new Error('empty MCP server field')
  if (key === 'type' || key === 'command') return plainString(value)
  if (key === 'args') return flowStrings(value)
  if (key === 'env') return stringMap(flowMap(value))
  throw new Error('unknown MCP server field')
}

function makeServer(fields: Map<string, unknown>): HarnessMcpServer {
  for (const key of fields.keys()) if (!['type', 'command', 'args', 'env'].includes(key)) throw new Error('unknown MCP server field')
  const type = fields.get('type')
  const command = fields.get('command')
  if (type !== 'stdio' || typeof command !== 'string' || !command.startsWith('/')) throw new Error('MCP server needs stdio and an absolute command path')
  const args = fields.get('args')
  const env = fields.get('env')
  if (args !== undefined && (!Array.isArray(args) || !args.every((arg) => typeof arg === 'string'))) throw new Error('MCP args must be strings')
  if (env !== undefined && (!env || typeof env !== 'object' || Array.isArray(env) || !Object.values(env).every((value) => typeof value === 'string'))) throw new Error('MCP environment values must be strings')
  return { type: 'stdio', command, ...(args === undefined ? {} : { args: args as string[] }), ...(env === undefined ? {} : { env: env as Record<string, string> }) }
}

function parseMcpServers(lines: string[]): Record<string, HarnessMcpServer> {
  const entries = lines.flatMap((line) => {
    if (/^\s*\t/.test(line)) throw new Error('tabs are not supported in MCP configuration')
    const content = line.trim()
    return !content || content.startsWith('#') ? [] : [{ indent: line.length - line.trimStart().length, content }]
  })
  if (!entries.length) throw new Error('MCP server list is empty')
  const servers = Object.create(null) as Record<string, HarnessMcpServer>
  let index = 0
  let listIndent: number | undefined
  while (index < entries.length) {
    const item = entries[index]!
    const listItem = item.content.match(/^-\s+(.+)$/)
    if (!listItem || (listIndent !== undefined && item.indent !== listIndent)) throw new Error('MCP servers must be a list of single-key maps')
    listIndent = item.indent
    const [rawName, rawConfig] = pair(listItem[1]!)
    const name = plainString(rawName)
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(name) || Object.prototype.hasOwnProperty.call(servers, name)) throw new Error('invalid or duplicate MCP server name')
    index++
    const fields = new Map<string, unknown>()
    const inline = cleanValue(rawConfig)
    if (inline) {
      for (const [rawKey, rawValue] of flowMap(inline)) {
        const key = plainString(rawKey)
        if (fields.has(key)) throw new Error('duplicate MCP server field')
        fields.set(key, serverField(key, rawValue))
      }
    } else {
      const fieldIndent = entries[index]?.indent
      if (fieldIndent === undefined || fieldIndent <= listIndent) throw new Error('MCP server map is empty')
      while (index < entries.length && entries[index]!.indent > listIndent) {
        const field = entries[index]!
        if (field.indent !== fieldIndent || field.content.startsWith('-')) throw new Error('invalid MCP server map indentation')
        const [rawKey, rawValue] = pair(field.content)
        const key = plainString(rawKey)
        if (fields.has(key)) throw new Error('duplicate MCP server field')
        const value = cleanValue(rawValue)
        index++
        if (value) fields.set(key, serverField(key, value))
        else if (key === 'args') {
          const args: string[] = []
          while (index < entries.length && entries[index]!.indent > fieldIndent) {
            const item = entries[index]!
            const list = item.content.match(/^-\s+(.+)$/)
            if (item.indent !== fieldIndent + 2 || !list) throw new Error('invalid MCP args list')
            args.push(plainString(cleanValue(list[1]!)))
            index++
          }
          if (!args.length) throw new Error('MCP args must use [] when empty')
          fields.set(key, args)
        } else if (key === 'env') {
          const pairs: [string, string][] = []
          while (index < entries.length && entries[index]!.indent > fieldIndent) {
            const item = entries[index]!
            if (item.indent !== fieldIndent + 2 || item.content.startsWith('-')) throw new Error('invalid MCP environment map')
            pairs.push(pair(item.content))
            index++
          }
          if (!pairs.length) throw new Error('MCP env must use {} when empty')
          fields.set(key, stringMap(pairs))
        } else throw new Error('MCP type and command must be strings')
      }
    }
    if (index < entries.length && entries[index]!.indent > listIndent) throw new Error('unexpected MCP configuration continuation')
    servers[name] = makeServer(fields)
  }
  return servers
}

// The hook VM has no YAML parser: accept plain top-level keys and bounded policy values.
export function parseAgentDefinition(text: string): AgentDefinition {
  const frontmatter = text.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/)
  if (!frontmatter) {
    if (/^\s*---|\b(?:tools|disallowedTools|model)\s*:/.test(text)) throw new Error('invalid agent frontmatter')
    return { prompt: '' }
  }
  const definition: AgentDefinition = { prompt: text.slice(frontmatter[0].length).trim() }
  const lines = frontmatter[1]!.split(/\r?\n/)
  const seen = new Set<string>()
  let parent: string | undefined
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!
    if (!line.trim() || /^\s*#/.test(line)) continue
    if (line.startsWith(' ') && parent) continue
    const field = line.match(/^([A-Za-z_][\w-]*)[ \t]*:([ \t]|$)/)
    if (!field) throw new Error('unsupported agent frontmatter key')
    const key = parent = field[1]!
    if (key !== 'model' && key !== 'tools' && key !== 'disallowedTools' && key !== 'egress' && key !== 'mcpServers') continue
    if (seen.has(key)) throw new Error('duplicate agent frontmatter key')
    seen.add(key)
    const value = line.slice(field[0].length).trim().replace(/^#.*$/, '')
    const continuation: string[] = []
    while (i + 1 < lines.length && (!lines[i + 1]!.trim() || /^\s*#/.test(lines[i + 1]!) || lines[i + 1]!.startsWith(' '))) {
      const line = lines[++i]!
      if (line.trim() && !/^\s*#/.test(line)) continuation.push(line)
    }
    const toolField = key === 'tools' || key === 'disallowedTools'
    if (key === 'mcpServers') {
      if (cleanValue(value)) throw new Error('invalid MCP server configuration')
      try { definition.mcpServers = parseMcpServers(continuation) } catch { throw new Error('invalid MCP server configuration') }
    } else if (toolField && !value) {
      if (!continuation.length) throw new Error('empty agent tool field requires []')
      let indent: number | undefined
      definition[key] = validateTools(continuation.map((line) => {
        const item = line.match(/^( +)-[ \t]+(.+)$/)
        if (!item || (indent !== undefined && item[1]!.length !== indent)) throw new Error('unsupported agent tool list entry')
        indent = item[1]!.length
        return scalar(item[2]!, true)
      }))
    } else {
      if (continuation.length) throw new Error('unsupported agent policy continuation')
      if (toolField) definition[key] = toolList(value)
      else if (key === 'egress') {
        if (scalar(value) !== 'network') throw new Error('unsupported agent egress value')
        definition.egress = 'network'
      } else definition.model = scalar(value)
    }
  }
  return definition
}

export function customAgentSandbox(definition: AgentDefinition): Sandbox | undefined {
  // Codex cannot enforce per-tool denials or selectors; core retains those policies.
  if (definition.disallowedTools?.length) return undefined
  if (definition.tools === undefined) return 'workspace-write'
  if (!definition.tools.length || definition.tools.some((tool) => !CODEX_TOOLS.includes(tool) && !tool.startsWith('mcp__'))) return undefined
  // Codex's workspace-write always carries a shell, so only a definition granting Bash may have it.
  if (definition.tools.includes('Bash')) return 'workspace-write'
  return definition.tools.some((tool) => WRITERS.includes(tool)) ? undefined : 'read-only'
}
