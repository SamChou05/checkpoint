# Managed source discovery adapter

September 8, 2026. `web_source_search.py` implements bounded, signed discovery
and invocation of the AWS AgentCore Web Search connector. This is a library for
the evidence work; generation does not invoke it, and no Gateway or IAM resource
was created or changed in this milestone.

The client validates its AWS regional endpoint before loading credentials, lists
tools once, and uses the actual namespaced WebSearch name and its version-1.2
input schema. It defaults to three searches, five results per search, a 32 KiB
request and 128 KiB response limit. The HTTPS child has a 15-second wall deadline
including DNS, plus up to two seconds to confirm cleanup. It follows no redirects,
uses no proxy environment, and retries no dispatched request.

Requests use the stateless MCP revision 2026-07-28, which AWS documents as supported.
The parser accepts one correlated JSON or completed SSE response and rejects
unsolicited interactions, sessions, paging, errors and ambiguous JSON. Signed
headers stay out of diagnostics. Captured unsigned requests and exact response
bytes/hashes support later inspection; they are not provider signatures.

Returned snippets retain their supplied text, URL, title and publication date,
including absent metadata and empty result sets. They are search observations,
not fetched pages, guaranteed verbatim passages or proof of a question's accuracy.
Reference selection and page acquisition remain separate work.

All 18 focused offline tests pass, including protocol correlation, transport
cleanup, credential destinations, unchanged observations and call bounds. Ruff
and whitespace checks pass. No live invocation has qualified compatibility,
coverage, latency or the accuracy of returned material.

A bounded live evaluation needs an IAM-authenticated Gateway pinned to the
supported protocol, a version-1.2 Web Search target, a service role with the
documented Web Search permission, and caller permission to invoke that Gateway.
An earlier read-only inventory found no Checkpoint Gateway in us-east-1. It did
not establish permission to create one. Production resources remain unchanged.

AWS's terms require retaining the returned source citations in user-visible
outputs that use the search results; product integration must preserve those
links. This adapter has not supplied any learner-facing content.

References: [Gateway protocol](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-using.html),
[Web Search schema and terms](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-connector-web-search-tool.html),
[target setup](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-add-target-api-target-config.html).
