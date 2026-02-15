# Flow Language Specification

This document defines the formal grammar and syntax for the **Flow** task management system.
The file format is plain text Markdown (`.md`).

## 1. General Structure

A Flow file consists of **Sections** and **Event Nodes**.
Hierarchy is defined by indentation (4 spaces or 1 tab per level).

```markdown
- [ ] Root Task
    - [ ] Child Task
## Section Name
- [ ] Another Root Task
```

## 2. Event Node Syntax

Each line representing a task or event must follow this structure:

```
{Indent}- [{State}] {Title} {Tags} {Metadata} {Anchor}
```

### Components

- **Indent**: 0 or more units of 4 spaces (or 1 tab).
- **State**:
    - ` ` (Space): Active / Incomplete
    - `x` or `X`: Completed
- **Title**: Plain text description.
- **Tags**: Space-separated strings starting with `#`.
    - `#wait`: Marks task as waiting (visual: amber hourglass).
    - `#ref`: System tag for reference nodes (visual: link icon).
    - User tags: `#urgent`, `#home`, etc.
- **Metadata**: Key-value pairs in brackets: `[key: value]`.
- **Anchor**: HTML anchor for reference targets: `<a id="..."></a>`.
  > **Note**: While self-closing tags like `<a id="..." />` are valid in XHTML, **HTML5** requires an end tag (`</a>`). We recommend the standard `<a id="..."></a>` format for maximum compatibility with external Markdown viewers.

## 3. Metadata & Timestamps

All time-related metadata uses a **Unified Timestamp Format**: `yyyy-MM-dd HH:mm`.

### Standard Keys

| Key | Description | Format | Example |
| :--- | :--- | :--- | :--- |
| `created` | Creation time | `[created: yyyy-MM-dd HH:mm]` | `[created: 2026-02-15 10:00]` |
| `done` | Completion time | `[done: yyyy-MM-dd HH:mm]` | `[done: 2026-02-15 14:30]` |
| `due` | Due date/time | `[due: yyyy-MM-dd HH:mm]` | `[due: 2026-02-20 17:00]` |

*Note: `due` may also support `yyyy-MM-dd` for backward compatibility, but `yyyy-MM-dd HH:mm` is preferred.*

### Parsing Regex
The standard regex for extracting metadata is:
```regex
\[(.*?):\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\]
```

## 4. Work Logs

Logs are appended immediately after the node they belong to, at `Indent + 1`.

### Syntax
```
{ParentIndent + 1}> [created: {Timestamp}] {Content}
```

- **Marker**: `>` followed by a space.
- **Timestamp**: Unified format with key `created`: `[created: yyyy-MM-dd HH:mm]`.
- **Content**: Markdown text.

### Example
```markdown
- [ ] Fix login bug [created: 2026-02-15 09:00]
    > [created: 2026-02-15 09:15] Investigating auth token issue.
    > [created: 2026-02-15 10:30] Found the bug in token refresh logic.
```

## 5. References

References allow a node to mirror another node's state.

- **Target Node**: Must have an anchor.
  `- [ ] Original Task <a id="task-123"></a>`
- **Reference Node**: Markdown link to the anchor, tagged `#ref`.
  `- [ ] [Original Task](#task-123) #ref`

## 6. Comprehensive Example

```markdown
# My Project Flow

- [ ] Project Alpha [created: 2026-01-01 09:00]
    - [x] Initial Research #research [done: 2026-01-02 14:00]
        > [created: 2026-01-01 10:00] Started gathering requirements.
        > [created: 2026-01-02 13:00] Finished market analysis.
    - [ ] Design Phase #design [due: 2026-02-20 17:00] <a id="design-phase"></a>
        - [ ] UI Mockups
        - [ ] User Testing #urgent

## Development
- [ ] Backend API [created: 2026-02-10 09:00]
    - [ ] [Design Phase](#design-phase) #ref
    - [ ] Setup Database #db
```
