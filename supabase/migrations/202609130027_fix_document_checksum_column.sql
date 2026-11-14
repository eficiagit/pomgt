-- Every file upload (Documentos, the order wizard, an OP, a BOM, etc.) failed
-- with "value too long for type character(1)": document_versions.checksum_sha256
-- was defined as character(1) instead of large enough to hold a SHA-256 hex
-- digest (64 characters, see lib/data/repositories/document_repository.dart).
alter table pomgt.document_versions
  alter column checksum_sha256 type varchar(64);

notify pgrst, 'reload schema';
