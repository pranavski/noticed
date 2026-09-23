# Somatic

A food–body record: the reader logs what they ate, the app reads it back to
them, and a statistical engine occasionally says something honest about the
pair. This file is the glossary for that domain and nothing else — no
implementation detail, no status, no decisions. Decisions live in
`docs/decisions/`.

## Language

### The paid line

**Description**:
A statement about what the reader logged, derived by templating and
arithmetic alone, with no model call and no claim of cause. Free forever,
because it costs nothing to produce and is the reader's own record read
back to them.
_Avoid_: summary, recap, digest

**Inference**:
A statement about a relationship between something eaten and something felt,
surviving statistical correction and phrased as hedged possibility. What a
subscription buys.
_Avoid_: insight (as a category term — an insight is one instance of an
inference), correlation, finding

**Generation**:
The act of producing new inferences: scoring the window, applying the
correction, and asking the model to select and phrase the survivors. The
single gated capability. Reading inferences already produced is not
generation and is never gated.
_Avoid_: analysis, running the engine, refresh

### Who is entitled

**Entitlement**:
The server's own answer to whether a given reader may trigger generation or
AI parsing, derived from Apple's notifications and never from the client. A
device's StoreKit state is a *display* of entitlement, not a source of it.
_Avoid_: subscription status, premium, pro

**Free**:
An account without entitlement — whether it never had one or its
subscription lapsed. These are one state, because they are identical in what
they permit; they differ only in what the reader already has, which the
record can answer. A free account keeps logging, the whole record, export,
deletion, descriptions, and every inference already surfaced.
_Avoid_: lapsed, expired, basic, freemium (as distinct states)
