# Liquid Types in Power Pages

Microsoft documents exactly seven basic types at <https://learn.microsoft.com/en-us/power-pages/configure/liquid/liquid-types>: String, Number, Boolean, Array, Dictionary, DateTime, Null. There is no separate Integer/Decimal split, no array literal syntax, and no auto-coercion from string to number. Anything outside this set isn't a real type, it's an object with attributes (covered in [objects.md](objects.md)).

## String

Wrap in single OR double quotes, both are valid and identical. Length comes from `.size`, not `.length`.

```liquid
{% assign greeting = "Hello" %}
{% assign target   = 'World' %}
{{ greeting.size }}    {# 5 #}
```

## Number

A single Number type covers integers and floats. Arithmetic is done through math filters (`plus`, `minus`, `times`, `divided_by`, `modulo`), there is no bare `+` operator in Liquid.

```liquid
{% assign pi    = 3.14 %}
{% assign count = 42 %}
{% assign next  = count | plus: 1 %}    {# 43 #}
```

## Boolean

Bare keywords `true` and `false`, no quotes. Quoting them turns them into strings, which are truthy.

```liquid
{% assign is_admin = true %}
{% if is_admin %}…{% endif %}
```

## Array

Holds an ordered list of values; mixed types are allowed. Zero-indexed access, iterate with `for`, length via `.size`.

```liquid
{% for tag in tags %}{{ tag }}{% endfor %}
{{ tags[0] }}
{{ tags.size }}
```

Liquid has **no** `[1, 2, 3]` array literal syntax. The canonical idiom is to build an array from a CSV string with `split`:

```liquid
{% assign tags = 'featured,sale,new' | split: ',' %}
```

Filters that produce arrays: `split`, `select`, `where`, `concat`, `batch`. To project a single attribute across rows of objects, use `select` (not `map`, Power Pages doesn't implement `map`).

## Dictionary

Holds key/value pairs accessed by string key. Power Pages calls this "Dictionary"; other Liquid implementations call it "hash" or "object". Iterating yields 2-element arrays, `[0]` is the key, `[1]` is the value.

```liquid
{{ request.params['id'] }}

{% for entry in request.params %}
  {{ entry[0] }}={{ entry[1] }}
{% endfor %}

{{ request.params.size }}
```

A nonexistent key returns `null`, not an error. `request.params` is the canonical example, it's the parsed querystring.

## DateTime

A specific point in time. Format with the `date` filter using **.NET format strings**, not strftime. Arithmetic uses dedicated filters (`date_add_days`, `date_add_hours`, etc.). See [filters.md](filters.md) for the full .NET format reference.

```liquid
{{ page.modifiedon | date: 'f' }}            {# Wednesday, April 29, 2026 3:45 PM #}
{{ now | date: 'yyyy-MM-dd' }}               {# 2026-04-29 #}
{{ now | date_add_days: 7 }}                 {# DateTime, 7 days from now #}
```

## Null

Represents an empty / nonexistent value.

- Rendering null produces an empty string, not the literal `"null"`.
- Treated as **false** in conditionals.
- A missing dictionary key returns null.
- A missing attribute on an object returns null, so `{% if record.someattr %}` is safe.

## Truthiness rules: critical gotcha

Microsoft, verbatim at <https://learn.microsoft.com/en-us/power-pages/configure/liquid/liquid-conditional-operators>: **"null and the Boolean value false are treated as false; everything else is treated as true."**

| Value | Truthy? |
|---|---|
| `true` | yes |
| `false` | no |
| `null` | no |
| any string, including `""` | **YES (surprising)** |
| `0`, any number | **YES (surprising)** |
| any array/dict, including empty | **YES (surprising)** |

For empty-test, use the `empty` keyword or `.size`:

```liquid
{% unless x == empty %}…{% endunless %}
{% if rows.size > 0 %}…{% endif %}
```

`empty` matches `null`, `""`, and empty collections in one shot. `.size > 0` is more explicit when you mean "non-empty array."

## Type coercion

There is no implicit string-to-number coercion. Querystring and form values arrive as **String** and stay that way until you cast them.

| Filter | Example | Result |
|---|---|---|
| `integer` | `'42' \| integer` | `42` (Number) |
| `decimal` | `'3.14' \| decimal` | `3.14` (Number) |
| `boolean` | `'true' \| boolean` | `true`, also accepts `on`, `yes`, `enabled` |
| `string`  | `0 \| string` | `"0"` |

All four return `null` on conversion failure. Combine with `default:` to provide a fallback:

```liquid
{% assign page_num = request.params['page'] | default: '1' | integer %}
```

## Variable initialization

```liquid
{% assign name = expression %}                {# single expression with optional filters #}
{% capture name %}…multi-line content…{% endcapture %}    {# captures rendered output #}
```

Variable names are case-sensitive. `{% capture %}` is the only way to build a string from multiple lines/tags, `assign` is single-expression only.

## Common patterns

```liquid
{# Read querystring as Number with default #}
{% assign page_num = request.params['page'] | default: '1' | integer %}

{# Test for truly empty string (which is truthy by default) #}
{% if search_term == empty or search_term == '' %}
  No search term provided.
{% endif %}

{# Build an array from CSV #}
{% assign tags = 'featured,sale,new' | split: ',' %}

{# Iterate dictionary entries #}
{% for entry in request.params %}
  {{ entry[0] }}={{ entry[1] }}
{% endfor %}
```

## Common type-related mistakes

| Mistake | Fix |
|---|---|
| `{% if 0 %}` (expects falsy) | `{% if n > 0 %}` or `{% if n != 0 %}` |
| `{% if "" %}` (expects falsy) | `{% if x == empty %}` or `{% if x == '' %}` |
| `{% if rows %}` for empty-array check | `{% if rows.size > 0 %}` |
| `request.params['n'] + 1` (string concat, not addition) | `{% assign n = request.params['n'] \| integer \| plus: 1 %}` |
| `{% if x in [1,2,3] %}` (no array literal syntax) | `{% assign valid = '1,2,3' \| split: ',' %}{% if valid contains x \| string %}…` |
| `{{ list.length }}` | `{{ list.size }}` |
| `{% assign flag = "true" %}` then `{% if flag %}` | `{% assign flag = true %}`, quotes make it a truthy string |

## See also

- [operators.md](operators.md), comparison operators and full truthiness rules
- [filters.md](filters.md), type-coercion filters (`integer`, `decimal`, `boolean`, `string`) and date format strings
- [objects.md](objects.md), built-in objects and the types of their attributes

> Verified against Microsoft Learn 2026-04-29.
