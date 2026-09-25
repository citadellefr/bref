# Changelog

## Unreleased

- `opc`: read and write OPC packages, keeping untouched parts byte for byte.
- `internal/xmltok`: allocation-free XML tokenizer for document parts.
- `internal/xmlcanon`: canonical comparison of XML parts.
- `opc`: `[Content_Types].xml` keeps the order of its rules when rewritten.
- `tools/validate`: Open XML SDK validation of rewritten packages, in CI.
- `opc`: an entry renamed from backslashes takes the spelling of its override.
- corpus: Writer test documents from LibreOffice.
- `internal/prototype/pagination`: measures how closely Word's page breaks are reproduced.
