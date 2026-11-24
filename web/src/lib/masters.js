// Konfigurasi kolom untuk halaman data master generik.
// type: text | number | bool | select (options statis) | ref (pilih dari resource lain) | tags
export const masters = {
  customers: {
    title: 'Pelanggan',
    fields: [
      { key: 'name', label: 'Nama perusahaan', required: true },
      { key: 'tax_id', label: 'NPWP' },
      { key: 'billing_address', label: 'Alamat penagihan' },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  sites: {
    title: 'Lokasi',
    fields: [
      { key: 'customer_id', label: 'Pelanggan', type: 'ref', ref: 'customers', refLabel: 'name', required: true },
      { key: 'name', label: 'Nama lokasi', required: true },
      { key: 'address', label: 'Alamat', required: true },
      { key: 'building_type_id', label: 'Jenis bangunan', type: 'ref', ref: 'building-types', refLabel: 'name',
        hint: 'Area bawaan dibuat otomatis sesuai jenis bangunan' },
      { key: 'latitude', label: 'Latitude', type: 'number', hideInTable: true },
      { key: 'longitude', label: 'Longitude', type: 'number', hideInTable: true },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  'site-contacts': {
    title: 'Kontak PIC',
    fields: [
      { key: 'name', label: 'Nama', required: true },
      { key: 'position', label: 'Jabatan' },
      { key: 'phone', label: 'No HP' },
      { key: 'email', label: 'Email' },
      { key: 'is_primary', label: 'PIC utama', type: 'bool', default: false },
    ],
  },
  areas: {
    title: 'Area',
    fields: [
      { key: 'name', label: 'Nama area', required: true },
      { key: 'zone', label: 'Zona', type: 'select', options: { internal: 'Dalam', external: 'Luar' }, default: 'internal' },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  stations: {
    title: 'Stasiun monitoring',
    fields: [
      { key: 'code', label: 'Kode', required: true, hint: 'Contoh: BS-01, ILT-01' },
      { key: 'equipment_type_id', label: 'Jenis alat', type: 'ref', ref: 'equipment-types', refLabel: 'name', required: true },
      { key: 'area_id', label: 'Area', type: 'ref', ref: 'areas', refLabel: 'name', refFilter: 'site_id' },
      { key: 'qr_value', label: 'Isi QR', readonly: true },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  'building-types': {
    title: 'Jenis bangunan',
    fields: [
      { key: 'name', label: 'Nama', required: true },
      { key: 'default_areas', label: 'Area bawaan', type: 'tags', hint: 'Pisahkan dengan koma' },
    ],
  },
  'pest-types': {
    title: 'Jenis hama',
    fields: [
      { key: 'name_id', label: 'Nama (Indonesia)', required: true },
      { key: 'name_en', label: 'Nama (Inggris)', required: true },
      { key: 'pest_group', label: 'Grup', required: true },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  'treatment-methods': {
    title: 'Metode pengendalian',
    fields: [
      { key: 'name_id', label: 'Nama (Indonesia)', required: true },
      { key: 'name_en', label: 'Nama (Inggris)', required: true },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  chemicals: {
    title: 'Bahan kimia',
    fields: [
      { key: 'trade_name', label: 'Nama dagang', required: true },
      { key: 'active_ingredient', label: 'Bahan aktif', required: true },
      { key: 'chemical_class', label: 'Golongan' },
      { key: 'registration_no', label: 'No registrasi' },
      { key: 'unit', label: 'Satuan', default: 'ml' },
      { key: 'active', label: 'Aktif', type: 'bool', default: true },
    ],
  },
  'chemical-doses': {
    title: 'Dosis standar',
    fields: [
      { key: 'chemical_id', label: 'Bahan kimia', type: 'ref', ref: 'chemicals', refLabel: 'trade_name', required: true },
      { key: 'method_id', label: 'Metode', type: 'ref', ref: 'treatment-methods', refLabel: 'name_id' },
      { key: 'dose_text', label: 'Dosis', required: true, hint: 'Contoh: 10 ml per 1 liter air' },
    ],
  },
  'equipment-types': {
    title: 'Jenis alat monitoring',
    fields: [
      { key: 'name', label: 'Nama', required: true },
      { key: 'code_prefix', label: 'Prefix kode', required: true },
    ],
  },
}
