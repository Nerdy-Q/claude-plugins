# Power Pages Liquid Filter Reference

This is the verified Power Pages filter inventory per Microsoft Learn. Filters absent from this list don't exist, even if standard Liquid / Shopify Liquid documents them. Source: <https://learn.microsoft.com/en-us/power-pages/configure/liquid/liquid-filters>.

Power Pages runs a customized DotLiquid implementation. Several Shopify staples (`map`, `sort`, `compact`, `slice` on strings, `url_encode`, `abs`, `escape_once`) are not implemented and will silently render nothing or throw, depending on context.

## Array filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `batch` | `{% assign rows = arr \| batch: 3 %}` | array of arrays | Splits into chunks of N |
| `concat` | `{{ a \| concat: b }}` | merged array | Concatenates two arrays |
| `except` | `{{ entities \| except: 'statecode', 1 }}` | filtered array | Inverse of `where` |
| `first` | `{{ arr \| first }}` | first item | |
| `group_by` | `{{ entities \| group_by: 'category' }}` | array of groups | Each group has `.name` and `.items` |
| `join` | `{{ arr \| join: ', ' }}` | comma-joined | |
| `last` | `{{ arr \| last }}` | last item | |
| `order_by` | `{{ entities \| order_by: 'name' }}` | sorted array | Append `'desc'` for reverse: `order_by: 'name', 'desc'` |
| `random` | `{{ arr \| random }}` | one random item | |
| `select` | `{{ entities \| select: 'name' }}` | array of values | Project a single attribute |
| `shuffle` | `{{ arr \| shuffle }}` | reordered array | Randomized copy |
| `size` | `{{ arr \| size }}` | `5` | Works on arrays AND strings |
| `skip` | `{{ arr \| skip: 2 }}` | array | Skip first N |
| `take` | `{{ arr \| take: 2 }}` | array | Take first N |
| `then_by` | `{{ entities \| order_by: 'a' \| then_by: 'b' }}` | sorted array | Secondary sort. Chain after `order_by` |
| `where` | `{{ entities \| where: 'statecode', 0 }}` | filtered array | Two-arg form. `'attr', value`, no expression form |

There is no `map`, no `sort`, no `compact`, no `uniq`, no `reverse` filter, and no `where_exp`. Use `select` instead of `map`. Use `order_by` instead of `sort`. To dedupe or reverse, do it in JavaScript after JSON-passthrough.

## Date filters

Power Pages dates use **.NET format strings**, not strftime. This is the single most common porting bug from Shopify Liquid.

| Filter | Example | Output | Notes |
|---|---|---|---|
| `date` | `{{ now \| date: 'yyyy-MM-dd' }}` | `2026-04-29` | .NET custom format |
| `date` | `{{ now \| date: 'MMMM dd, yyyy' }}` | `April 29, 2026` | |
| `date` | `{{ now \| date: 'g' }}` | `4/29/2026 3:45 PM` | Standard short format |
| `date` | `{{ now \| date: 'D' }}` | `Wednesday, April 29, 2026` | Standard long date |
| `date_add_days` | `{{ now \| date_add_days: 7 }}` | DateTime | Accepts negative values |
| `date_add_hours` | `{{ now \| date_add_hours: -2 }}` | DateTime | |
| `date_add_minutes` | `{{ now \| date_add_minutes: 30 }}` | DateTime | |
| `date_add_months` | `{{ now \| date_add_months: 1 }}` | DateTime | |
| `date_add_seconds` | `{{ now \| date_add_seconds: 45 }}` | DateTime | |
| `date_add_years` | `{{ now \| date_add_years: -1 }}` | DateTime | |
| `date_to_iso8601` | `{{ now \| date_to_iso8601 }}` | `2026-04-29T15:45:00Z` | |
| `date_to_rfc822` | `{{ now \| date_to_rfc822 }}` | `Wed, 29 Apr 2026 15:45:00 GMT` | RSS/Atom feeds |

### .NET format string crash course

Format specifiers are **case-sensitive** and differ from strftime in critical ways. Reference: <https://learn.microsoft.com/en-us/dotnet/standard/base-types/custom-date-and-time-format-strings>.

| Token | Meaning | Example |
|---|---|---|
| `yyyy` | 4-digit year | `2026` |
| `yy` | 2-digit year | `26` |
| `MMMM` | Full month name | `April` |
| `MMM` | Abbreviated month | `Apr` |
| `MM` | 2-digit month | `04` |
| `M` | Month, no pad | `4` |
| `dddd` | Full weekday | `Wednesday` |
| `ddd` | Abbreviated weekday | `Wed` |
| `dd` | 2-digit day | `29` |
| `d` | Day, no pad | `29` |
| `HH` | 24-hour, padded | `15` |
| `hh` | 12-hour, padded | `03` |
| `mm` | Minutes | `45` |
| `ss` | Seconds | `00` |
| `tt` | AM/PM | `PM` |
| `K` | Time-zone offset | `-05:00` |

### strftime → .NET migration map

If you're porting from Shopify Liquid (Ruby strftime), translate verbatim, strftime tokens render as literals in Power Pages.

| strftime | .NET equivalent | Output |
|---|---|---|
| `%Y` | `yyyy` | `2026` |
| `%y` | `yy` | `26` |
| `%m` | `MM` | `04` |
| `%d` | `dd` | `29` |
| `%B` | `MMMM` | `April` |
| `%b` | `MMM` | `Apr` |
| `%A` | `dddd` | `Wednesday` |
| `%a` | `ddd` | `Wed` |
| `%H` | `HH` | `15` |
| `%I` | `hh` | `03` |
| `%M` | `mm` | `45` |
| `%S` | `ss` | `00` |
| `%p` | `tt` | `PM` |
| `%Y-%m-%d` | `yyyy-MM-dd` | `2026-04-29` |
| `%B %d, %Y` | `MMMM dd, yyyy` | `April 29, 2026` |
| `%m/%d/%Y` | `MM/dd/yyyy` | `04/29/2026` |

Common porting failure: `{{ x \| date: '%Y-%m-%d' }}` renders the literal string `%Y-%m-%d` in Power Pages. Always rewrite to `yyyy-MM-dd`.

## Escape filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `escape` | `{{ '<a>' \| escape }}` | `&lt;a&gt;` | HTML entities. Not for JSON |
| `html_safe_escape` | `{{ user_html \| html_safe_escape }}` | sanitized HTML | **Power Pages-specific.** Strips dangerous tags/attributes, allows safe HTML through |
| `url_escape` | `{{ 'a b/c' \| url_escape }}` | `a%20b%2Fc` | Percent-encodes for URL components |
| `xml_escape` | `{{ '<x>' \| xml_escape }}` | `&lt;x&gt;` | XML-safe entity encode |

There is no `url_encode` (use `url_escape`), no `escape_once`, and no `cgi_escape`. For embedding strings in JSON, see the JSON Output section below, `escape` is wrong for that purpose.

## List filters (entitylist-only)

These three only work inside an `{% entitylist %}` block, against the implicit list context.

| Filter | Example | Output | Notes |
|---|---|---|---|
| `current_sort` | `{{ 'name' \| current_sort }}` | `'asc'` / `'desc'` / nil | Returns the current sort direction for the named attribute |
| `metafilters` | `{{ entitylist \| metafilters }}` | filter object | Exposes faceted-search filter state |
| `reverse_sort` | `{{ 'asc' \| reverse_sort }}` | `'desc'` | Inverts a sort direction string |

Outside of an entitylist they return null silently.

## Math filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `ceil` | `{{ 3.1 \| ceil }}` | `4` | |
| `divided_by` | `{{ 10 \| divided_by: 3 }}` | `3` | Integer division if both ints |
| `divided_by` | `{{ 10 \| divided_by: 3.0 }}` | `3.333` | Float division if either is float |
| `floor` | `{{ 3.9 \| floor }}` | `3` | |
| `minus` | `{{ 5 \| minus: 2 }}` | `3` | |
| `modulo` | `{{ 10 \| modulo: 3 }}` | `1` | |
| `plus` | `{{ 5 \| plus: 2 }}` | `7` | |
| `round` | `{{ 3.456 \| round: 2 }}` | `3.46` | |
| `times` | `{{ 5 \| times: 2 }}` | `10` | |

There is no `abs`, no `at_least`, no `at_most`. For absolute value, branch with `if` and `times: -1`.

## String filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `append` | `{{ 'foo' \| append: 'bar' }}` | `foobar` | |
| `capitalize` | `{{ 'hello world' \| capitalize }}` | `Hello World` | **Capitalizes every word**, not just the first character. Diverges from Shopify |
| `downcase` | `{{ 'FOO' \| downcase }}` | `foo` | |
| `newline_to_br` | `{{ "a\nb" \| newline_to_br }}` | `a<br/>b` | |
| `prepend` | `{{ 'bar' \| prepend: 'foo-' }}` | `foo-bar` | |
| `remove` | `{{ 'a-b-c' \| remove: '-' }}` | `abc` | |
| `remove_first` | `{{ 'a-b-c' \| remove_first: '-' }}` | `ab-c` | |
| `replace` | `{{ 'hello' \| replace: 'l', 'L' }}` | `heLLo` | Literal, **not regex** |
| `replace_first` | `{{ 'foofoo' \| replace_first: 'foo', 'bar' }}` | `barfoo` | |
| `split` | `{{ 'a,b,c' \| split: ',' }}` | array `[a,b,c]` | |
| `strip_html` | `{{ '<p>x</p>' \| strip_html }}` | `x` | |
| `strip_newlines` | `{{ "a\nb" \| strip_newlines }}` | `ab` | |
| `text_to_html` | `{{ "Visit https://x.com\n\nNew para" \| text_to_html }}` | autolinked + `<p>` wrapped | Auto-links URLs and wraps blank-line-separated blocks in `<p>` |
| `truncate` | `{{ 'longstring' \| truncate: 5 }}` | `lo...` | Default ellipsis is `...` (counted in the length) |
| `truncate_words` | `{{ 'one two three four' \| truncate_words: 2 }}` | `one two...` | **Underscore**, not `truncatewords` |
| `upcase` | `{{ 'foo' \| upcase }}` | `FOO` | |

There is no `strip`, `lstrip`, `rstrip`, `slice` (string), `pluralize`, or `truncatewords` (camelCase). Trim whitespace by `replace`-ing known characters or hand off to JavaScript.

## Type filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `boolean` | `{{ 'on' \| boolean }}` | `true` | Accepts `on`/`off`, `yes`/`no`, `enabled`/`disabled`, `true`/`false`, `1`/`0` |
| `decimal` | `{{ '3.14' \| decimal }}` | `3.14` | Parses to decimal |
| `integer` | `{{ '42' \| integer }}` | `42` | Parses to int |
| `string` | `{{ 42 \| string }}` | `'42'` | Coerces to string |

There is no `to_string`, `to_integer`, or `json` filter. The Power Pages way to serialize an object to JSON is the Unicode-escape pattern in the next section.

## URL filters

Operate on a URL string and return a parsed component or modified URL.

| Filter | Example | Output | Notes |
|---|---|---|---|
| `add_query` | `{{ url \| add_query: 'page', 2 }}` | URL with `?page=2` appended/replaced | |
| `base` | `{{ url \| base }}` | `https://example.com` | Scheme + host (+ port) |
| `host` | `{{ url \| host }}` | `example.com` | |
| `path` | `{{ url \| path }}` | `/products/widgets` | |
| `path_and_query` | `{{ url \| path_and_query }}` | `/products/widgets?id=1` | |
| `port` | `{{ url \| port }}` | `443` | |
| `remove_query` | `{{ url \| remove_query: 'page' }}` | URL with `page` param stripped | |
| `scheme` | `{{ url \| scheme }}` | `https` | |

## Additional filters

| Filter | Example | Output | Notes |
|---|---|---|---|
| `default` | `{{ x \| default: 'n/a' }}` | `x` or `n/a` | Falls back when input is null/empty/false |
| `file_size` | `{{ note.filesize \| file_size }}` | `1.2 MB` | Humanizes a byte count |
| `h` | `{{ '<a>' \| h }}` | `&lt;a&gt;` | Shortcut for HTML escape, equivalent to `escape` |
| `has_role` | `{{ user \| has_role: 'Administrators' }}` | `true` / `false` | Power Pages-specific. Web role membership check |
| `liquid` | `{{ template_string \| liquid }}` | rendered output | Re-renders a string as Liquid against the current context |

## JSON output pattern

Emitting a server-side object into a `<script>` block requires two steps: Unicode-escape the value at server render time, then `JSON.parse` on the client. Plain `escape` is not safe, it does not protect against `</script>` breakouts or unescaped quotes inside string fields.

```liquid
<script type="application/json" id="bootstrap-data">
{{ entity_data | xml_escape }}
</script>

<script>
  const raw = document.getElementById('bootstrap-data').textContent;
  const data = JSON.parse(raw);
</script>
```

For a JSON literal you build in Liquid, prefer the `<script type="application/json">` envelope (the browser will not execute it) and parse client-side. If you must inline into JavaScript directly, run each string field through a Unicode-escape helper rather than `escape`. The `application/json` envelope is the safer default and the recommended Power Pages pattern.

## Filters that DON'T exist (despite Shopify Liquid docs)

These appear in Shopify Liquid documentation, Stack Overflow answers, and AI-generated Liquid code. **None of them are implemented in Power Pages.** Using them produces silent failure or literal output.

**String:** `strip`, `lstrip`, `rstrip`, `slice` (on strings), `escape_once`, `url_encode`, `pluralize`, `truncatewords` (camelCase, Power Pages uses `truncate_words` with underscore), `t` (translation)

**Array:** `sort`, `sort_natural`, `uniq`, `compact`, `reverse` (filter form), `map`, `where_exp`

**Math:** `abs`, `at_least`, `at_most`

**Date:** `time_ago_in_words`, anything strftime-flavored (`%Y`, `%m`, `%d` render as literals)

**Type/Conversion:** `json` (filter), `to_string`, `to_integer`

**Entity/CMS:** `current_culture`, `display_name`, `metafield`

**Shopify theme-specific:** `url_for`, `image_tag`, `stylesheet_tag`, `script_tag`, `asset_url`, `img_url`, `link_to`, `payment_type_img_url`, `money`, `money_with_currency`, `money_without_trailing_zeros`

When porting code that uses any of the above, the substitutions are:

- `map: 'name'` → `select: 'name'`
- `sort: 'name'` → `order_by: 'name'`
- `sort` (descending) → `order_by: 'name', 'desc'`
- `reverse` → no equivalent, pass through JSON and reverse client-side, or pre-reverse the source query
- `uniq` / `compact` → no equivalent, handle in JavaScript after JSON-passthrough
- `abs` → `if x < 0`, then `times: -1`
- `url_encode` → `url_escape`
- `strip` / `lstrip` / `rstrip` → no equivalent, `replace` known characters or post-process client-side
- `truncatewords: N` → `truncate_words: N`
- strftime tokens → .NET tokens (see migration map above)
- `json` filter → `<script type="application/json">` envelope + `xml_escape` + `JSON.parse`

> Verified against Microsoft Learn 2026-04-29.
