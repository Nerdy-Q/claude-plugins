# Recipe: File Upload via /_api/annotations

## What you'll build

An "Attach files" page where users select one or more files, the JS reads each as base64, and POSTs an annotation (note) to Power Pages, linking it to a parent record. Annotations are how the platform stores file attachments, they live on the `annotation` (notes) table with a polymorphic lookup back to whatever record they belong to.

The flow:

1. User picks files via `<input type="file" multiple>` or drag-drop
2. JS reads each file as base64
3. JS POSTs to `/_api/annotations` with `documentbody`, `mimetype`, `filename`, and the `objectid_<entity>@odata.bind` polymorphic lookup
4. JS shows progress per file and the final list of attached files

## Pre-flight checklist

| Requirement | Where | Value |
|---|---|---|
| `Webapi/annotation/enabled` site setting | site-settings YAML | `true` (Active) |
| `Webapi/annotation/fields` site setting | site-settings YAML | `subject,filename,mimetype,documentbody,notetext,objectid` (whitelist; never `*`) |
| Table Permission allowing Create on `annotation` | table-permissions YAML | Scope = Parent, parent permission = the parent entity's permission |
| Web Role on the parent record's Table Permission | Studio | The user must own the parent record (or have access via Account scope) |
| Parent entity already has a record |, | You can't attach to a record that does not exist; create the parent first |

The `Parent` scope on the annotation Table Permission cascades from the parent entity's permission, the user can attach to a parent record if they can read the parent. If you set the annotation permission to `Global`, **any user can attach to any record**, security hole.

> Annotations are also where SharePoint integration kicks in. If your environment has SharePoint document management enabled on the parent entity, files over a configurable size threshold get auto-redirected to SharePoint and the annotation only stores metadata. **No code change needed**, but the user-visible URL changes.

## Page setup

This recipe assumes the parent record (e.g. a contact) already exists and its ID is in the querystring as `?id=<guid>&type=contact`. The page name is `Attach Files`.

```
web-pages/attach-files/
  AttachFiles.webpage.yml
  AttachFiles.webpage.copy.html
  AttachFiles.webpage.custom_javascript.js
  content-pages/
    AttachFiles.en-US.webpage.copy.html
```

## Step 1: HTML file input + drop zone + progress UI

```liquid
{% assign parent_id   = request.params['id'] | escape %}
{% assign parent_type = request.params['type'] | default: 'contact' | escape %}

{% if parent_id == '' %}
  <div class="alert alert-warning">No record specified.</div>
{% else %}

  <header class="mb-4">
    <h1>Attach files</h1>
    <p class="text-muted">Drag files into the box below, or click to choose. Max 10 MB per file.</p>
  </header>

  <div id="uploadAlert" class="alert alert-danger d-none" role="alert" aria-live="polite"></div>

  <form id="uploadForm" novalidate>
    <input type="hidden" id="parentId"   value="{{ parent_id }}" />
    <input type="hidden" id="parentType" value="{{ parent_type }}" />

    <div id="dropZone"
         class="border border-2 border-dashed rounded p-4 text-center mb-3"
         tabindex="0"
         role="button"
         aria-label="Choose files or drop them here">
      <p class="mb-2"><strong>Drop files here</strong></p>
      <p class="mb-2 text-muted">or</p>
      <label for="fileInput" class="btn btn-outline-primary">Choose files</label>
      <input type="file" id="fileInput" multiple class="d-none"
             accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.xlsx,.csv" />
    </div>

    <ul id="uploadList" class="list-group mb-3" aria-live="polite"></ul>
  </form>

  <h2 class="h5">Already attached</h2>
  <ul id="existingList" class="list-group">
    <li class="list-group-item text-muted">Loading...</li>
  </ul>

{% endif %}
```

Notes:

- The hidden inputs hold the parent record context, easier than re-parsing querystring in JS
- `accept=".pdf,..."` is a UX hint, not security; server still must enforce
- `tabindex="0"` + `role="button"` makes the drop zone keyboard-actionable
- Two lists: `#uploadList` for in-progress uploads, `#existingList` for already-attached files

## Step 2: JS reads files as base64

```javascript
// AttachFiles.webpage.custom_javascript.js
(function (webapi, $) {
  'use strict';

  function safeAjax(ajaxOptions) {
    var deferredAjax = $.Deferred();
    shell.getTokenDeferred().done(function (token) {
      if (!ajaxOptions.headers) {
        $.extend(ajaxOptions, { headers: { '__RequestVerificationToken': token } });
      } else {
        ajaxOptions.headers['__RequestVerificationToken'] = token;
      }
      $.ajax(ajaxOptions)
        .done(function (data, textStatus, jqXHR) {
          validateLoginSession(data, textStatus, jqXHR, deferredAjax.resolve);
        })
        .fail(deferredAjax.reject);
    }).fail(function () { deferredAjax.rejectWith(this, arguments); });
    return deferredAjax.promise();
  }
  webapi.safeAjax = safeAjax;
})(window.webapi = window.webapi || {}, jQuery);

var MAX_BYTES = 10 * 1024 * 1024;  // 10 MB per file
var ALLOWED_MIMES = [
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'image/png',
  'image/jpeg',
  'text/csv'
];

function fileToBase64(file) {
  return new Promise(function (resolve, reject) {
    var reader = new FileReader();
    reader.onload  = function () {
      // FileReader.readAsDataURL returns "data:<mime>;base64,<payload>"
      // documentbody wants only the <payload>
      resolve(reader.result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
```

The `.split(',')[1]` is the entire reason this trips people up. `readAsDataURL` returns `data:application/pdf;base64,JVBERi0xL...`. `documentbody` wants just `JVBERi0xL...`. Forgetting the split sends the prefix as part of the body, which corrupts the file silently, Power Pages saves the annotation, the download works, but the file doesn't open.

## Step 3: POST to /_api/annotations

```javascript
function uploadFile(file, parentId, parentType) {
  var $li = $('<li class="list-group-item d-flex justify-content-between align-items-center"></li>')
    .append($('<span></span>').text(file.name))
    .append($('<span class="badge bg-secondary"></span>').text('Uploading...'));
  $('#uploadList').append($li);

  return fileToBase64(file).then(function (base64) {
    var payload = {
      filename:                              file.name,
      mimetype:                              file.type || 'application/octet-stream',
      documentbody:                          base64,
      subject:                               file.name,
      notetext:                              'Uploaded via portal'
    };
    payload['objectid_' + parentType + '@odata.bind'] = '/' + entitySetFor(parentType) + '(' + parentId + ')';

    return new Promise(function (resolve, reject) {
      webapi.safeAjax({
        type:        'POST',
        url:         '/_api/annotations',
        contentType: 'application/json',
        data:        JSON.stringify(payload),
        success: function (data, textStatus, xhr) {
          $li.find('.badge').removeClass('bg-secondary').addClass('bg-success').text('Uploaded');
          resolve();
        },
        error: function (xhr) {
          $li.find('.badge').removeClass('bg-secondary').addClass('bg-danger').text('Failed');
          $li.append($('<small class="text-danger ms-2"></small>').text(parseError(xhr)));
          reject(xhr);
        }
      });
    });
  });
}

// Entity logical name to entity set name mapping for the polymorphic objectid binding
function entitySetFor(logicalName) {
  var map = {
    contact:             'contacts',
    account:             'accounts',
    contoso_application: 'contoso_applications'
  };
  return map[logicalName] || (logicalName + 's');
}
```

Three field-naming traps in this payload:

| Field | Form | Common mistake |
|---|---|---|
| `documentbody` | base64 string, no `data:...` prefix | Sending the full data URL |
| `mimetype` | string | Falling back to empty when `file.type` is empty (older browsers), pass `application/octet-stream` |
| `objectid_<entity>@odata.bind` | **lowercase entity logical name** suffix | Using `objectid_Contact` (PascalCase), the polymorphic suffix is logical name (lowercase) |

## Step 4: Multi-file uploads

Two strategies:

**Serial**, simpler, friendlier on the server, predictable progress:

```javascript
function uploadAll(files) {
  var arr = Array.from(files);
  return arr.reduce(function (promise, file) {
    return promise.then(function () {
      return uploadFile(file, $('#parentId').val(), $('#parentType').val());
    });
  }, Promise.resolve());
}
```

**Parallel with concurrency cap**, faster on small files:

```javascript
function uploadAll(files, concurrency) {
  concurrency = concurrency || 3;
  var queue = Array.from(files);
  var inflight = [];

  function next() {
    while (inflight.length < concurrency && queue.length > 0) {
      var file = queue.shift();
      var p = uploadFile(file, $('#parentId').val(), $('#parentType').val())
        .finally(function () {
          inflight.splice(inflight.indexOf(p), 1);
          next();
        });
      inflight.push(p);
    }
    return Promise.all(inflight);
  }
  return next();
}
```

Stick with serial for files larger than ~1 MB, base64 encoding doubles the wire size, and parallel uploads of large files saturate the user's uplink without finishing faster.

Wire it up:

```javascript
$(function () {
  var $input = $('#fileInput');
  var $zone  = $('#dropZone');

  $zone.on('click keypress', function (e) {
    if (e.type === 'click' || e.key === 'Enter' || e.key === ' ') {
      $input.trigger('click');
    }
  });
  $input.on('change', function () { handleFiles(this.files); });
  $zone.on('dragover',  function (e) { e.preventDefault(); $zone.addClass('bg-light'); });
  $zone.on('dragleave', function ()  { $zone.removeClass('bg-light'); });
  $zone.on('drop',      function (e) {
    e.preventDefault();
    $zone.removeClass('bg-light');
    handleFiles(e.originalEvent.dataTransfer.files);
  });

  loadExisting();
});

function handleFiles(files) {
  var arr = Array.from(files).filter(function (f) {
    if (f.size > MAX_BYTES) {
      showAlert(f.name + ' exceeds the 10 MB limit.');
      return false;
    }
    if (f.type && ALLOWED_MIMES.indexOf(f.type) === -1) {
      showAlert(f.name + ' has an unsupported type (' + f.type + ').');
      return false;
    }
    return true;
  });
  if (arr.length === 0) return;
  uploadAll(arr).then(loadExisting);
}
```

## Step 5: Display attached files

Two approaches; choose by where the page is rendered:

**Server-side (initial render via Liquid + FetchXML)**, preferred when the list is the primary content:

```liquid
{% fetchxml notes_query %}
<fetch mapping="logical">
  <entity name="annotation">
    <attribute name="annotationid"></attribute>
    <attribute name="filename"></attribute>
    <attribute name="filesize"></attribute>
    <attribute name="createdon"></attribute>
    <filter>
      <condition attribute="objectid" operator="eq" value="{{ parent_id }}" />
      <condition attribute="isdocument" operator="eq" value="1" />
    </filter>
    <order attribute="createdon" descending="true" />
  </entity>
</fetch>
{% endfetchxml %}

<ul class="list-group">
  {% for n in notes_query.results.entities %}
    <li class="list-group-item">
      <a href="/_api/annotations({{ n.annotationid }})/documentbody/$value">
        {{ n.filename | escape }}
      </a>
      <small class="text-muted">{{ n.filesize | divided_by: 1024 }} KB</small>
    </li>
  {% endfor %}
</ul>
```

**Client-side (Web API GET)**, when you need to refresh after an upload without reloading:

```javascript
function loadExisting() {
  var parentId = $('#parentId').val();
  webapi.safeAjax({
    type: 'GET',
    url:  '/_api/annotations'
        + '?$select=annotationid,filename,filesize,createdon'
        + '&$filter=_objectid_value eq ' + parentId + ' and isdocument eq true'
        + '&$orderby=createdon desc',
    success: function (data) {
      var $list = $('#existingList').empty();
      if (data.value.length === 0) {
        $list.append('<li class="list-group-item text-muted">No files attached yet.</li>');
        return;
      }
      data.value.forEach(function (n) {
        var $li = $('<li class="list-group-item"></li>')
          .append($('<a></a>')
            .attr('href', '/_api/annotations(' + n.annotationid + ')/documentbody/$value')
            .text(n.filename));
        $list.append($li);
      });
    }
  });
}
```

## Common variations

### SharePoint integration auto-redirect

If SharePoint document management is enabled on the parent entity (set up at the Dataverse level, see [Manage SharePoint documents](https://learn.microsoft.com/power-pages/configure/manage-sharepoint-documents)), Dataverse routes attachment storage to SharePoint instead of into the annotation `documentbody`. The annotation itself is created as a metadata stub. **No client-side code change**, but the download URL is now SharePoint-hosted, and behavior depends on the user's SharePoint permissions, not their portal Web Role.

The Power Pages site settings that govern the SharePoint upload path are `SharePoint/MaxUploadSize` (per-file, default 10 MB, max 50 MB) and `SharePoint/MaxTotalUploadSize` (combined). There is no per-entity threshold setting; routing is controlled by whether SharePoint document management is turned on for the table.

### MIME type allowlist on the server

Client-side checks (Step 4 `ALLOWED_MIMES`) are UX, not security. Add a Dataverse plugin or business rule on the `annotation` table to reject disallowed `mimetype` values server-side.

### Max size enforcement

Three layers must agree. **There is no Power Pages site setting named `Documents/MaxFileSize`**, that name is a long-standing misremembering (likely a mash-up of the SharePoint/Azure Blob settings below). The actual layers and their canonical setting names are:

| Layer | Setting | Default | Where |
|---|---|---|---|
| Client-side (UX) | `MAX_BYTES` constant in JS | author-set | Recipe code |
| **Per-form upload limit (Studio)** | "Upload size limit per file (in KB)" on the form's Attachments panel | author-set | Power Pages design studio → Form → Attachments |
| **Notes storage (annotations)** | `Organization.MaxUploadFileSize` (Dataverse, env-level, **not** a Power Pages site setting) | 5 MB | Power Platform admin center → Environment → Settings → Email → Maximum file size; max 128 MB |
| **SharePoint integration** | `SharePoint/MaxUploadSize` site setting | 10 MB | Power Pages site setting; max 50 MB. Pair with `SharePoint/MaxTotalUploadSize` for combined cap. |
| **Azure Blob Storage Web API** | `Site/FileManagement/MaxFileSize` site setting (in KB) | 1 GB (`1048576`) | Power Pages site setting, only when using the Azure Blob Storage upload path |
| Enhanced upload UX toggle | `EnhancedFileUpload` site setting | new sites: on | Power Pages site setting; opt-in for older sites. Doesn't change size limits. |

When any one layer rejects, the user sees a different error per layer, match all layers to a consistent number. For Notes-storage uploads (the path this recipe uses), the **Dataverse `Organization.MaxUploadFileSize`** is the binding ceiling; the per-form Studio value clamps it lower for that specific form.

See [../data/site-settings.md](../data/site-settings.md#documents--file-upload-limits) for the canonical site-setting reference.

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Including the `data:...;base64,` prefix in `documentbody` | File saves but won't open | `.split(',')[1]` to strip the prefix |
| `objectid_<entity>` with PascalCase entity name | 400 "not a valid navigation property" | Use lowercase logical name: `objectid_contact`, not `objectid_Contact` |
| Annotation Table Permission scope = Global | Any user can attach to any record | Use Parent scope tied to the parent entity's permission |
| `Webapi/annotation/fields = *` | Sensitive note text exposed via GET | Whitelist only the fields you need |
| Large file (>5 MB) hits 413 | Upload silently fails | Raise Dataverse `Organization.MaxUploadFileSize` via Power Platform admin → Environment → Settings → Email; or enable SharePoint integration and use `SharePoint/MaxUploadSize`; or switch to Azure Blob Storage with `Site/FileManagement/MaxFileSize` |
| CSP blocks `blob:` URLs | Image previews fail in CSP-enabled portals | Add `img-src 'self' blob:` to the site's `Content-Security-Policy` site setting |
| `_objectid_value` filter shape | 400 in client-side list | Use the lookup-filter form `_objectid_value eq <guid>`, not `objectid eq <guid>` |
| `isdocument = false` annotations show up | Notes-only entries in the file list | Filter `isdocument eq true` to get only file annotations |
| Parallel uploads exhaust memory on mobile | Browser tab crashes | Stick to serial for files > 1 MB; cap concurrency at 2-3 for parallel |

## See also

- [../data/webapi-patterns.md](../data/webapi-patterns.md), `safeAjax`, file upload pattern, polymorphic `@odata.bind`
- [../data/site-settings.md](../data/site-settings.md), `Webapi/annotation/enabled`, `Webapi/annotation/fields`, `EnhancedFileUpload`, `SharePoint/MaxUploadSize`, `Site/FileManagement/MaxFileSize` (and the Dataverse env-level `Organization.MaxUploadFileSize` cap)
- [../data/permissions-and-roles.md](../data/permissions-and-roles.md), Parent-scope cascading, why annotation perms must inherit from parent
- [../data/dataverse-naming.md](../data/dataverse-naming.md), entity-set name vs logical name (relevant for `entitySetFor` lookups)
- [hybrid-form-with-safeajax.md](hybrid-form-with-safeajax.md), chaining a file upload after a record create

> Verified against Microsoft Learn 2026-04-29.
