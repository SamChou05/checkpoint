The original `execution.json` manifest (SHA-256
`40f20ba966ab78ad7998f42cf93dbcd5549ebec4de6eaea79dd87dced6c5bc64`)
was prepared but never dispatched. Review required redacting adaptive
`reasoningContent` blocks and signatures before saving provider responses.
The final runner includes that redaction and its offline preservation test;
`execution-v2.json` pins the revised runner. The original two-call plan and
candidate schema remain unchanged. No provider response exists for the older
manifest, and no warmup or replacement calls were made.
