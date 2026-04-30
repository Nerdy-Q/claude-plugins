# Power Pages Site Settings

A **site setting** is a named string value the runtime reads to flip behavior, expose tables to the Web API, configure auth providers, attach HTTP headers, or tune search. It's the closest thing Power Pages has to a `web.config`, except settings live as Dataverse rows on the `adx_sitesetting` table (or, in the enhanced data model, the `powerpagesitesetting` table) rather than in a config file.

Two scopes exist:

- **Website settings**, a row with a populated `adx_websiteid` lookup. Applies only to that one site. This is what you almost always want.
- **Global settings**, environment-wide, no website lookup. Applies to every site in the Dataverse environment. Created from the **Settings** node (not **Site settings**) in the Portal Management app.

Setting lookup is **first-write-wins by name within the website**. If two rows exist with the same `adx_name` against the same site, the runtime picks the first record it finds and ignores the rest. Dedupe before debugging anything else.

## The site setting record

| Field | Logical name | Purpose |
|---|---|---|
| Name | `adx_name` | The setting key, case-sensitive lookup string, e.g. `Webapi/contact/enabled` |
| Value | `adx_value` | String value (parsed as bool/int/comma-list/JSON depending on setting) |
| Website | `adx_websiteid` | Lookup to `adx_website` (or `powerpagesite` in EDM); empty for global |
| Description | `adx_description` | Free text, for humans only, not read by the runtime |
| Status | `statecode` / `statuscode` | **MUST be Active (statecode = 0, statuscode = 1)** or the setting is ignored |

The `statecode` requirement bites people. A deactivated site setting still appears in lists but is not read by the runtime. If a setting "isn't taking effect," confirm `statecode = 0` first, before spelunking the value.

## Case sensitivity rule

> **Per Microsoft convention, setting names are lowercase after the prefix slash:** `Webapi/<entity>/enabled`, not `Webapi/<entity>/Enabled`. The prefix segment (`Webapi`, `Authentication`, `Search`, `HTTP`, `Site`, `Profile`, `Header`, `Footer`) is conventionally PascalCase but matched case-insensitively in practice. The provider segment (`AzureAD`, `OpenIdConnect`, etc.) is matched as-is.

When you copy from older `adxportals` documentation you'll see PascalCase suffixes like `/Enabled`. Normalize them to lowercase. The runtime accepts both in most cases, but the lowercase form is what current Microsoft docs and the Studio emit, and consistency matters when grepping a YAML export.

The `<entity>` segment in `Webapi/<entity>/...` is the **table logical name**, `account`, `contact`, `incident`, `contoso_application`. Logical names are always lowercase in Dataverse, so this segment is naturally lowercase.

## Webapi/*: Per-table Web API enablement

To expose any table to `/_api/<entityset>`, both rows must exist and be Active:

| Setting | Value | Notes |
|---|---|---|
| `Webapi/<entity>/enabled` | `true` | Default `false`. Without this row, `/_api/<entityset>` returns 404. |
| `Webapi/<entity>/fields` | `*` or `attr1,attr2,attr3` | **Mandatory.** No fields = "No fields defined for this entity" error. `*` = all attributes. |
| `Webapi/error/innererror` | `true` | One global toggle (no `<entity>` segment). Surfaces the `innererror` block in OData error JSON for debugging. Default `false`. |
| `Webapi/<entity>/disableodatafilter` | `true` | Disables OData `$filter` parsing for the table, workaround for known filter bugs. Available 9.4.10.74+. Default `false`. |

`<entity>` is the **logical name**, not schema name and not entityset name. So for the `Account` table:

```
Webapi/account/enabled         = true
Webapi/account/fields          = name,accountnumber,telephone1
```

Common gotchas:

- A field listed in `Webapi/<entity>/fields` that the calling user can't read via Table/Column Permissions still produces a 401, the setting opens the API surface, permissions enforce who can use it
- The `annotation` table needs its own pair (`Webapi/annotation/enabled = true`, `Webapi/annotation/fields = *`) for file uploads via `/_api/annotations`
- The `msdyn_richtextfile` table needs the same pair if rich-text editor images should round-trip
- Configuration tables (`adx_contentsnippet`, `adx_entityform`, `adx_entitylist`, etc.) are **not supported** via the Web API regardless of these settings

See [webapi-patterns.md](webapi-patterns.md) for the calling code.

## Authentication/*: Identity providers

### General

| Setting | Default | Purpose |
|---|---|---|
| `Authentication/Registration/LocalLoginEnabled` | `True` | Allow username/email + password sign-in. Recommended `False` once an external IdP is wired up. |
| `Authentication/Registration/LocalLoginByEmail` | `False` | Use email instead of username for local login. |
| `Authentication/Registration/ExternalLoginEnabled` | `True` | Allow external IdP sign-in/registration. |
| `Authentication/Registration/RememberMeEnabled` | `True` | Show "Remember me?" check box on local sign-in. |
| `Authentication/Registration/TwoFactorEnabled` | `False` | Enable 2FA for local accounts (email-based). |
| `Authentication/Registration/RememberBrowserEnabled` | `True` | Persist 2FA "remember browser" cookie. |
| `Authentication/Registration/ResetPasswordEnabled` | `True` | Surface password reset flow. |
| `Authentication/Registration/ResetPasswordRequiresConfirmedEmail` | `False` | Block reset emails to unconfirmed addresses. |
| `Authentication/Registration/RequiresConfirmation` | `False` | Email confirmation required; disables open registration. |
| `Authentication/Registration/RequiresInvitation` | `False` | Invitation code required; disables open registration. |

### Local password validator

| Setting | Default | Purpose |
|---|---|---|
| `Authentication/UserManager/PasswordValidator/EnforcePasswordPolicy` | `True` | Three of four char categories required (upper / lower / digit / nonalpha). |
| `Authentication/UserManager/PasswordValidator/RequiredLength` | `8` | Minimum length. |
| `Authentication/UserManager/PasswordValidator/RequireNonLetterOrDigit` | `False` | Force special character. |
| `Authentication/UserManager/PasswordValidator/RequireDigit` | `False` | Force digit. |
| `Authentication/UserManager/PasswordValidator/RequireLowercase` | `False` | Force lowercase. |
| `Authentication/UserManager/PasswordValidator/RequireUppercase` | `False` | Force uppercase. |
| `Authentication/UserManager/UserValidator/AllowOnlyAlphanumericUserNames` | `False` | Lock username to alphanumeric. |
| `Authentication/UserManager/UserValidator/RequireUniqueEmail` | `True` | Reject duplicate emails. |

### Per-provider OpenID Connect

Replace `{Provider}` with whatever name you used when adding the provider in Studio (e.g. `AzureAD`). Names are case-sensitive, `AzureAD` and `azuread` are different keys.

| Setting | Notes |
|---|---|
| `Authentication/OpenIdConnect/{Provider}/Authority` | Authority URL, e.g. `https://login.microsoftonline.com/<tenantid>/` |
| `Authentication/OpenIdConnect/{Provider}/ClientId` | App registration client ID |
| `Authentication/OpenIdConnect/{Provider}/ClientSecret` | Required when response_type contains `code` |
| `Authentication/OpenIdConnect/{Provider}/RedirectUri` | Reply URL, must match app registration exactly |
| `Authentication/OpenIdConnect/{Provider}/MetadataAddress` | OIDC metadata document URL |
| `Authentication/OpenIdConnect/{Provider}/Scope` | Default `openid`. Add `email`, `profile` as needed. Space-separated. |
| `Authentication/OpenIdConnect/{Provider}/ResponseType` | `code id_token` (default), `code`, `id_token`, `id_token token`, `code id_token token` |
| `Authentication/OpenIdConnect/{Provider}/ResponseMode` | `form_post` default; use `query` when ResponseType is `code` |
| `Authentication/OpenIdConnect/{Provider}/Caption` | The text on the sign-in button (e.g. rename to "Contoso Work Account") |
| `Authentication/OpenIdConnect/{Provider}/ExternalLogoutEnabled` | Federated sign-out toggle |
| `Authentication/OpenIdConnect/{Provider}/PostLogoutRedirectUri` | Where the IdP returns users after logout |
| `Authentication/OpenIdConnect/{Provider}/RPInitiatedLogoutEnabled` | Allow RP-initiated logout (requires ExternalLogoutEnabled) |
| `Authentication/OpenIdConnect/{Provider}/IssuerFilter` | Wildcard issuer match for multitenant, e.g. `https://sts.windows.net/*/` |
| `Authentication/OpenIdConnect/{Provider}/ValidateAudience` | Bool, validate `aud` claim |
| `Authentication/OpenIdConnect/{Provider}/ValidAudiences` | Comma-separated audience URIs |
| `Authentication/OpenIdConnect/{Provider}/ValidateIssuer` | Bool, validate `iss` claim |
| `Authentication/OpenIdConnect/{Provider}/ValidIssuers` | Comma-separated issuer URIs |
| `Authentication/OpenIdConnect/{Provider}/RegistrationClaimsMapping` | `field=jwt_attr,…`, maps claims to contact fields on register |
| `Authentication/OpenIdConnect/{Provider}/LoginClaimsMapping` | Same shape, applied on every sign-in |
| `Authentication/OpenIdConnect/{Provider}/UseUserInfoEndpointforClaims` | `True` to call UserInfo endpoint for claims |
| `Authentication/OpenIdConnect/{Provider}/UserInfoEndpoint` | Override UserInfo URL (otherwise discovered from metadata) |
| `Authentication/OpenIdConnect/{Provider}/NonceLifetime` | Nonce lifetime in minutes (default 10) |
| `Authentication/OpenIdConnect/{Provider}/UseTokenLifetime` | Bool, match cookie lifetime to token lifetime |
| `Authentication/OpenIdConnect/{Provider}/AllowContactMappingWithEmail` | Bool, auto-link contact by email (single-tenant only) |
| `Authentication/OpenIdConnect/{Provider}/RegistrationEnabled` | Bool, show sign-up page |
| `Authentication/OpenIdConnect/{Provider}/PostLogoutRedirectUri` | Sign-out redirect target |

For Azure AD B2C specifically: `Authority` is the issuer URL (must include `tfp`), and the password reset flow adds `DefaultPolicyId`, `PasswordResetPolicyId`, and a comma-delimited `ValidIssuers` list of all the user-flow issuer URLs.

### Per-provider SAML 2.0

| Setting | Notes |
|---|---|
| `Authentication/SAML2/{Provider}/MetadataAddress` | Federation metadata URL |
| `Authentication/SAML2/{Provider}/AuthenticationType` | `entityID` value from metadata |
| `Authentication/SAML2/{Provider}/ServiceProviderRealm` | App ID URI / site URL |
| `Authentication/SAML2/{Provider}/AssertionConsumerServiceUrl` | Reply URL |
| `Authentication/SAML2/{Provider}/ValidateAudience` | Bool |
| `Authentication/SAML2/{Provider}/ValidAudiences` | Comma-separated |
| `Authentication/SAML2/{Provider}/AllowContactMappingWithEmail` | Bool |
| `Authentication/SAML2/{Provider}/ExternalLogoutCertThumbprint` | Custom cert thumbprint for SAML logout signing |

Power Pages is a **SAML 2.0 only** SP, requires signed responses, requires persistent name identifiers, requests `PasswordProtectedTransport`, and does **not** support encrypted assertions or signed assertion requests. If your IdP requires those, federate it through Microsoft Entra External ID.

### Bearer authentication (MCP server, API auth)

| Setting | Value |
|---|---|
| `Authentication/BearerAuthentication/Enabled` | `True` |
| `Authentication/BearerAuthentication/Protocol` | `OpenIdConnect` |
| `Authentication/BearerAuthentication/Provider` | `AzureAD` (matches an OIDC `{Provider}` key) |
| `Authentication/BearerAuthentication/UseEntraV2Issuer` | `True` for v2.0 endpoints |
| `Authentication/BearerAuthentication/ValidIssuers` | Comma-separated issuer URIs from the OIDC metadata document |

Used together with `Authentication/OpenIdConnect/{Provider}/MCPClientId` and `MCPScope` to enable MCP server (`MCP/Enabled = true`).

References: <https://learn.microsoft.com/power-pages/security/authentication/openid-settings>, <https://learn.microsoft.com/power-pages/security/authentication/saml2-provider>, <https://learn.microsoft.com/power-pages/security/authentication/set-authentication-identity>

## Search/*: Site search

| Setting | Default | Purpose |
|---|---|---|
| `Search/Enabled` | `True` | Master toggle. `False` hides the search box from out-of-the-box header and short-circuits `/search` page. |
| `Search/EnableDataverseSearch` | `True` (sites 9.4.4.x+) | Use Dataverse search backend. `False` falls back to Lucene.NET (deprecated). |
| `Search/EnableAdditionalEntities` | `False` | Enable searching additional tables. Requires `Search/Enabled = True`. |
| `Search/EnableProgressiveSearchCounts` | `False` | Process up to 5 pages × 50 records to fix count/permission mismatch. |
| `Search/IndexQueryName` | `Portal Search` | Name of the Dataverse view that defines indexed fields per table. |
| `Search/Stemmer` | `English` | Stemming language (Lucene only). |
| `Search/FacetedView` | `True` | Enable left-rail facets on search page. |
| `Search/Filters` | (long default) | Site-wide search filter dropdown. Format: `Label1:logicalname1,logicalname2;Label2:logicalname3`. |
| `Search/RecordTypeFacetsEntities` | (long default) | Same shape as `Filters`, for record-type facets. |
| `Search/Query` | (Lucene query string) | Override Lucene-side weighting and filtering. Lucene-only, ignored for Dataverse search and for `{% search %}` Liquid tag. |
| `Search/IndexNotesAttachments` | `False` | Index file content of annotation attachments on KB articles and web files. |
| `KnowledgeManagement/DisplayNotes` | `True` (default text says False, verify) | Surface KB-article attachments in results. |
| `KnowledgeManagement/NotesFilter` | `*WEB*` | Prefix that note text must start with to appear publicly. |

Generative-AI search is configured from the Set up workspace and disables faceted search when active.

References: <https://learn.microsoft.com/power-pages/configure/search/overview>, <https://learn.microsoft.com/power-pages/configure/search/faceted>, <https://learn.microsoft.com/power-pages/configure/search/progressive>

## HTTP/*: Response headers, CORS, CSP

Each `HTTP/*` site setting maps 1:1 to an HTTP response header the runtime emits.

### CORS

| Setting | Header |
|---|---|
| `HTTP/Access-Control-Allow-Origin` | `Access-Control-Allow-Origin`, Dataverse URL or `*` |
| `HTTP/Access-Control-Allow-Headers` | `Access-Control-Allow-Headers`, comma-separated |
| `HTTP/Access-Control-Allow-Methods` | `Access-Control-Allow-Methods`, comma-separated (`GET,POST,OPTIONS,...`) |
| `HTTP/Access-Control-Allow-Credentials` | `Access-Control-Allow-Credentials`, only valid value is `true` (case-sensitive); omit setting to leave header off |
| `HTTP/Access-Control-Expose-Headers` | `Access-Control-Expose-Headers` |
| `HTTP/Access-Control-Max-Age` | `Access-Control-Max-Age`, seconds |

### Frame / MIME / referrer

| Setting | Header / behavior |
|---|---|
| `HTTP/X-Frame-Options` | `X-Frame-Options`, default `SAMEORIGIN` (anti-clickjacking) |
| `HTTP/X-Content-Type-Options` | `X-Content-Type-Options: nosniff` |

`Cache-Control` is **not** configurable via site settings, Power Pages emits it automatically (`max-age=3600` for anonymous static files).

### CSP

| Setting | Mode |
|---|---|
| `HTTP/Content-Security-Policy` | Enforcement |
| `HTTP/Content-Security-Policy-Report-Only` | Report-only (logs violations, doesn't block) |

See **CSP deep dive** below.

References: <https://learn.microsoft.com/power-pages/configure/cors-support>, <https://learn.microsoft.com/power-pages/security/manage-content-security-policy>

## Site/*: Site-wide flags

| Setting | Value | Purpose |
|---|---|---|
| `Site/EnableDefaultHtmlEncoding` | `True`/`False` | Default `True` on 9.3.8+. When `True`, `user` and `request` Liquid objects auto-`escape` filter their output. Set `False` to disable (rarely correct). |
| `Site/BootstrapV5Enabled` | `True`/`False` | Enables Bootstrap 5 styling. New EDM sites get this automatically; legacy sites set this after running `pac pages bootstrap-migrate`. Delete the row to revert to v3. |
| `Site/EnableContentSnippetTranslationForForms` | `True`/`False` | Enables `[[ContentSnippet.{name}.field]]` reference syntax for translating basic-form labels into custom languages. |
| `EnhancedFileUpload` | `True`/`False` | Opt-in for the enhanced file-upload experience on existing sites (new sites since 9.3.2405.x have it on automatically). Note: no `Site/` prefix, it's a top-level key. |

References: <https://learn.microsoft.com/power-pages/configure/configure-site-settings>, <https://learn.microsoft.com/power-pages/configure/bootstrap-version-5>

## Documents & file upload limits

There is **no** Power Pages site setting named `Documents/MaxFileSize` (a common misremembering). File upload size in Power Pages is governed by a **layered** set of settings, depending on which storage backend the upload uses.

### Notes (annotation) storage: the default

When attachments save to the `annotation` table (Notes storage), the binding ceiling is the **Dataverse environment** setting, not a Power Pages site setting:

| Setting | Where | Default | Max | Purpose |
|---|---|---|---|---|
| `Organization.MaxUploadFileSize` | Power Platform admin → Environment → Settings → Email tab | 5 MB | 128 MB | Hard cap on annotation `documentbody` size, applied to base64-encoded payload (so net file ceiling is ~75% of the value) |

Per-form, the **Studio** "Upload size limit per file (in KB)" on the form's Attachments panel clamps it lower for that form. The Studio control is the per-form ceiling; the env-level setting is the absolute ceiling.

### SharePoint document management

When the parent entity has SharePoint document management enabled (see [Manage SharePoint documents](https://learn.microsoft.com/power-pages/configure/manage-sharepoint-documents)), attachments route to SharePoint instead of Notes. Two Power Pages site settings:

| Setting | Default | Purpose |
|---|---|---|
| `SharePoint/MaxUploadSize` | `10` (MB) | Per-file SharePoint upload ceiling. Max **50 MB**. Value in MB. |
| `SharePoint/MaxTotalUploadSize` | (no default; advisory) | Combined size cap across multi-file uploads. Value in MB. |

Reference: <https://learn.microsoft.com/power-pages/configure/manage-sharepoint-documents#configure-file-upload-size>

### Azure Blob Storage Web API path

When the site uses the Azure Blob Storage upload Web API (`Site/FileManagement/EnableWebAPI = true`), a separate set of settings applies:

| Setting | Default | Purpose |
|---|---|---|
| `Site/FileManagement/EnableWebAPI` | `false` | Master toggle. **Required** for any of the rest. |
| `Site/FileManagement/BlobStorageAccountName` | (none) | Azure storage account name. **Required.** |
| `Site/FileManagement/BlobStorageContainerName` | (none) | Azure container name. **Required.** |
| `Site/FileManagement/SupportedFileType` | (none) | Comma-separated extensions, e.g. `.pdf,.jpg,.png`. **Required.** |
| `Site/FileManagement/SupportedMimeType` | (none) | Semicolon-separated MIME types. **Required.** |
| `Site/FileManagement/MaxFileSize` | `1048576` (KB, ~1 GB) | Max per-file size. **In KB**, not bytes. |
| `Site/FileManagement/DownloadViaSASUri` | `true` | Use SAS URI for downloads. |
| `Site/FileManagement/DownloadSASUriExpiryTimeSpan` | `00:10:00` | SAS URI expiry. Used only when SAS download is enabled. |
| `Site/FileManagement/DownloadChunkSizeInKB` | `4096` (4 MB) | Chunk size for non-SAS downloads. |

Reference: <https://learn.microsoft.com/power-pages/configure/webapi-azure-blob>

### Enhanced upload UX toggle

| Setting | Default | Purpose |
|---|---|---|
| `EnhancedFileUpload` | new sites: `True`; older sites: opt-in | Toggle for the new file-upload UX (progress bar, per-file errors, delete control). **Does not affect size limits.** No `Site/` prefix, top-level key. |

Reference: <https://learn.microsoft.com/power-pages/getting-started/add-form#new-file-upload-experience>

### Common mismatches

- **Recipe code says 10 MB but uploads fail at 5 MB** → Dataverse `Organization.MaxUploadFileSize` is at default 5 MB; raise it via Power Platform admin
- **Studio limit set to 50 MB but uploads fail at 10 MB on SharePoint** → `SharePoint/MaxUploadSize` defaults to 10 MB; bump to 50
- **Web API uploads fail at 1 GB despite `Site/FileManagement/MaxFileSize = 1048576`** → value is in KB, not bytes; 1 GB = `1048576` KB is correct. If you set `1048576000` you set 1 TB, which the platform clamps elsewhere.

## Profile/*: User profile

| Setting | Default | Purpose |
|---|---|---|
| `Profile/ForceSignUp` | `False` | Force users to complete profile before any other site access. |
| `Profile/ShowMarketingOptionsPanel` | `False` | Show the marketing comms-preference panel on profile. (Out-of-the-box doc lists default `True` in some places, verify per template.) |

## Header/Footer/*: Output caching

| Setting | Value | Purpose |
|---|---|---|
| `Header/OutputCache/Enabled` | `True` | Cache the header web template output. |
| `Footer/OutputCache/Enabled` | `True` | Cache the footer web template output. |

Requires accompanying changes to the header / footer / Languages Dropdown web templates to wrap user-specific blocks with `{% substitution %}…{% endsubstitution %}` and to use `language.url_substitution`. Skipping the template edits will cache the wrong user's data into everyone's pages.

Reference: <https://learn.microsoft.com/power-pages/configure/enable-header-footer-output-caching>

## HelpDesk/*, CustomerSupport/*: Help desk template

| Setting | Default | Purpose |
|---|---|---|
| `HelpDesk/CaseEntitlementEnabled` | `False` | Enable case entitlement on the help-desk template. |
| `HelpDesk/Deflection/DefaultSelectedProductName` | (empty) | Pre-selected product on the case-deflection page. |
| `CustomerSupport/DisplayAllUserActivitiesOnTimeline` | `False` | Whether to show all activity types on the case timeline. |

## Bingmaps/*, Geolocation

| Setting | Notes |
|---|---|
| `Bingmaps/credentials` | Bing Maps API key. **Required** for any geolocation form section. **Not supported** in German Sovereign Cloud, creating the row throws an error. |
| `Bingmaps/restURL` | Defaults to `https://dev.virtualearth.net/REST/v1/Locations`. Override only for sovereign clouds. |

## Common gotchas

1. **`statecode` must be 0 (Active)**, deactivated rows are silently ignored. After import / promotion across environments, this is the most common silent failure.
2. **Cache is sticky**, site settings are configuration-tier data. After a write, changes take **up to 15 minutes** to propagate (the SLA), or you can force it via Studio → Sync, the `/_services/about` page → Clear cache, or restart the site from Power Platform admin center. For auth changes, restart is recommended.
3. **Setting names are case-sensitive at the lookup level**. The runtime does a string-equal match on `adx_name`. `WebApi/contact/Enabled` and `Webapi/contact/enabled` will both compile, but the runtime looks for the exact casing it expects internally, Microsoft has standardized on lowercase suffixes (`/enabled`, `/fields`, `/clientid`).
4. **`Webapi/<entity>/fields` is mandatory**, the missing-fields error message ("No fields defined for this entity") is misleading; people often think they need to add field-level permissions. They need the row, with `*` or a comma list.
5. **Provider name in `Authentication/{Protocol}/{Provider}/...` is yours to choose** but every setting under that provider must use the **exact same casing**. `AzureAD/ClientId` and `azuread/Authority` won't bind together as one provider, the runtime keys on the segment string.
6. **`Authentication/Registration/RequiresConfirmation = True` AND `RequiresInvitation = True`**, both can be true; the user must satisfy both flows. This is the slowest possible registration UX and almost never what you want; pick one.
7. **Search settings without `Search/Enabled = True`** are no-ops, including `Search/EnableProgressiveSearchCounts` and `Search/EnableAdditionalEntities`.
8. **A duplicate `adx_name` against the same site** is silently picked at random. After bulk import / merge, run a dedupe FetchXML against `adx_sitesetting` filtered by `adx_websiteid` and grouped by `adx_name`.
9. **Rebuild the search index** after changing any `Search/*` setting that affects indexing (`EnableAdditionalEntities`, `EnableProgressiveSearchCounts`, `IndexNotesAttachments`). The setting alone doesn't reindex.
10. **`Site/BootstrapV5Enabled`**, don't create this manually. Run `pac pages bootstrap-migrate` first; the migration script writes the setting plus the supporting CSS / template edits. Hand-creating the row turns on v5 styles against v3 markup.

## CSP deep dive

CSP is the single most likely setting to break a working site if applied carelessly, and the single most likely to be missing on a site that thinks it's secure. New sites since November 10, 2025 ship with it; older sites must opt in.

### Default policy (new sites, post-Nov 2025)

```
script-src 'self' content.powerapps.com content.powerapps.us content.appsplatform.us content.powerapps.cn 'nonce';
style-src 'unsafe-inline' https:;
```

That single policy carries four CDN hosts that the runtime itself loads scripts from. Drop any one of them and core Power Pages JavaScript stops working.

### Sovereign cloud notes

The default policy is **identical across all clouds** because it lists every CDN: `content.powerapps.com` (commercial), `content.powerapps.us` (GCC and GCC High), `content.appsplatform.us` (DoD), `content.powerapps.cn` (China). If you write a custom policy you must keep the host that matches your environment, otherwise the platform's own scripts get blocked.

| Cloud | Required CDN host in `script-src` |
|---|---|
| Commercial | `content.powerapps.com` |
| GCC | `content.powerapps.us` |
| GCC High | `content.powerapps.us` (same host, gated by tenancy) |
| Power Apps DoD | `content.appsplatform.us` |
| China (21Vianet) | `content.powerapps.cn` |

The blanket-include-all-four approach in the default policy is the safe default; trim only if you know your cloud will never change and you want a tighter CSP.

### Working with report-only mode first

Before flipping enforcement on an existing site, deploy in report-only mode and watch the browser console for a few days:

```
HTTP/Content-Security-Policy-Report-Only
```

Value: same syntax as enforcement. Browsers log each violation but allow the resource. Once the console is clean, copy the value into `HTTP/Content-Security-Policy` and delete the report-only row.

You can also run both simultaneously: enforce a baseline policy and report-only a tighter candidate.

### Nonce

The `'nonce'` keyword in `script-src` is mandatory for inline scripts to run. Power Pages auto-injects the per-request nonce into:

- Inline `<script>` tags rendered through Liquid templates
- Inline event handlers (via auto-generated hashes)

Scripts created at runtime via `document.createElement('script')` **cannot** receive the nonce, move them to external files and add the source domain to `script-src`.

### Common scenarios (only the directives that change shown)

```
# Google Analytics
script-src 'self' content.powerapps.com 'nonce' https://www.googletagmanager.com https://www.google-analytics.com;
connect-src 'self' https://www.google-analytics.com https://analytics.google.com;
img-src 'self' https: data:;

# YouTube embed
frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com;

# Google Fonts
style-src 'unsafe-inline' https://fonts.googleapis.com;
font-src 'self' https://fonts.gstatic.com;

# Iframe embed in an external host
frame-ancestors 'self' https://www.contoso.com;
```

`'self'` in `frame-ancestors` is mandatory if the site uses any modal forms or Liquid `iframe` components, without it, the site can't even embed itself, and basic-form modals break.

If `font-src` blocks your icon font, that's an accessibility regression, see [accessibility.md] (when added) for keyboard-nav implications, but the immediate fix is adding the font CDN to `font-src`.

References: <https://learn.microsoft.com/power-pages/security/manage-content-security-policy>

## Adding and editing settings

### Studio (graphical, slowest, safest for one-offs)

1. Open the site for editing → **More items (…)** → **Portal Management**.
2. **Site Settings** node → **+ New**.
3. Fill **Name**, **Website**, **Value**. Save & Close.
4. Back in Studio, **Sync** to invalidate cache.

### Portal Management direct

Same place but accessible without going through Studio: <https://make.powerapps.com> → Apps → Portal Management → Site Settings.

### YAML (the path you'll use most often once a site is mature)

Site settings ride along with everything else on `pac pages download` / `pac pages upload`. They land in the downloaded folder under `<sitename>/sitesetting/<NAME>.sitesetting.yml`:

```yaml
adx_sitesettingid: 12345678-aaaa-bbbb-cccc-1111aaaa2222
adx_name: Webapi/contoso_application/enabled
adx_value: 'true'
adx_websiteid: 4d3f5b7e-aaaa-bbbb-cccc-9999dddd1111
statecode: 0
statuscode: 1
```

Edit the value, run:

```
pac pages upload --path ./mysite --modelVersion 2
```

Only changed files are uploaded (delta upload). Use `--forceUploadAll` if delta tracking is suspected to be out of sync (e.g. cherry-picked commits, branch switches, partial uploads).

For multi-environment promotion, use **deployment profiles** to override values per environment:

```
mysite/
  deployment-profiles/
    dev.deployment.yml
    test.deployment.yml
    prod.deployment.yml
```

A profile YAML looks like:

```yaml
adx_sitesetting:
  - adx_sitesettingid: 12345678-aaaa-bbbb-cccc-1111aaaa2222
    adx_name: Header/OutputCache/Enabled
    adx_value: 'false'           # disable in dev
```

Apply with:

```
pac pages upload --path ./mysite --deploymentProfile dev --modelVersion 2
```

### Environment variables (recommended for cross-env values)

Site settings can be **bound to a Dataverse environment variable** instead of a literal value. Create the env-var in a solution, then in Portal Management open the site setting and pick the env-var from the dropdown. Promoting the solution to test/prod prompts for the new value, and the site setting reads through the env-var at runtime.

Caveats:

- The env-var **type must match** the site setting's expected type (`Search/Enabled` is bool; an env-var value of `abc` causes a runtime error)
- Environment variable source type must be **Value** (Key Vault works for secrets, but only with proper RBAC)
- After updating the env-var value, **clear cache**, env-vars don't trigger automatic invalidation

### Pipelines / ALM Accelerator

Power Platform pipelines use the deployment-profile mechanism above; the pipeline UI accepts uploaded `.deployment.yml` files. ALM Accelerator looks for `PowerPages/Website/deployment-profiles/<env>.deployment.yml` in the solution branch.

After deployment, **always clear the cache** on the target site, pipelines don't do it automatically, so the new settings sit in Dataverse but the runtime keeps serving old values up to 15 minutes.

References: <https://learn.microsoft.com/power-pages/configure/power-platform-cli>, <https://learn.microsoft.com/power-pages/configure/environment-variables-for-site-settings>, <https://learn.microsoft.com/power-pages/configure/power-pages-pipelines>

## Cross-references

- **Web API enablement and JavaScript patterns** → [webapi-patterns.md](webapi-patterns.md). Site settings open the API; permissions enforce who can call it.
- **FetchXML and OData query patterns** → [fetchxml-patterns.md](fetchxml-patterns.md). Lookup behavior is also controlled here for portal lookups.
- **Web Roles, Table Permissions, Page Permissions** → [permissions-and-roles.md](permissions-and-roles.md). Site settings open API surface; permissions decide who passes through.
- **Bootstrap version, theming** → see `Site/BootstrapV5Enabled` above and the `pac pages bootstrap-migrate` workflow.
- **Accessibility (font CDN allowlists)** → make sure CSP `font-src` and `style-src` permit the host serving icon fonts and screen-reader-friendly assets.

> Verified against Microsoft Learn 2026-04-29.
