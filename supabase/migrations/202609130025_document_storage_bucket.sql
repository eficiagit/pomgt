-- Uploading a document (from any screen: Documentos, the order wizard, a
-- production OP, etc.) failed with "La política de seguridad por registro
-- no permite esta operación." because the 'pomgt-documents' storage bucket
-- and its access policies were never created by any tracked migration.
--
-- Files are stored at "<organization_id>/<document_id>/v<version>/<name>"
-- (see lib/data/services/document_storage_service.dart), so access is
-- granted per object based on membership in the organization named by the
-- first path segment.

insert into storage.buckets (id, name, public)
values ('pomgt-documents', 'pomgt-documents', false)
on conflict (id) do nothing;

drop policy if exists "pomgt-documents read" on storage.objects;
create policy "pomgt-documents read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'pomgt-documents'
    and pomgt.is_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "pomgt-documents insert" on storage.objects;
create policy "pomgt-documents insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'pomgt-documents'
    and pomgt.is_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "pomgt-documents update" on storage.objects;
create policy "pomgt-documents update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'pomgt-documents'
    and pomgt.is_member((storage.foldername(name))[1]::uuid)
  )
  with check (
    bucket_id = 'pomgt-documents'
    and pomgt.is_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "pomgt-documents delete" on storage.objects;
create policy "pomgt-documents delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'pomgt-documents'
    and pomgt.is_member((storage.foldername(name))[1]::uuid)
  );
