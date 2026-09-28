// The code languages of the editor: the ones that it highlights and that
// its language picker offers. `Kotoba.CodeLanguages` has the same table on
// the server (a test compares the two).
//
// A language has an id, which a code block stores and Prism knows, a label
// for the picker, and aliases: the other names that a pasted or imported
// block can have (`ex`, `yml`, `js`). A block keeps the name that it has;
// the picker shows the language of an alias, and writes the id only when
// the person picks a language.

export interface CodeLanguage {
  id: string;
  label: string;
  aliases: readonly string[];
}

/** The language of a code block with no language: no highlighting. */
export const PLAIN_TEXT: CodeLanguage = { id: "plain", label: "Plain text", aliases: ["text", "txt", "plaintext"] };

/** The highlighted languages, in the order of the picker. */
export const CODE_LANGUAGES: readonly CodeLanguage[] = [
  { id: "bash", label: "Bash", aliases: ["sh", "shell", "zsh"] },
  { id: "c", label: "C", aliases: [] },
  { id: "cpp", label: "C++", aliases: ["c++"] },
  { id: "css", label: "CSS", aliases: [] },
  { id: "diff", label: "Diff", aliases: ["patch"] },
  { id: "dockerfile", label: "Dockerfile", aliases: ["docker"] },
  { id: "elixir", label: "Elixir", aliases: ["ex", "exs"] },
  { id: "erlang", label: "Erlang", aliases: ["erl"] },
  { id: "go", label: "Go", aliases: ["golang"] },
  { id: "graphql", label: "GraphQL", aliases: ["gql"] },
  { id: "html", label: "HTML", aliases: ["htm", "markup"] },
  { id: "java", label: "Java", aliases: [] },
  { id: "javascript", label: "JavaScript", aliases: ["js", "mjs", "cjs"] },
  { id: "json", label: "JSON", aliases: [] },
  { id: "kotlin", label: "Kotlin", aliases: ["kt", "kts"] },
  { id: "markdown", label: "Markdown", aliases: ["md"] },
  { id: "objectivec", label: "Objective-C", aliases: ["objc"] },
  { id: "php", label: "PHP", aliases: [] },
  { id: "powershell", label: "PowerShell", aliases: ["ps1", "pwsh"] },
  { id: "python", label: "Python", aliases: ["py"] },
  { id: "ruby", label: "Ruby", aliases: ["rb"] },
  { id: "rust", label: "Rust", aliases: ["rs"] },
  { id: "sql", label: "SQL", aliases: [] },
  { id: "swift", label: "Swift", aliases: [] },
  { id: "toml", label: "TOML", aliases: [] },
  { id: "typescript", label: "TypeScript", aliases: ["ts"] },
  { id: "xml", label: "XML", aliases: ["svg"] },
  { id: "yaml", label: "YAML", aliases: ["yml"] },
];

const BY_NAME = new Map<string, CodeLanguage>();
for (const language of [...CODE_LANGUAGES, PLAIN_TEXT]) {
  for (const name of [language.id, ...language.aliases]) BY_NAME.set(name, language);
}

/**
 * The language of a name: an id or an alias, in any case. `null` for a
 * name that is not one of `CODE_LANGUAGES` (or plain text).
 */
export function findCodeLanguage(name: string | null | undefined): CodeLanguage | null {
  if (name === null || name === undefined || name === "") return PLAIN_TEXT;
  return BY_NAME.get(name.toLowerCase()) ?? null;
}

/**
 * Reads `data-code-languages`: comma-separated ids (or aliases) of the
 * languages that the picker offers. Unknown names are dropped with a log.
 * No attribute (or no known name) gives every language.
 */
export function parseCodeLanguages(value: string | undefined): readonly CodeLanguage[] {
  if (value === undefined || value.trim() === "") return CODE_LANGUAGES;

  const languages: CodeLanguage[] = [];
  for (const name of value.split(",").map((part) => part.trim()).filter((part) => part !== "")) {
    const language = findCodeLanguage(name);
    if (language === null || language === PLAIN_TEXT) {
      console.error(`Kotoba: the code language ${JSON.stringify(name)} is not one of the editor's languages`);
    } else if (!languages.includes(language)) {
      languages.push(language);
    }
  }
  return languages.length > 0 ? languages : CODE_LANGUAGES;
}

interface PrismLike {
  languages: Record<string, unknown>;
}

/**
 * Makes each alias (and each id that Prism names otherwise) a name of its
 * grammar in the editor's Prism, so that a block with `ex` or `yml`
 * highlights as Elixir or YAML. Call it once the grammars have loaded.
 */
export function registerCodeLanguageAliases(prism: PrismLike): void {
  for (const language of CODE_LANGUAGES) {
    const grammar = prism.languages[language.id];
    if (grammar === undefined || typeof grammar === "function") {
      console.error(`Kotoba: no grammar for the code language "${language.id}"`);
      continue;
    }
    for (const alias of language.aliases) {
      if (!Object.prototype.hasOwnProperty.call(prism.languages, alias)) prism.languages[alias] = grammar;
    }
  }
}
