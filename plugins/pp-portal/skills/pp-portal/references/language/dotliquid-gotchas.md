# DotLiquid Gotchas: Power Pages-Specific Liquid Behavior

Power Pages uses **DotLiquid**, a .NET reimplementation of Shopify's Liquid. The syntax matches in the common cases, but several filters and behaviors differ in ways that bite you only when you reach for them. This file lists the gotchas and how to work around each.

## 1. JSON serialization: the `replace` quote-escape trap

**The trap:**

```liquid
{# This DOES NOT produce \", it produces \\" (3 chars) #}
"name": "{{ value | replace: '"', '\\"' }}"
```

DotLiquid's `replace` interprets backslash literally, there's no string-escape pass on the replacement argument. The output of `replace: '"', '\\"'` is `\` + `\` + `"` (three characters), which breaks JSON parsing.

**The fix, Unicode escape:**

```liquid
"name": "{{ value | replace: '"', '"' }}"
```

`"` is the standard JSON Unicode escape for `"`. Two characters in the source (`"` literal, no actual escaping needed).

**Combine with `<script type="application/json">`:**

```liquid
<script id="rowsJSON" type="application/json">
[{% for row in rows %}{
  "id":   "{{ row.id }}",
  "name": "{{ row.name | replace: '"', '"' }}"
}{% unless forloop.last %},{% endunless %}{% endfor %}]
</script>
<script>
  var rows = JSON.parse(document.getElementById('rowsJSON').textContent || '[]');
</script>
```

`type="application/json"` prevents the browser from executing the content, so even if your JSON has a syntax error, no script crashes. You catch the error in the `JSON.parse`.

**Do NOT use `| escape`** for JSON values. `| escape` produces HTML entities (`&quot;`, `&#39;`) which stay literal inside `<script>` blocks because there's no HTML entity decoding inside a script tag. The result is `JSON.parse` blowing up on `"name":"&quot;value&quot;"`.

## 2. `replace` is not regex

DotLiquid's `replace` is a literal string replace, not a regex. To do pattern replaces, do them in JavaScript after JSON.parse, not in Liquid.

```liquid
{# Won't work, `replace` doesn't take regex #}
{{ phone | replace: '\D', '' }}
```

## 3. Date/time gotchas

Power Pages dates render in **server time**, not user time. The server is typically UTC for Commercial Cloud, can vary in GCC.

```liquid
{{ now | date: '%Y-%m-%d %H:%M:%S %Z' }}           UTC most environments
```

DotLiquid's `date` filter accepts strftime tokens but **not** all of them:

| Token | Status |
|---|---|
| `%Y` `%m` `%d` `%H` `%M` `%S` | OK |
| `%B` (full month name) | OK |
| `%b` (abbrev month) | OK |
| `%A` `%a` (day names) | OK |
| `%I` `%p` (12-hour clock) | OK |
| `%-d` `%-m` (no-leading-zero) | **DotLiquid: NOT supported**, strip zeros in output instead |
| `%Z` (timezone) | OK on server |
| `%s` (Unix timestamp) | **NOT supported** |

For numeric-only dates (e.g., GCC environment requirements), stick to `%m/%d/%Y`, these work everywhere.

To emit a Unix timestamp, do it server-side in C# or compute in JavaScript on the client.

## 4. `default` is "blank-default", not "nil-default"

Liquid's `default` filter falls through on blank string OR nil, but the definition of "blank" includes `0` and `false`:

```liquid
{{ count | default: 'none' }}                      "none" if count is 0!
```

If you want zero to pass through, check explicitly:

```liquid
{% if count == 0 or count > 0 %}{{ count }}{% else %}none{% endif %}
```

Or use `| default: 'none', allow_false: true`, but `allow_false` support varies by DotLiquid version. Test it on your portal before relying on it.

## 5. `forloop.length` ≠ array.size

Inside a `{% for %}` block:

| Expression | Returns |
|---|---|
| `forloop.length` | total iterations of the current loop |
| `forloop.index` | current iteration (1-indexed) |
| `forloop.index0` | current iteration (0-indexed) |
| `forloop.first` | true on first iteration |
| `forloop.last` | true on last iteration |

For array length **outside** a loop, use `arr.size`:

```liquid
{% if rows.size > 0 %}
{% if rows.size == 0 %}                            often clearer than `unless`
```

## 6. Logical operators

DotLiquid uses `and` / `or`, not `&&` / `||`. They're left-associative, there is no operator precedence:

```liquid
{# DotLiquid evaluates this LEFT to RIGHT, not C-style precedence #}
{% if a and b or c %}                              == ((a and b) or c), works
{% if a or b and c %}                              == ((a or b) and c), surprising!
```

Use parentheses to be explicit: DotLiquid supports `( ... )` grouping in some operators but it's flaky, if logic is non-trivial, push it to assigned booleans:

```liquid
{% assign is_priority   = item.priority == 'High' %}
{% assign needs_review  = item.status   == 'New' %}
{% if is_priority and needs_review %}…{% endif %}
```

## 7. `assign` is the only sane way to compose

DotLiquid does NOT support nested filter calls inside expressions:

```liquid
{# Error: can't filter on filter result mid-expression in some DotLiquid versions #}
{% if (request.params['x'] | strip) != '' %}
```

Always assign first:

```liquid
{% assign x = request.params['x'] | strip %}
{% if x != '' %}
```

## 8. String concatenation

There's no `+` operator for strings, use `| append:`:

```liquid
{% assign url = customers_url | append: '?search=' | append: encoded_search %}
```

For a more complex assemble, chain or `| concat:` arrays then `| join:`:

```liquid
{% assign parts = '' | split: '' %}                 empty array
{% assign parts = parts | concat: 'a,b,c' | split: ',' %}
{{ parts | join: ' / ' }}                           "a / b / c"
```

## 9. `where` filter

DotLiquid implements a `where` filter for arrays (filter records by attribute value):

```liquid
{% assign active_rows = rows | where: 'statecode', 0 %}
```

But `where_exp` (with arbitrary expressions) is **not** supported. For richer filters, use `{% if %}` inside the loop or filter at the FetchXML level:

```liquid
{% for row in rows %}
  {% if row.statecode == 0 and row.priority > 5 %}
    …
  {% endif %}
{% endfor %}
```

## 10. `| escape` is HTML, not URL or JS

| Filter | Use case |
|---|---|
| `| escape` | HTML attribute or text content (`<input value="{{ x | escape }}">`) |
| `| url_encode` | querystring values |
| `| url_escape` | path components (alias for url_encode in DotLiquid) |
| `| strip_html` | strip HTML tags from rich text |
| `| escape_once` | escape but don't double-escape |

For inserting into JavaScript string literals, use the `<script type="application/json">` + `JSON.parse` pattern from gotcha 1, NOT `| escape`.

## 11. Custom Power Pages filters

Power Pages adds filters that aren't standard Liquid. Useful ones:

| Filter | Description |
|---|---|
| `| has_role: 'Role Name'` | true if `user` has the named Web Role |
| `| current_culture` | current request culture code (e.g., `en-US`) |
| `| display_name` | format an OptionSet value as its display name |
| `| metafield: 'name'` | resolve a metafield (entity custom property) |

Example:

```liquid
{% if user | has_role: 'State Employee' %}
  Admin actions
{% endif %}
```

## 12. Comments

DotLiquid comments use `{% comment %}…{% endcomment %}`. Inline `{# ... #}`-style comments are NOT supported in production DotLiquid, they sometimes work but leak through to output unexpectedly. Use `{% comment %}` only.

## 13. `include` parameter syntax

DotLiquid's `include` accepts named parameters:

```liquid
{% include 'Customer Card' with customer: row, expanded: true %}
```

But the **comma between parameters is required** in DotLiquid (vs optional in Shopify Liquid). Forgetting commas silently makes parameters disappear.

## 14. Whitespace control

DotLiquid honors `{%-` and `-%}` for whitespace stripping the same as Shopify, **except** in `{% raw %}` blocks where they're literal.

```liquid
{%- assign x = 1 -%}                               strips surrounding whitespace
{%- comment -%}…{%- endcomment -%}                 cleanest comment form
```

## 15. `| size` works on both strings and arrays

Same filter, different meaning depending on type:

```liquid
{{ 'hello' | size }}                               5
{{ rows | size }}                                  number of array elements
```

## Quick "is this a DotLiquid issue?" checklist

When something works in your local Liquid sandbox but fails on the portal:

1. Are you using `{# inline comment #}`? Remove it.
2. Are you using `\\"` in a `replace`? Switch to `"`.
3. Are you using `&&` / `||`? Switch to `and` / `or`.
4. Are you using `%-d` (no-zero day)? Use `%d` and accept the leading zero.
5. Are you nesting filters inside expressions? `{% assign %}` first.
6. Are you using `where_exp:`? Filter in the loop or at FetchXML level.
