// Command seed membuat akun super admin pertama, dan dengan -demo juga data contoh.
//
//	go run ./cmd/seed -email admin@propestindo.co.id -password rahasia123
//	go run ./cmd/seed -demo
package main

import (
	"context"
	"flag"
	"log"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/config"
	"github.com/propestindo/pestcontrol/internal/db"
	"github.com/propestindo/pestcontrol/migrations"
)

func main() {
	email := flag.String("email", "admin@propestindo.local", "email super admin")
	password := flag.String("password", "admin12345", "password super admin")
	demo := flag.Bool("demo", false, "buat juga data contoh (pelanggan, lokasi, teknisi, kunjungan)")
	flag.Parse()

	ctx := context.Background()
	cfg := config.Load()
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool, migrations.FS); err != nil {
		log.Fatal(err)
	}

	mkUser := func(email, pass, name, role string, code, customerID any) string {
		hash, err := auth.HashPassword(pass)
		if err != nil {
			log.Fatal(err)
		}
		var id string
		err = pool.QueryRow(ctx, `INSERT INTO users (email, password_hash, name, role, technician_code, customer_id)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
			email, hash, name, role, code, customerID).Scan(&id)
		if err != nil {
			log.Fatal(err)
		}
		log.Printf("user %-11s %s / %s", role, email, pass)
		return id
	}
	mkUser(*email, *password, "Super Admin", auth.RoleSuperAdmin, nil, nil)
	if !*demo {
		return
	}

	var customerID, siteID string
	must := func(err error) {
		if err != nil {
			log.Fatal(err)
		}
	}
	must(pool.QueryRow(ctx, `INSERT INTO customers (name, billing_address) VALUES ('PT. Guna Sejahtera', 'Jl. Perintis Kemerdekaan No. 12, Jakarta') RETURNING id`).Scan(&customerID))
	must(pool.QueryRow(ctx, `INSERT INTO sites (customer_id, building_type_id, name, address)
		SELECT $1, id, 'Pabrik Cikarang', 'Jl. Industri Raya Blok B2, Cikarang' FROM building_types WHERE name='Pabrik' RETURNING id`,
		customerID).Scan(&siteID))
	_, err = pool.Exec(ctx, `
		INSERT INTO areas (site_id, name) SELECT $1, unnest(default_areas) FROM building_types WHERE name='Pabrik' ON CONFLICT DO NOTHING;`, siteID)
	must(err)
	_, err = pool.Exec(ctx, `INSERT INTO site_contacts (site_id, name, position, phone, is_primary) VALUES ($1, 'Sari Ramadhani', 'HSE Officer', '081200000000', true)`, siteID)
	must(err)
	_, err = pool.Exec(ctx, `INSERT INTO stations (site_id, area_id, equipment_type_id, code)
		SELECT $1, (SELECT id FROM areas WHERE site_id=$1 AND name=x.area), (SELECT id FROM equipment_types WHERE code_prefix=x.prefix), x.code
		FROM (VALUES ('Gudang','BS','BS-01'), ('Parkiran','BS','BS-02'), ('Perimeter Luar','BS','BS-03'), ('Pantry','ILT','ILT-01')) x(area, prefix, code)`, siteID)
	must(err)

	mkUser("admin.ops@propestindo.local", "admin12345", "Admin Operasional", auth.RoleAdmin, nil, nil)
	tech := mkUser("teknisi@propestindo.local", "teknisi123", "Ahmad Fauzi", auth.RoleTechnician, "P015", nil)
	mkUser("pic@gunasejahtera.local", "pelanggan123", "Sari Ramadhani", auth.RoleCustomer, nil, customerID)

	_, err = pool.Exec(ctx, `INSERT INTO visits (site_id, technician_id, visit_type, scheduled_date)
		VALUES ($1, $2, 'routine_monthly', current_date), ($1, $2, 'routine_monthly', current_date + 30)`, siteID, tech)
	must(err)
	log.Printf("data contoh dibuat: pelanggan %s, lokasi %s", customerID, siteID)
}
