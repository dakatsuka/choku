# File Upload Filename Safety

## Source

- URL: https://www.rfc-editor.org/rfc/rfc7578
- URL: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition
- URL: https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- URL: https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html
- Accessed: 2026-05-23

## Summary

Multipart `filename` values are client supplied metadata. RFC 7578 says
receivers must not use them blindly and must not use directory path information
that may be present. MDN gives similar operational guidance for
`Content-Disposition`: strip path information, avoid overwriting existing
files, avoid special files, and satisfy filesystem character and length
requirements.

OWASP recommends generating storage filenames server-side. If user filenames are
needed, applications should restrict length and allowed characters, avoid hidden
files and traversal patterns, and not let clients choose storage paths or
temporary filenames.

## Implications

Choku should keep raw multipart filenames available as metadata, but must not
derive storage paths from them automatically. Filename sanitization helpers are
appropriate as pure candidate/display-name utilities. Actual upload storage
policy, generated storage names, overwrite behavior, content validation, and
destination directories remain application-owned.
