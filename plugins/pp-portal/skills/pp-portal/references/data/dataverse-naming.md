# Dataverse Naming and Casing: the Hidden Trap

**The single most surprising class of Power Pages bugs comes from Dataverse's multi-name model.** Every entity, column, and relationship has 3+ different "names," and Power Pages uses different ones in different contexts. Mixing them up gives you cryptic errors that don't say "you have a casing problem", they just say "name not found."

This reference is the cheat sheet for which name to use where.

## The four names every Dataverse object has

Every entity has these names:

| Name | Casing | Example (entity) | Where you see it |
|---|---|---|---|
| **Logical Name** | lowercase | `acme_customer` | Studio "Logical name" field; FetchXML; Web API attribute references |
| **Schema Name** | PascalCase (usually) | `acme_Customer` | Solution XML; navigation property names in `@odata.bind` |
| **Display Name** | human-readable | `Acme Customer` | UI labels, never used in code |
| **Entity Set Name** | lowercase plural | `acme_customers` | Web API URLs: `/_api/<entity-set-name>` |

Every column also has Logical Name + Schema Name + Display Name (no entity set name, since columns aren't URL-addressable).

Every relationship (lookup) has its **own** schema name that becomes the **Navigation Property Name**, and this is independent of the lookup column's logical name. This is where most of the pain is.

## The single rule that explains it all

> **Logical names → lowercase. Navigation properties → match the schema name (often PascalCase). Entity set names → lowercase plural.**

Power Pages uses logical names for FetchXML and most Web API attribute references, but uses navigation property names for `@odata.bind` and `$expand`. They look almost identical for system entities (Microsoft entities have all-lowercase nav props) but **diverge for custom entities** where developers typically PascalCase their schema names.

## Where each name applies

### Web API URL path

Entity set name (lowercase plural):

```
/_api/contacts                          system entity, plural
/_api/accounts
/_api/acme_customers                    custom entity, plural with prefix
/_api/acme_customers(<guid>)            single record by ID
```

Get the entity set name from `Entity.xml` (the `<EntityInfo>` `EntitySetName` attribute) or `pac data list-tables`.

### Web API `$select`, `$filter`, `$orderby`, attribute references

Lowercase logical names. For lookup columns, use the `_<attr>_value` form:

```javascript
'/_api/acme_customers'
  + '?$select=acme_customername,acme_customertype,_acme_account_value'   // logical names, lowercase
  + '&$filter=_acme_account_value eq ' + accountId                       // lookup filter form
  + '&$orderby=acme_customername asc'
```

| Attribute kind | Form |
|---|---|
| Text/number/etc. | `acme_customername` (lowercase logical) |
| Lookup column GUID | `_acme_account_value` (with leading underscore + `_value` suffix) |
| Choice (option set) | `acme_customertype` (lowercase logical) |

### Web API POST/PATCH payload: attribute keys

Lowercase logical names for direct attribute writes:

```javascript
{
  acme_customername: 'Jane Doe',
  acme_customertype: 100000000,
  acme_isactive: true
}
```

For lookups, use **navigation property + `@odata.bind`**, NOT `_<attr>_value`:

```javascript
{
  acme_customername: 'Jane Doe',
  'acme_Account@odata.bind': '/accounts(' + accountId + ')'    // navigation property casing
}
```

### Web API `@odata.bind`, navigation property names

**Match the schema name's casing.** This is the single most common Power Pages bug.

```javascript
// Correct, navigation property uses the schema name PascalCase:
'acme_Account@odata.bind': '/accounts(' + accountId + ')'

// WRONG, using lowercase logical name as nav property:
'acme_account@odata.bind': '/accounts(' + accountId + ')'
//        ^ this returns 400 "is not a valid navigation property"
```

You cannot infer the navigation property casing from the logical name. You must look it up in:
1. `dataverse-schema/<solution>/Entities/<entity>/Entity.xml`, search for `<Relationship>` and `<lookup>` elements
2. `/_api/$metadata`, the OData EDMX schema (requires auth)
3. The Maker Portal's **Relationships** view (NOT the Columns view, that shows attribute logical names, not nav prop names)

### Web API `$expand`, navigation property names

Same casing as `@odata.bind`:

```javascript
'/_api/contacts(' + contactId + ')?$expand=acme_Account($select=name,address1_city)'
```

### FetchXML in Liquid `{% fetchxml %}`

**All lowercase logical names**, everywhere, entity, attributes, link-entity, conditions:

```liquid
{% fetchxml q %}
<fetch mapping="logical">
  <entity name="acme_customer">                        {# logical: lowercase #}
    <attribute name="acme_customername" />             {# logical: lowercase #}
    <attribute name="acme_account" />                  {# logical: lowercase #}
    <link-entity name="account"                        {# logical: lowercase #}
                 from="accountid"
                 to="acme_account"                     {# attribute logical: lowercase #}
                 alias="parent_acct">
      <attribute name="name" alias="acct_name" />
    </link-entity>
    <filter>
      <condition attribute="acme_isactive"             {# logical: lowercase #}
                 operator="eq" value="1" />
    </filter>
  </entity>
</fetch>
{% endfetchxml %}
```

FetchXML doesn't use navigation property names at all, it uses attribute logical names plus `from`/`to` relationship pointers. So FetchXML is consistent: lowercase everywhere.

## Why "I copied it from Studio" doesn't help

Studio shows different names in different places:

| Studio view | What you see | What it actually is |
|---|---|---|
| Tables list | `acme_customer` | Logical name (lowercase) |
| Table detail → Columns | `acme_customername` | Attribute logical name (lowercase) |
| Table detail → Relationships | `acme_customer_account` (1:N relationship) | Schema name of the relationship |
| Table detail → Relationships → Lookup column | The column's **Schema Name**, often PascalCase | This IS the navigation property name |
| Solution XML view | Schema names (PascalCase) | Schema names |
| Web API endpoint URL builder | Entity set name (lowercase plural) | Entity set name |

If you copy from "Columns" you get the lowercase logical name. If you copy from "Relationships" you get the schema name (your nav property). Same field, two different copies, different casing.

**Rule of thumb**: when you need a navigation property for `@odata.bind` or `$expand`, **always look it up in the Relationships view** (or Entity.xml). Never assume it matches the logical name.

## Casing cheat sheet (printable)

```
                              ┌─ FetchXML ────────┐  ┌─ Web API ──────────────────────────┐
                              │                   │  │ URL    │ $sel  │ payload │ @bind  │
─────────────────────────────┼───────────────────┤  ├────────┼───────┼─────────┼────────┤
  Entity reference            │ logical lowercase │  │ entset │  ,   │   ,    │  ,    │
  Attribute (text/num/bool)   │ logical lowercase │  │  ,    │ lower │ lower   │  ,    │
  Lookup attribute (set)      │ logical lowercase │  │  ,    │  ,   │  ,     │ NavPP  │
  Lookup attribute (read)     │ logical lowercase │  │  ,    │ _lwr_value │, │  ,    │
  Navigation property         │      ,           │  │  ,    │  ,   │  ,     │ NavPP  │
```

Where:
- **logical lowercase** = `acme_customer`, `acme_customername`
- **entset** = entity set name, lowercase plural (`acme_customers`, `contacts`)
- **`_lwr_value`** = `_acme_account_value` (lowercased lookup logical with `_value` suffix)
- **NavPP** = Navigation Property name with **schema name casing** (`acme_Account`)

## Common error messages and what they really mean

| Error | Likely cause |
|---|---|
| `Could not find a property named '<name>'` | Used PascalCase / wrong casing for an attribute reference. Try lowercase logical name. |
| `'<name>' is not a valid navigation property` | Used lowercase / wrong casing for a navigation property. Check schema name in Entity.xml or Studio Relationships view. |
| `Resource not found for the segment '<name>'` | Wrong entity set name in URL. Check `Entity.xml` `EntitySetName` attribute. |
| `Cannot bind value of type Edm.String to property '<name>'` | Sent the wrong field type, but if the property name is unrecognizable, it's also possibly a casing issue. |
| `400 Bad Request` with no specific message | Often a casing mismatch in `@odata.bind`. Double-check nav property casing. |

## How to find the right name (programmatically)

### From an unpacked solution

```bash
# Entity set name for an entity:
grep -r "EntitySetName" dataverse-schema/<Solution>/Entities/<entity>/Entity.xml

# Navigation property names for an entity (look at Relationships):
grep -r "ReferencingEntityNavigationPropertyName\|ReferencedEntityNavigationPropertyName" \
    dataverse-schema/<Solution>/Entities/<entity>/Entity.xml

# All attribute logical names:
grep -E '<attribute\s+PhysicalName=' dataverse-schema/<Solution>/Entities/<entity>/Entity.xml \
  | sed 's/.*PhysicalName="\([^"]*\)".*/\1/' | sort -u
```

### From `pac` CLI

```bash
pac data list-tables                              # entity logical names + entity set names
pac data list-columns --entity <logical-name>     # column logical + display names
```

### From the Web API metadata endpoint

```bash
curl '$ENV_URL/_api/$metadata' -H "Authorization: ..."
# Returns OData EDMX XML, search for <NavigationProperty> elements with their Name and ToRole attributes
```

This is the most authoritative source, it's what the live Web API actually accepts.

### From the browser

In the Maker Portal:
1. Open the entity's detail
2. Tab: **Relationships** (NOT Columns)
3. Click the lookup relationship
4. Look at the **Schema Name** field, that's your navigation property

Then in the Web API URL builder:
1. Open the entity in any record list
2. Look at the URL, `/main.aspx?...etn=<logical>` shows the logical name
3. Or use `pac data list-tables` to get the entity set name

## Anti-pattern: `$expand` instead of separate fetches

Some developers, frustrated by the casing puzzle, give up on `$expand` and do separate Web API calls instead:

```javascript
// Anti-pattern: two calls because $expand requires nav property name
var contact = await safeAjax({ url: '/_api/contacts(' + id + ')?$select=fullname,_parentcustomerid_value' });
var account = await safeAjax({ url: '/_api/accounts(' + contact._parentcustomerid_value + ')?$select=name' });
```

This works but it's a round-trip wasted on a name-finding inconvenience. The `$expand` version is one call:

```javascript
// Better, once you have the right nav property name:
var contact = await safeAjax({
  url: '/_api/contacts(' + id + ')'
     + '?$select=fullname'
     + '&$expand=parentcustomerid_account($select=name)'
});
// Note: parentcustomerid is polymorphic, so the nav prop is parentcustomerid_account or parentcustomerid_contact
```

If you find yourself doing 2-call workarounds, take 5 minutes to find the correct `$expand` name, usually a permanent fix.

## Polymorphic lookups: the worst-case casing trap

Customer-type lookups (target Account OR Contact) have **two** navigation properties on the source entity, one per target:

```javascript
// For an applicant field that targets Contact OR Account:
{
  'acme_Applicant_contact@odata.bind': '/contacts(' + contactId + ')',     // for Contact
  // OR
  'acme_Applicant_account@odata.bind': '/accounts(' + accountId + ')',     // for Account

  // WRONG, bare `acme_Applicant@odata.bind` is ambiguous, returns 400
  // WRONG, `acme_applicant_contact` (lowercased) is also wrong
}
```

The audit (`pp-permissions-audit`) catches this with WRN-001. See `webapi-patterns.md` for the full polymorphic pattern.

## Bottom line

When in doubt, **read Entity.xml**. The schema is the source of truth. Studio shows different views; documentation is sometimes stale; only the unpacked solution XML and the live `/_api/$metadata` endpoint are authoritative.

Or: build a one-time cheat sheet for your project. Run this once after every solution sync:

```bash
# Generates a name reference for all your custom entities
for d in dataverse-schema/<Solution>/Entities/*/; do
  entity=$(basename "$d")
  echo "=== $entity ==="
  grep -E "EntitySetName=|<attribute PhysicalName=|NavigationPropertyName" "$d/Entity.xml" | head -20
done > name-reference.md
```

Commit `name-reference.md` to the project repo. Future-you will thank present-you.
