-- report_document menyusun satu dokumen JSON lengkap untuk sebuah kunjungan:
-- info kunjungan, pelanggan, lokasi, teknisi, dan semua isi laporan.
-- Dipakai oleh API (detail laporan) dan oleh generator PDF.
CREATE OR REPLACE FUNCTION report_document(p_visit_id UUID) RETURNS JSONB
LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
  'visit', jsonb_build_object(
      'id', v.id, 'visit_type', v.visit_type, 'scheduled_date', v.scheduled_date,
      'status', v.status, 'notes', v.notes, 'technician_id', v.technician_id),
  'customer', jsonb_build_object('id', c.id, 'name', c.name),
  'site', jsonb_build_object('id', s.id, 'name', s.name, 'address', s.address,
      'latitude', s.latitude, 'longitude', s.longitude),
  'technician', CASE WHEN u.id IS NULL THEN NULL ELSE
      jsonb_build_object('id', u.id, 'name', u.name, 'code', u.technician_code) END,
  'pic', (SELECT jsonb_build_object('name', sc.name, 'phone', sc.phone, 'email', sc.email)
          FROM site_contacts sc WHERE sc.site_id = s.id ORDER BY sc.is_primary DESC, sc.name LIMIT 1),
  'report', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', r.id, 'report_no', r.report_no, 'started_at', r.started_at, 'finished_at', r.finished_at,
      'checkin_lat', r.checkin_lat, 'checkin_lng', r.checkin_lng, 'pic_name', r.pic_name,
      'general_notes', r.general_notes, 'review_notes', r.review_notes,
      'submitted_at', r.submitted_at, 'published_at', r.published_at, 'has_pdf', r.pdf_path IS NOT NULL,
      'findings', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', f.id, 'pest_type_id', f.pest_type_id, 'pest_name_id', p.name_id, 'pest_name_en', p.name_en,
            'pest_icon', p.icon, 'area_id', f.area_id, 'area_name', coalesce(a.name, f.area_text),
            'area_text', f.area_text, 'level', f.level, 'is_active', f.is_active, 'remarks', f.remarks,
            'attachments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', at.id, 'caption', at.caption)
                             ORDER BY at.created_at), '[]') FROM attachments at
                             WHERE at.owner_type = 'finding' AND at.owner_id = f.id)
          ) ORDER BY f.sort_order), '[]')
          FROM report_findings f JOIN pest_types p ON p.id = f.pest_type_id
          LEFT JOIN areas a ON a.id = f.area_id WHERE f.report_id = r.id),
      'treatments', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', t.id, 'method_id', t.method_id, 'method_name_id', m.name_id, 'method_name_en', m.name_en,
            'area_id', t.area_id, 'area_name', coalesce(a.name, t.area_text), 'area_text', t.area_text,
            'chemical_id', t.chemical_id, 'chemical_name', ch.trade_name, 'active_ingredient', ch.active_ingredient,
            'dose_text', t.dose_text, 'quantity_used', t.quantity_used, 'equipment', t.equipment
          ) ORDER BY t.sort_order), '[]')
          FROM report_treatments t JOIN treatment_methods m ON m.id = t.method_id
          LEFT JOIN areas a ON a.id = t.area_id LEFT JOIN chemicals ch ON ch.id = t.chemical_id
          WHERE t.report_id = r.id),
      'recommendations', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', rc.id, 'category', rc.category, 'risk_finding', rc.risk_finding,
            'recommendation', rc.recommendation, 'customer_status', rc.customer_status,
            'customer_note', rc.customer_note,
            'attachments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', at.id, 'caption', at.caption)
                             ORDER BY at.created_at), '[]') FROM attachments at
                             WHERE at.owner_type = 'recommendation' AND at.owner_id = rc.id)
          ) ORDER BY rc.sort_order), '[]')
          FROM report_recommendations rc WHERE rc.report_id = r.id),
      'station_checks', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', sc.id, 'station_id', sc.station_id, 'station_code', st.code, 'equipment_type', et.name,
            'area_name', a.name, 'status', sc.status, 'bait_consumption', sc.bait_consumption, 'finding', sc.finding
          ) ORDER BY st.code), '[]')
          FROM report_station_checks sc JOIN stations st ON st.id = sc.station_id
          JOIN equipment_types et ON et.id = st.equipment_type_id LEFT JOIN areas a ON a.id = st.area_id
          WHERE sc.report_id = r.id),
      'attachments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', at.id, 'caption', at.caption)
                       ORDER BY at.created_at), '[]') FROM attachments at
                       WHERE at.report_id = r.id AND at.owner_type = 'report'),
      'signatures', (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'id', sg.id, 'signer_role', sg.signer_role, 'signer_name', sg.signer_name, 'signed_at', sg.signed_at
          )), '[]') FROM signatures sg WHERE sg.report_id = r.id)
  ) END
)
FROM visits v
JOIN sites s ON s.id = v.site_id
JOIN customers c ON c.id = s.customer_id
LEFT JOIN users u ON u.id = v.technician_id
LEFT JOIN visit_reports r ON r.visit_id = v.id
WHERE v.id = p_visit_id
$$;
