Generate a new sleep science question for the GoToSleep app.

## Instructions

1. Read `GoToSleep/Resources/questions.json` to see existing questions and avoid duplicates.
2. If the user provided a PDF path as argument (`$ARGUMENTS`), read that PDF for source material. Otherwise, use the "Why We Sleep" PDF at `BOOKS.YOSSR.COM-Why-We-Sleep.pdf` in the project root if it exists.
3. Search the source material for interesting quantitative findings not already covered by existing questions.
4. Generate ONE new question in one of the three types below.
5. Append the new question to `GoToSleep/Resources/questions.json`.

## Question Types

### Type 1: `hard_multiple_choice`
- 10 plausible answer choices with educational hints for wrong answers (`hint: null` for correct)
- `answerIndex` points to the correct choice (0-indexed)
- `correctExplanation` connects the science to real life — make it revelatory and guilt-inducing
- Include `chapter` number and `reference` string

```json
{
  "id": "unique-kebab-case-id",
  "type": "hard_multiple_choice",
  "chapter": 8,
  "text": "Question text here?",
  "choices": [
    { "text": "Choice A", "hint": "Why this is wrong" },
    { "text": "Choice B", "hint": null }
  ],
  "answerIndex": 1,
  "correctExplanation": "Explanation with emotional impact...",
  "minimumSeconds": 30,
  "reference": "Walker, Why We Sleep, Ch. X"
}
```

### Type 2: `verifiable_fact`
- `answerType`: "percentage", "number", or "word"
- For numbers: `exactAnswer` (number), `tolerance` (acceptable margin)
- For words: `exactAnswer` (string), `maxAttempts` (default 5)
- Word answers should be specific scientific terms
- Correct answers show explanation; incorrect answers do NOT reveal the answer

```json
{
  "id": "unique-kebab-case-id",
  "type": "verifiable_fact",
  "chapter": 6,
  "text": "Question requiring a specific fact?",
  "answerType": "percentage",
  "exactAnswer": 70,
  "tolerance": 5,
  "unit": "%",
  "maxAttempts": 1,
  "minimumSeconds": 30,
  "correctExplanation": "Explanation...",
  "reference": "Walker, Why We Sleep, Ch. X"
}
```

### Type 3: `calculation`
- Parameterized questions with randomized values
- `parameters`: each has `type` ("int", "float", "enum"), `min`, `max`, `step`, `unit`, `values`
- `calculate`: DSL expression using these functions:
  - `ADD(a, b)`, `SUBTRACT(a, b)`, `MULTIPLY(a, b)`, `DIVIDE(a, b)`
  - `ROUND(value, places)`, `PERCENT(value)`
  - `HALF_LIFE_DECAY(initial, halfLife, elapsed)` — `initial * 0.5^(elapsed/halfLife)`
  - `HOURS_BETWEEN(time1, time2)` — hours between two time strings
  - `MIN(a, b)`, `MAX(a, b)`, `CLAMP(value, low, high)`
  - `PERCENTAGE_OF(part, whole)` — `(part/whole)*100`
  - `IF_GREATER(a, b, then, else)`
- `correctExplanation` can use `{param_name}` and `{answer}` substitutions, plus inline DSL like `{ROUND(DIVIDE(answer, 95), 1)}`
- Must include `tags` array for skill categorization (e.g., `["percentages"]`, `["half-life-decay"]`)

```json
{
  "id": "unique-kebab-case-id",
  "type": "calculation",
  "chapter": 8,
  "tags": ["percentages"],
  "text": "Question with {param1} and {param2}?",
  "parameters": {
    "param1": { "type": "int", "min": 10, "max": 100, "step": 10, "unit": "mg" },
    "param2": { "type": "float", "min": 1.0, "max": 5.0, "step": 0.5, "unit": "hours" }
  },
  "calculate": "ROUND(MULTIPLY(param1, param2), 0)",
  "tolerance": 5,
  "unit": "mg",
  "maxAttempts": 5,
  "minimumSeconds": 30,
  "correctExplanation": "At {param2} hours, {answer}mg remains...",
  "reference": "Walker, Why We Sleep, Ch. X"
}
```

## Quality Guidelines

- Questions should be **revelatory** — the user should learn something shocking about sleep science
- Explanations should make the user feel **demotivated to stay awake**
- Use specific numbers from the research, not vague claims
- Include page/chapter references
- For multiple choice: wrong answers should be plausible and hints should be educational
- Avoid duplicating existing question IDs or topics
