# Liquid Operators in Power Pages

Power Pages runs DotLiquid, and Microsoft documents the operator surface in two pages: the operator inventory at `/power-pages/configure/liquid/liquid-operators` and the truthiness rules at `/power-pages/configure/liquid/liquid-conditional-operators`. This file is the cross-reference of what those pages actually guarantee, and what they don't. Anything outside this set is either undocumented or unsupported.

## Operator inventory

| Operator | Use |
|---|---|
| `==` | Equals |
| `!=` | Not equals |
| `>` `<` `>=` `<=` | Numeric / comparable ordering |
| `and` | Logical AND |
| `or` | Logical OR |
| `contains` | Substring in string, OR string in array of strings |
| `startswith` | String prefix test |
| `endswith` | String suffix test |

Operators **NOT** documented by Microsoft for Power Pages, do not use them, even if a sandbox accepts them: `<>`, `not`, `in`, `&&`, `||`. There is no negation operator. Invert with `{% unless %}` or `!=`.

## Truthiness rules

Microsoft, verbatim: **"null and the Boolean value false are treated as false; everything else is treated as true."**

That "everything else" is wider than most developers expect. The surprising cases are the ones that bite:

| Value | Truthy? |
|---|---|
| `true` | yes |
| `false` | no |
| `null` | no |
| any string, including `""` | **YES (surprising)** |
| `0`, any number | **YES (surprising)** |
| any array/dict, including empty | **YES (surprising)** |
| any object | yes |

**Warning:** `{% if rows %}` is true even when `rows` is an empty array. `{% if name %}` is true even when `name == ""`. `{% if count %}` is true even when `count == 0`. None of these check what they look like they check.

## Empty-test pattern

The right way to test for emptiness is the `empty` keyword for strings/collections, or `.size > 0` for arrays:

```liquid
{% unless page.title == empty %}<h1>{{ page.title }}</h1>{% endunless %}
{% if page.children.size > 0 %}…{% endif %}
```

`empty` matches `null`, `""`, and empty collections, it's the catch-all. `.size > 0` is more explicit when you mean "non-empty array" and excludes the string-of-length-zero case.

## Operator precedence

**Microsoft does not document operator precedence or parenthesis grouping.** Do not assume C-style precedence and do not assume `( ... )` groups expressions, DotLiquid's parser doesn't honor either.

The DotLiquid implementation evaluates conditions **left to right with no precedence**, so:

```liquid
{% if a or b and c %}    {# parses as: (a or b) and c, NOT (a or (b and c)) #}
```

When logic is non-trivial, push it to intermediate `{% assign %}` expressions instead of relying on grouping:

```liquid
{% assign needs_review = item.status == 'New' %}
{% assign is_priority  = item.priority == 'High' %}
{% if is_priority and needs_review %}…{% endif %}
```

## `contains` examples

`contains` does double duty, substring test on a string, and membership test on an array of strings:

```liquid
{# substring test on a string #}
{% if page.title contains 'Application' %}
  This is an application page.
{% endif %}

{# membership test on an array of strings #}
{% assign roles = user.roles %}
{% if roles contains 'Authenticated Users' %}
  Show the signed-in nav.
{% endif %}
```

`contains` does **not** test for object membership in an array of objects. To check whether a row matches a value across an object array, loop with `{% if %}` or use the `where` filter.

## Common mistakes

| Wrong | Right |
|---|---|
| `{% if a && b %}` | `{% if a and b %}` |
| `{% if x <> y %}` | `{% if x != y %}` |
| `{% if not x %}` | `{% unless x %}…{% endunless %}` or `{% if x == false %}` |
| `{% if "" %}` (expects falsey) | `{% if x == empty %}` or `{% if x.size > 0 %}` |
| `{% if rows.length > 0 %}` | `{% if rows.size > 0 %}` |
| `{% if 0 %}` (expects falsey) | `{% if n > 0 %}` |
| `{% if a or (b and c) %}` (expects grouping) | `{% assign tmp = b and c %}{% if a or tmp %}` |
| `{% if user.roles in 'Admin' %}` | `{% if user.roles contains 'Admin' %}` |

> Verified against Microsoft Learn 2026-04-29.
