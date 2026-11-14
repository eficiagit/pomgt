-- Deleting a document failed with a raw foreign-key error the moment it had
-- any uploaded version, e.g. "violates foreign key constraint
-- document_versions_document_id_fkey". Same safety posture as the other
-- delete_* RPCs: block when the document (or one of its versions) is cited
-- as formal evidence — a design approval or the documented source of a
-- customer requirement — otherwise cascade away its own versions and the
-- links pointing at it. A product revision's reference image is just a
-- visual aid, so it's detached (set to null) rather than blocking.
--
-- Note: this does not delete the underlying file from Supabase Storage —
-- only the pomgt.* rows. Orphaned storage objects are an acceptable,
-- pre-existing gap, not addressed here.
create or replace function pomgt.delete_document(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = pomgt, public
as $$
declare
  document_row pomgt.documents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;

  select * into document_row from pomgt.documents where id = p_document_id;
  if not found then
    raise exception 'Documento no encontrado';
  end if;
  if not pomgt.is_member(document_row.organization_id) then
    raise exception 'No tiene acceso a la organización de este documento';
  end if;

  if exists (
    select 1 from pomgt.design_approvals
    where document_id = p_document_id
       or document_version_id in (select id from pomgt.document_versions where document_id = p_document_id)
  ) then
    raise exception 'Este documento es evidencia de una aprobación de diseño registrada y no puede eliminarse';
  end if;

  if exists (
    select 1 from pomgt.customer_requirements
    where source_document_id = p_document_id
       or source_document_version_id in (select id from pomgt.document_versions where document_id = p_document_id)
  ) then
    raise exception 'Este documento es el origen de un requisito de cliente registrado y no puede eliminarse';
  end if;

  update pomgt.product_revisions
     set image_document_version_id = null
   where image_document_version_id in (select id from pomgt.document_versions where document_id = p_document_id);

  delete from pomgt.document_links
   where document_id = p_document_id
      or pinned_version_id in (select id from pomgt.document_versions where document_id = p_document_id);

  delete from pomgt.document_versions where document_id = p_document_id;

  delete from pomgt.documents where id = p_document_id;
end;
$$;

grant execute on function pomgt.delete_document(uuid) to authenticated;

notify pgrst, 'reload schema';
